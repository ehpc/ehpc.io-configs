{ ... }:
{
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
}
