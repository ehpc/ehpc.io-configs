{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  system.stateVersion = "25.05"; # Do not touch
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Time
  time.timeZone = "Europe/Amsterdam";
  
  # Grub
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Networking
  networking.useDHCP = false;
  systemd.network.enable = true;

  # SSH
  services.sshd.enable = true;
}
