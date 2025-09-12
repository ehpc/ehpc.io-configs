{ config, ... }:
{
  networking.useDHCP = false;
  systemd.network.enable = true;

  sops.templates."10-wan".content = ''
    [Match]
    Name=ens3

    [Network]
    Address=${config.sops.placeholder."ipv4-address"}
    Address=${config.sops.placeholder."ipv6-address"}
    Gateway=${config.sops.placeholder."ipv4-gateway"}

    [Route]
    Gateway=${config.sops.placeholder."ipv6-gateway"}
    GatewayOnLink=true
  '';

  environment.etc."systemd/network/10-wan.network".source = config.sops.templates."10-wan".path;

  systemd.services.systemd-networkd.wants = [
    "sops-nix.service"
  ];
  systemd.services.systemd-networkd.after = [
    "sops-nix.service"
  ];
}
