{ ... }:
{
  services.k3s.enable = true;
  services.k3s.role = "server";
  services.k3s.extraFlags = toString [
    "--disable=traefik"
  ];
  services.k3s.manifests.ehpc-io = ../web/ehpc-io-deployment.yaml;
}
