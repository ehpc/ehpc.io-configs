{ config, ... }:
{
  users.users.ehpc = {
    isNormalUser = true;
    home = "/home/ehpc";
    extraGroups = [
      "wheel"
      "podman"
      "docker"
      "kube"
    ];
  };
  environment.etc."ssh/authorized_keys.d/ehpc" = {
    source = config.sops.secrets."ehpc-public-key".path;
    mode = "0644";
  };
}
