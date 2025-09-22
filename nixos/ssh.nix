{ ... }:
{
  services.openssh = {
    enable = true;
    ports = [ 4242 ];
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

  programs.ssh.startAgent = true;
  security.pam.sshAgentAuth.enable = true;
}
