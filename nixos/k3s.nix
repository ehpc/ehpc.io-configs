{ ... }:
{
  users.groups.kube = { };
  services.k3s.enable = true;
  services.k3s.role = "server";
  services.k3s.extraFlags = toString [
    "--disable=traefik"
    "--write-kubeconfig-group=kube"
    "--write-kubeconfig-mode=640"
  ];
  services.k3s.manifests.ehpc-io.source = ../web/ehpc-io-deployment.yaml;
}
