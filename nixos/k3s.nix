{ ... }:
{
  users.groups.kube = { };
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
    manifests.ehpc-io-letsencrypt.source = ../k8s/ehpc-io-letsencrypt.yaml;
    manifests.ehpc-io-namespace.source = ../k8s/ehpc-io-namespace.yaml;
    manifests.ehpc-io-middleware.source = ../k8s/ehpc-io-middleware.yaml;
    manifests.ehpc-io-ingress.source = ../k8s/ehpc-io-ingress.yaml;
    manifests.ehpc-io-service.source = ../k8s/ehpc-io-service.yaml;
    manifests.ehpc-io-deployment.source = ../k8s/ehpc-io-deployment.yaml;
    manifests.ehpc-io-hpa.source = ../k8s/ehpc-io-hpa.yaml;
  };
}
