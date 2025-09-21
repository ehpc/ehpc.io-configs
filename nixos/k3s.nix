{ lib, ... }:
let
  manifestsList = [
    ../k8s/ehpc-io-letsencrypt.yaml
    ../k8s/ehpc-io-namespace.yaml
    ../k8s/ehpc-io-dummy-service.yaml
    ../k8s/ehpc-io-https-redirect-middleware.yaml
    ../k8s/ehpc-io-http-ingress.yaml
    ../k8s/ehpc-io-headers-middleware.yaml
    ../k8s/ehpc-io-compress-middleware.yaml
    ../k8s/ehpc-io-https-ingress.yaml
    ../k8s/ehpc-io-main-page-service.yaml
    ../k8s/ehpc-io-main-page-deployment.yaml
    ../k8s/ehpc-io-main-page-hpa.yaml
  ];

  manifestsAttrs = builtins.listToAttrs (
    map (p: {
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
      "--write-kubeconfig-group=kube"
      "--write-kubeconfig-mode=644"
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
          installCRDs = true;
        };
      };
    };
    manifests = manifestsAttrs;
  };
}
