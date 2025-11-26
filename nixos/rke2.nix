{
  config,
  lib,
  sops,
  ...
}:
let
  namespacePaths = [
    ../k8s/nginx/namespace.yaml
    ../k8s/ehpc-io/namespace.yaml
  ];

  manifestPaths = [
    ../k8s/nginx/gateway-crds.yaml # https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/experimental?ref=v2.2.1
    ../k8s/system/cert-manager.yaml

    ../metallb/metallb.yaml

    ../k8s/nginx/issuer.yaml
    ../k8s/nginx/agent-certificate.yaml
    ../k8s/nginx/server-certificate.yaml

    ../k8s/nginx/ngf.yaml

    ../k8s/letsencrypt.yaml
    ../k8s/gateway.yaml

    ../k8s/tls-redirect.yaml
    ../k8s/www-redirect.yaml
    # ../k8s/client-traffic-policy.yaml

    ../k8s/ehpc-io/main-page-deployment.yaml
    ../k8s/ehpc-io/main-page-service.yaml
    ../k8s/ehpc-io/main-page-httproute.yaml
    # ../k8s/ehpc-io/backend-traffic-policy.yaml
    ../k8s/ehpc-io/main-page-hpa.yaml
  ];

  manifestPathToDict = path: {
    name = builtins.replaceStrings [ "../k8s/" "/" ] [ "" "-" ] (
      builtins.head (builtins.match ".*/k8s/(.*)" (toString path))
    );
    value = {
      source = path;
    };
  };

  namespaces = map manifestPathToDict namespacePaths;
  manifests = map manifestPathToDict manifestPaths;

  allManifests =
    namespaces
    ++ [
      {
        name = "nginx-gateway-ca.yaml";
        value = {
          source = config.sops.templates."nginx-gateway-ca".path;
        };
      }
    ]
    ++ manifests;

  allManifestsAttrs = builtins.listToAttrs allManifests;
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

  users.groups.kube = { };

  services.k3s.enable = false;

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
    manifests = allManifestsAttrs;
  };

  environment.variables.KUBECONFIG = "/etc/rancher/rke2/rke2.yaml";
}
