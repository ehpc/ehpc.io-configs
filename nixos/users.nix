{ ... }:
{
  users.users.ehpc = {
    isNormalUser = true;
    home = "/home/ehpc";
    extraGroups = [
      "wheel"
      "podman"
    ];
  };
}
