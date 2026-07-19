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
    max-jobs = 1;
    auto-optimise-store = true;
    substituters = [
      "https://cache.nixos.org"
      "https://hyprland.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    trusted-substituters = [
      "https://hyprland.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=2weeks
  '';

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
