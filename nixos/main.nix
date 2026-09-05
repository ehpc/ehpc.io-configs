{ lib, ... }:

{
  system.stateVersion = "25.05";

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  time.timeZone = "Europe/Amsterdam";

  nix.settings = {
    max-jobs = "auto";
    cores = 0;
    auto-optimise-store = true;
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cache.thalheim.io"
      "https://hyprland.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    trusted-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.thalheim.io"
      "https://hyprland.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSDs="
      "cache.thalheim.io-1:R7msbosLEZKrxk/lKxf9BTjOOH7Ax3H0Qj0/6wiHOgc="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  services.journald.settings.Journal = {
    SystemMaxUse = "500M";
    MaxRetentionSec = "2weeks";
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
