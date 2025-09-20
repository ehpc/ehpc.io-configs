{ ... }:
{
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
  systemd.timers."podman-auto-update".timerConfig.OnCalendar = "*:0/15";

  environment.etc."podman/ehpc-io.yaml".source = ../web/ehpc-io.yaml;
  systemd.services."podman-kube@/etc/podman/ehpc-io.yaml".enable = true;
}
