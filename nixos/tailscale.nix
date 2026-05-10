{ ... }:
{
  services.tailscale = {
    enable = true;
    extraSetFlags = [
      "--ssh"
    ];
  };
}
