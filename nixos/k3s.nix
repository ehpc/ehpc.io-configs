{ ... }:
{
  users.groups.kube = { };
  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    extraFlags = toString [
      "--write-kubeconfig-group=kube"
      "--write-kubeconfig-mode=644"
    ];
    manifests.ehpc-io-letsencrypt.source = ./k8s/ehpc-io-letsencrypt.yaml;
    manifests.ehpc-io-namespace.source = ./k8s/ehpc-io-namespace.yaml;
    manifests.ehpc-io-ingress.source = ./web/ehpc-io-ingress.yaml;
    manifests.ehpc-io-middleware.source = ./web/ehpc-io-middleware.yaml;
    manifests.ehpc-io-service.source = ./web/ehpc-io-service.yaml;
    manifests.ehpc-io-deployment.source = ./web/ehpc-io-deployment.yaml;
    manifests.ehpc-io-hpa.source = ./web/ehpc-io-hpa.yaml;
  };
}
