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

  networking.firewall.extraInputRules = ''
    tcp dport 4242 ct state new limit rate over 5/minute burst 10 packets drop
  '';
}
