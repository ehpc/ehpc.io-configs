{ ... }:
{
  networking.useDHCP = false;
  systemd.network.enable = true;

  systemd.network.networks."10-wan" = {
    matchConfig.Name = "ens3";
  };
}
