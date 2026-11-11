{
  config,
  lib,
  sops,
  pkgs,
  ...
}:
let
  kubeconfig = "/etc/rancher/rke2/rke2.yaml";
  manifestsRoot = "/home/ehpc/ehpc.io-configs/k8s";
in
{
  sops.templates."nginx-gateway-ca" = {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: nginx-gateway-ca
        namespace: nginx-gateway
      type: kubernetes.io/tls
      data:
        tls.crt: ${config.sops.placeholder."ngf-root-ca-base64-crt"}
        tls.key: ${config.sops.placeholder."ngf-root-ca-base64.key"}
    '';
  };

  sops.templates."main-ip-address-pool" = {
    content = ''
      apiVersion: metallb.io/v1beta1
      kind: IPAddressPool
      metadata:
        name: main-pool
        namespace: metallb-system
      spec:
        addresses:
        - ${config.sops.placeholder."server-ip"}/32
    '';
  };

  sops.templates."grafana-admin-secret" = {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: grafana-admin-secret
        namespace: monitoring
      type: Opaque
      stringData:
        admin-user: ehpc
        admin-password: ${config.sops.placeholder."kawaii"}
    '';
  };

  sops.templates."grafana-contactpoints" = {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: grafana-contactpoints
        namespace: monitoring
      type: Opaque
      stringData:
        contactpoints.yaml: |
          apiVersion: 1
          contactPoints:
            - orgId: 1
              name: Telegram
              receivers:
                - uid: telegram
                  type: telegram
                  settings:
                    bottoken: ${config.sops.placeholder."telegram-bot-token"}
                    chatid: "${config.sops.placeholder."telegram-chat-id"}"
    '';
  };

  sops.templates."gandi-credentials" = {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: gandi-credentials
        namespace: cert-manager
      type: Opaque
      stringData:
        pat: ${config.sops.placeholder."gandi-domain-pat"}
    '';
  };

  sops.templates."tailscale-operator-oauth" = {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: operator-oauth
        namespace: tailscale
      stringData:
        client_id: ${config.sops.placeholder."tailscale-client-id"}
        client_secret: ${config.sops.placeholder."tailscale-client-secret"}
    '';
  };

  sops.templates."audio-modal-token" = {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: audio-modal-token
        namespace: default
      type: Opaque
      stringData:
        token-id: "${config.sops.placeholder."modal-token-id"}"
        token-secret: "${config.sops.placeholder."modal-token-secret"}"
    '';
  };

  sops.templates."audio-openrouter" = {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: audio-openrouter
        namespace: default
      type: Opaque
      stringData:
        OPENROUTER_API_KEY: "${config.sops.placeholder."openrouter-api-key"}"
    '';
  };

  sops.templates."audio-auth" = {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: audio-auth
        namespace: default
      type: Opaque
      stringData:
        AUTH_OTP_SECRET: "${config.sops.placeholder."audio-auth-otp-secret"}"
        AUTH_INVITE_SECRET: "${config.sops.placeholder."audio-auth-invite-secret"}"
    '';
  };

  users.groups.kube = { };

  services.rke2 = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik"
      "--disable=rke2-ingress-nginx"
      "--write-kubeconfig-group=kube"
      "--write-kubeconfig-mode=640"
      "--tls-san=ehpc.io"
      "--kube-apiserver-arg=default-watch-cache-size=50"
      "--kube-apiserver-arg=max-requests-inflight=200"
      "--kube-apiserver-arg=max-mutating-requests-inflight=100"
    ];
    manifests = { };
  };

  environment.variables.KUBECONFIG = kubeconfig;

  systemd.services.apply-k8s-manifests = {
    description = "Apply Kubernetes manifests from git repo + sops templates";
    wants = [ "rke2-server.service" ];
    # By default sops-nix installs secrets during NixOS activation, before services
    # start. Its optional systemd activation uses sops-install-secrets.service.
    requires = [ "audio-mail.socket" ] ++ lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
    after = [ "rke2-server.service" "audio-mail.socket" ]
      ++ lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = [
        "KUBECONFIG=${kubeconfig}"
        "PATH=/var/lib/rancher/rke2/bin:${pkgs.git}/bin:/run/current-system/sw/bin"
      ];
    };

    script = ''
      set -euo pipefail

      if [[ ! -r "${config.sops.templates."audio-modal-token".path}" || ! -r "${config.sops.templates."audio-openrouter".path}" || ! -r "${config.sops.templates."audio-auth".path}" || ! -r "${config.sops.secrets."audio-auth-otp-secret".path}" || ! -r "${config.sops.secrets."audio-auth-invite-secret".path}" ]]; then
        echo "[apply-k8s-manifests] Audio Secret templates are not ready; refusing to apply manifests." >&2
        exit 1
      fi

      # Check only key validity, never emit their contents or put them in argv.
      ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 ${./audio-render.py} --check-secrets \
        "${config.sops.secrets."audio-auth-otp-secret".path}" "${config.sops.secrets."audio-auth-invite-secret".path}" \
        || { echo "[apply-k8s-manifests] Audio auth keys must be distinct and at least 32 bytes." >&2; exit 1; }
      audio_mail_group=$(${pkgs.getent}/bin/getent group audio-mail) || { echo "[apply-k8s-manifests] audio-mail group unavailable." >&2; exit 1; }
      IFS=: read -r audio_mail_name _ audio_mail_gid _ <<< "$audio_mail_group"
      [[ "$audio_mail_name" == audio-mail && "$audio_mail_gid" =~ ^[0-9]+$ && "$audio_mail_gid" != 0 && -d /run/audio-mail ]] \
        || { echo "[apply-k8s-manifests] Invalid audio-mail group or socket directory." >&2; exit 1; }
      ${pkgs.python3}/bin/python3 -c 'import sys; n=int(sys.argv[1]); sys.exit(0 if 0 < n <= 2147483647 else 1)' "$audio_mail_gid" \
        || { echo "[apply-k8s-manifests] Audio mail group ID is out of range." >&2; exit 1; }

      echo KUBECONFIG=$KUBECONFIG

      echo "[apply-k8s-manifests] Waiting for API server..."
      for i in $(seq 1 60); do
        if kubectl get ns kube-system >/dev/null 2>&1; then
          echo "[apply-k8s-manifests] API is ready."
          break
        fi
        sleep 2
      done

      cd ${manifestsRoot}

      kubectl apply -k "github.com/rancher/local-path-provisioner/deploy?ref=v0.0.32"

      if ! kubectl get crd gatewayclasses.gateway.networking.k8s.io >/dev/null 2>&1; then
        echo "[apply-k8s-manifests] Applying Gateway API crds"
        kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=v2.2.1" | kubectl apply -f -
      fi

      if ! kubectl get crd nginxproxies.gateway.nginx.org >/dev/null 2>&1; then
        echo "[apply-k8s-manifests] Applying nginx crds"
        kubectl apply --server-side -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/main/deploy/crds.yaml
      fi

      echo "[apply-k8s-manifests] Applying 020-namespaces"
      kubectl apply -f 020-namespaces

      echo "[apply-k8s-manifests] Applying dynamic manifest grafana-admin-secret"
      kubectl apply -f "${config.sops.templates."grafana-admin-secret".path}"

      echo "[apply-k8s-manifests] Applying dynamic manifest grafana-contactpoints"
      kubectl apply -f "${config.sops.templates."grafana-contactpoints".path}"

      echo "[apply-k8s-manifests] Applying dynamic manifest tailscale-operator-oauth"
      kubectl apply -f "${config.sops.templates."tailscale-operator-oauth".path}"

      echo "[apply-k8s-manifests] Applying helmfile"
      # cert-manager is installed by helmfile itself, so its webhook only exists from
      # the second run onward. Whenever it does exist, wait for it before running
      # helmfile: a webhook that is still starting has no endpoints, which fails other
      # releases' Certificate/Issuer patches and aborts this script before any of the
      # manifests below get applied.
      if kubectl -n cert-manager get deploy cert-manager-webhook >/dev/null 2>&1; then
        echo "[apply-k8s-manifests] Waiting for existing cert-manager-webhook..."
        kubectl -n cert-manager wait --for=condition=Available deploy/cert-manager-webhook --timeout=120s
      fi
      helmfile apply

      echo "[apply-k8s-manifests] Waiting for cert-manager-webhook..."
      kubectl -n cert-manager wait --for=condition=Available deploy/cert-manager-webhook --timeout=120s

      echo "[apply-k8s-manifests] Applying dynamic manifest gandi-credentials"
      kubectl apply -f "${config.sops.templates."gandi-credentials".path}"

      echo "[apply-k8s-manifests] Applying dynamic manifest nginx-gateway-ca"
      kubectl apply -f "${config.sops.templates."nginx-gateway-ca".path}"

      echo "[apply-k8s-manifests] Applying 030-tailscale"
      kubectl apply -f 030-tailscale

      echo "[apply-k8s-manifests] Applying 040-metallb"
      kubectl apply -f 040-metallb

      echo "[apply-k8s-manifests] Applying dynamic manifest main-ip-address-pool"
      kubectl apply -f "${config.sops.templates."main-ip-address-pool".path}"

      echo "[apply-k8s-manifests] Applying 060-nginx"
      kubectl apply -f 060-nginx

      echo "[apply-k8s-manifests] Applying 080-server"
      kubectl apply -f 080-server

      echo "[apply-k8s-manifests] Applying 100-ehpc-io"
      kubectl apply -f 100-ehpc-io

      echo "[apply-k8s-manifests] Applying 110-dns-01-test"
      kubectl apply -f 110-dns-01-test

      # Flux receives the real host group through a Nix-owned ConfigMap. Its
      # workload Kustomization is created suspended on first bootstrap only.
      audio_tmp=$(${pkgs.coreutils}/bin/mktemp -d)
      trap '${pkgs.coreutils}/bin/rm -rf "$audio_tmp"' EXIT

      # Apply the ingress restriction before the app can trust forwarded IPs.
      # Enforcement must also be verified as a separate rollout prerequisite.
      kubectl apply -f ${./audio-network-policy.yaml}

      echo "[apply-k8s-manifests] Applying dynamic manifest audio-modal-token"
      kubectl apply -f "${config.sops.templates."audio-modal-token".path}"

      echo "[apply-k8s-manifests] Applying dynamic manifest audio-openrouter"
      kubectl apply -f "${config.sops.templates."audio-openrouter".path}"

      echo "[apply-k8s-manifests] Applying dynamic manifest audio-auth"
      kubectl apply -f "${config.sops.templates."audio-auth".path}"

      echo "[apply-k8s-manifests] Applying 120-audio common resources"
      kubectl apply -f 120-audio

      echo "[apply-k8s-manifests] Installing pinned scoped Flux controllers"
      kubectl apply --server-side --field-manager=audio-flux-components -f ${./flux-components.yaml}
      kubectl wait --for=condition=Established crd/gitrepositories.source.toolkit.fluxcd.io --timeout=120s
      kubectl wait --for=condition=Established crd/kustomizations.kustomize.toolkit.fluxcd.io --timeout=120s
      kubectl apply -f ${./audio-flux-bootstrap.yaml}
      kubectl -n flux-system create configmap audio-runtime \
        --from-literal="AUDIO_MAIL_GID=$audio_mail_gid" --dry-run=client -o yaml \
        | kubectl apply --server-side --field-manager=audio-runtime -f -

      # Never re-suspend a Kustomization that an operator has safely resumed.
      # A separate manager creates the one-time safety gate; Nix SSA omits it.
      audio_flux_existing=$(kubectl -n flux-system get kustomization audio --ignore-not-found -o name)
      if [[ -z "$audio_flux_existing" ]]; then
        ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 -c \
          'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); d["spec"]["suspend"]=True; yaml.safe_dump(d,open(sys.argv[2],"w"),sort_keys=False)' \
          ${./audio-flux-kustomization.yaml} "$audio_tmp/suspended.yaml"
        kubectl apply --server-side --field-manager=audio-bootstrap -f "$audio_tmp/suspended.yaml"
        kubectl apply --server-side --field-manager=audio-nix -f ${./audio-flux-kustomization.yaml}
        # Relinquish bootstrap ownership of all fields except the safety gate.
        printf '%s\n' 'apiVersion: kustomize.toolkit.fluxcd.io/v1' 'kind: Kustomization' \
          'metadata:' '  name: audio' '  namespace: flux-system' 'spec:' '  suspend: true' \
          > "$audio_tmp/gate.yaml"
        kubectl apply --server-side --field-manager=audio-bootstrap -f "$audio_tmp/gate.yaml"
      else
        kubectl apply --server-side --field-manager=audio-nix -f ${./audio-flux-kustomization.yaml}
      fi

      echo "[apply-k8s-manifests] Done"
    '';
  };
}
