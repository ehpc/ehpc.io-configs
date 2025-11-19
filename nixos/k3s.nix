{ lib, ... }:
let
  manifestsList = [

    ../k8s/letsencrypt.yaml
    ../k8s/gatewayclass.yaml
    ../k8s/gateway.yaml
    ../k8s/tls-redirect.yaml
    ../k8s/www-redirect.yaml
    ../k8s/client-traffic-policy.yaml

    ../k8s/ehpc-io-namespace.yaml
    ../k8s/ehpc-io-main-page-deployment.yaml
    ../k8s/ehpc-io-main-page-service.yaml
    ../k8s/ehpc-io-main-page-httproute.yaml
    ../k8s/ehpc-io-backend-traffic-policy.yaml
    ../k8s/ehpc-io-main-page-hpa.yaml
  ];

  manifestsAttrs = builtins.listToAttrs (
    [
      {
        name = "envoy-gateway";
        value = {
          source = builtins.fetchurl {
            url = "https://github.com/envoyproxy/gateway/releases/download/v1.6.0/install.yaml";
            sha256 = "b622097b5df36d2d26e40fce5e9dada26f61c73884b211b33016898b3c667321";
          };
        };
      }
    ]
    ++ map (p: {
      name = lib.removeSuffix ".yaml" (baseNameOf (toString p));
      value = {
        source = p;
      };
    }) manifestsList
  );
in
{
  users.groups.kube = { };
  systemd.services.k3s.serviceConfig.LimitNOFILE = 1048576;
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik"
      "--write-kubeconfig-group=kube"
      "--write-kubeconfig-mode=644"
      "--tls-san=ehpc.io"
    ];
    autoDeployCharts = {
      cert-manager = {
        enable = true;
        name = "cert-manager";
        targetNamespace = "cert-manager";
        createNamespace = true;
        repo = "https://charts.jetstack.io";
        hash = "sha256-2t33r3sfDqqhDt15Cu+gvYwrB4MP6/ZZRg2EMhf1s8U=";
        version = "v1.18.2";
        values = {
          crds.enabled = true;
          config = {
            apiVersion = "controller.config.cert-manager.io/v1alpha1";
            kind = "ControllerConfiguration";
            enableGatewayAPI = true;
          };
        };
      };
    };
    manifests = manifestsAttrs;
  };

  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
}
