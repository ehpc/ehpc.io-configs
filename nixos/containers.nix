{ lib, ... }:
{
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
  systemd.timers."podman-auto-update".timerConfig.OnCalendar = "*:0/15";

  systemd.services."podman-kube@".serviceConfig = {
    ExecStart = lib.mkForce [
      "/run/current-system/sw/bin/podman kube play --replace --service-container=true /etc/podman/%I.yaml"
    ];
    ExecStop = lib.mkForce [
      "/run/current-system/sw/bin/podman kube down /etc/podman/%I.yaml"
    ];
  };

  environment.etc."podman/ehpc.io.yaml".source = ../web/ehpc.io.yaml;

  systemd.services."podman-kube@ehpc.io.yaml".enable = true;
}
