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

  programs.nix-ld.enable = true;

  zramSwap.enable = true;

  imports = [
    ./hardware-configuration.nix
    ./sops.nix
    ./boot.nix
    ./network.nix
    ./security.nix
    ./ssh.nix
    ./users.nix
    ./firewall.nix
    ./system-packages.nix
    ./nfs.nix
    ./tailscale.nix
    ./containers.nix
    ./helm.nix
    ./rke2.nix
  ];
}
