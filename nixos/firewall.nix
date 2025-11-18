{ ... }:
{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      4242
      80
      443
      6443
    ];
    allowedUDPPorts = [
      443
    ];
  };
}
