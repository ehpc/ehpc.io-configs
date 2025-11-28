{ config, ... }:
{
  services.nfs.server = {
    enable = true;
  };
  services.nfs.settings = {
    nfsd.udp = false;
    nfsd.vers3 = false;
    nfsd.vers4 = true;
    nfsd."vers4.0" = false;
    nfsd."vers4.1" = false;
    nfsd."vers4.2" = true;
  };
  services.openiscsi = {
    enable = true;
    name = "${config.networking.hostName}-initiatorhost";
  };
  systemd.services.iscsid.serviceConfig = {
    PrivateMounts = "yes";
    BindPaths = "/run/current-system/sw/bin:/bin";
  };
}
