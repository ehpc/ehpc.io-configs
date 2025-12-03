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

  users.groups.kube = { };

  services.rke2 = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik"
      "--disable=rke2-ingress-nginx"
      "--write-kubeconfig-group=kube"
      "--write-kubeconfig-mode=644"
      "--tls-san=ehpc.io"
    ];
    manifests = { };
  };

  environment.variables.KUBECONFIG = kubeconfig;

  systemd.services.apply-k8s-manifests = {
    description = "Apply Kubernetes manifests from git repo + sops templates";
    wants = [
      "rke2-server.service"
      "sops-nix.service"
    ];
    after = [
      "rke2-server.service"
      "sops-nix.service"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Environment = [
        "KUBECONFIG=${kubeconfig}"
        "PATH=${pkgs.kubectl}/bin:/run/current-system/sw/bin"
      ];
    };

    script = ''
      set -euo pipefail

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

      kustomize build "github.com/rancher/local-path-provisioner/deploy?ref=v0.0.32" | kubectl apply -f -

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

      echo "[apply-k8s-manifests] Applying dynamic manifest tailscale-operator-oauth"
      kubectl apply -f "${config.sops.templates."tailscale-operator-oauth".path}"

      echo "[apply-k8s-manifests] Applying helmfile"
      helmfile apply

      echo "[apply-k8s-manifests] Waiting for cert-manager-webhook..."
      kubectl -n cert-manager wait --for=condition=Available deploy/cert-manager-webhook --timeout=120s

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

      echo "[apply-k8s-manifests] Done"
    '';
  };
}
