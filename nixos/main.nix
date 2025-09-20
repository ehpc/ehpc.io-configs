{ ... }:

{
  system.stateVersion = "25.05";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  time.timeZone = "Europe/Amsterdam";

  nix.settings = {
    max-jobs = 1;
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  imports = [
    ./hardware-configuration.nix
    ./sops.nix
    ./boot.nix
    ./network.nix
    ./ssh.nix
    ./users.nix
    ./firewall.nix
    ./system-packages.nix
    ./containers.nix
    ./k3s.nix
    ./caddy.nix
  ];
}
