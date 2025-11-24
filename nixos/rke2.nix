{
  config,
  lib,
  sops,
  ...
}:
let
  manifestsList = [
    ../k8s/nginx/namespace.yaml
    # ../k8s/helm-envoy-gateway.yaml

    # ../k8s/letsencrypt.yaml
    # ../k8s/gatewayclass.yaml
    # ../k8s/gateway.yaml
    # ../k8s/tls-redirect.yaml
    # ../k8s/www-redirect.yaml
    # ../k8s/client-traffic-policy.yaml

    # ../k8s/ehpc-io-namespace.yaml
    # ../k8s/ehpc-io-main-page-deployment.yaml
    # ../k8s/ehpc-io-main-page-service.yaml
    # ../k8s/ehpc-io-main-page-httproute.yaml
    # ../k8s/ehpc-io-backend-traffic-policy.yaml
    # ../k8s/ehpc-io-main-page-hpa.yaml
  ];

  manifests = map (p: {
    name = builtins.replaceStrings [ "../k8s/" "/" ] [ "" "-" ] (
      builtins.head (builtins.match ".*/k8s/(.*)" (toString p))
    );
    value = {
      source = p;
    };
  }) manifestsList;

  allManifests = [
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
