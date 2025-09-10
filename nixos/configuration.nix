{ ... }:

{
  system.stateVersion = "25.05";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  time.timeZone = "Europe/Amsterdam";

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  imports = [
    ./boot.nix
    ./network.nix
    ./ssh.nix
    ./users.nix
    ./firewall.nix
    ./system-packages.nix
  ];
}
