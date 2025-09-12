{ ... }:
{
  sops.age.keyFile = "/etc/age/keys.txt";
  sops.defaultSopsFile = ../secrets.yaml;
  sops.secrets.ehpc-public-key = { };
  sops.secrets.ipv4-address = { };
  sops.secrets.ipv6-address = { };
  sops.secrets.ipv4-gateway = { };
  sops.secrets.ipv6-gateway = { };
}
