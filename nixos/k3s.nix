{ lib, ... }:
let
  manifestsList = [
    ../k8s/ehpc-io-letsencrypt.yaml
    ../k8s/ehpc-io-certificate.yaml
    ../k8s/ehpc-io-namespace.yaml
    ../k8s/ehpc-io-ingress.yaml
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
          installCRDs = true;
        };
      };

      haproxy-kubernetes-ingress = {
        enable = true;
        name = "kubernetes-ingress";
        repo = "https://haproxytech.github.io/helm-charts";
        hash = "sha256-8D3Od8YWnsKvtlbQRWmM/Rl30ZlOWa8/PFoje4V8MTA=";
        version = "1.44.6";
        values = {
          controller.ingressClass = "haproxy";
          controller.service.type = "LoadBalancer";
        };
      };
    };
    manifests = manifestsAttrs;
  };

  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
}
