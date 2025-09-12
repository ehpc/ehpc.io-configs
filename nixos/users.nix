{ config, ... }:
{
  users.users.ehpc = {
    isNormalUser = true;
    home = "/home/ehpc";
    extraGroups = [
      "wheel"
      "podman"
    ];
  };
  environment.etc."ssh/authorized_keys.d/ehpc".source = config.sops.secrets."ehpc-public-key".path;
}
