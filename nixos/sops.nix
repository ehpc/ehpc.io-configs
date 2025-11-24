{ ... }:
{
  sops.age.keyFile = "/etc/age/keys.txt";
  sops.defaultSopsFile = ../secrets.yaml;
  sops.secrets."ehpc-public-key" = { };
  sops.secrets."ipv4-address" = { };
  sops.secrets."ipv6-address" = { };
  sops.secrets."ipv4-gateway" = { };
  sops.secrets."ipv6-gateway" = { };
  sops.secrets."ngf-root-ca-base64-crt" = { };
  sops.secrets."ngf-root-ca-base64.key" = { };
}
