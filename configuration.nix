{ config, lib, pkgs, ... }:

{
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
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      ChallengeResponseAuthentication = false;
      X11Forwarding = false;
      AllowAgentForwarding = false;
      MaxAuthTries = 3;
      LoginGraceTime = "20s";
    };
  };
  services.sshd.enable = true;
  services.fail2ban.enable = true;

  # GC
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
