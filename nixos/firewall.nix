{ ... }:
{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      4242
      80
      443
      6443
      8543
    ];
    allowedUDPPorts = [
      443
    ];
    trustedInterfaces = [ "tailscale0" ];
  };
}
