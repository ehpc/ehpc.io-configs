{ config, ... }:
{
  users.users.ehpc = {
    isNormalUser = true;
    home = "/home/ehpc";
    extraGroups = [
      "wheel"
      "podman"
    ];
    openssh.authorizedKeys.keyFiles = [
      config.sops.secrets."ehpc-public-key".path
    ];
  };
}
