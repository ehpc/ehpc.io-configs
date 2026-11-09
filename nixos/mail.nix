{ lib, pkgs, ... }:
let
  senderAccess = pkgs.writeText "audio-mail-sender-access" ''
    /^bounce@auth\.ehpc\.io$/ OK
    /.*/ REJECT Envelope sender must be bounce@auth.ehpc.io
  '';
  headerChecks = pkgs.writeText "audio-mail-header-checks" ''
    if /^From:/
    !/^From:[[:space:]]*no-reply@auth\.ehpc\.io[[:space:]]*$/ REJECT From must be no-reply@auth.ehpc.io
    endif
  '';
in
{
  users.groups.audio-mail = { };
  users.users.mail-bounce = {
    isSystemUser = true;
    group = "mail-bounce";
    home = "/var/lib/mail-bounce";
    createHome = true;
  };
  users.groups.mail-bounce = { };

  services.opendkim = {
    enable = true;
    domains = "csl:auth.ehpc.io";
    selector = "vps2026";
    group = "postfix";
    settings = {
      Mode = "s";
      MacroList = "csl:{daemon_name}=ORIGINATING";
      RequiredHeaders = "yes";
      UMask = "007";
    };
  };
  # Generate the private key at runtime, never in the world-readable Nix store.
  systemd.services.opendkim = {
    preStart = lib.mkForce ''
      umask 077
      cd /var/lib/opendkim/keys
      if ! test -f vps2026.private; then
        ${pkgs.opendkim}/bin/opendkim-genkey -b 2048 -s vps2026 -d auth.ehpc.io
      fi
    '';
    serviceConfig.RuntimeDirectoryMode = "0750";
  };

  services.postfix = {
    enable = true;
    setSendmail = false;
    postmasterAlias = "mail-bounce";
    extraAliases = "bounce: mail-bounce\n";
    localRecipients = [ "bounce@auth.ehpc.io" "postmaster@auth.ehpc.io" ];
    settings.main = {
      myhostname = "mail.ehpc.io";
      mydomain = "auth.ehpc.io";
      myorigin = "auth.ehpc.io";
      mydestination = [ "auth.ehpc.io" ];
      inet_protocols = "ipv4";
      inet_interfaces = "all";
      mynetworks = [ "127.0.0.1/32" ];
      authorized_submit_users = "root";
      smtp_helo_name = "mail.ehpc.io";
      smtp_tls_security_level = "encrypt";
      smtpd_relay_restrictions = "reject_unauth_destination";
      smtpd_recipient_restrictions = "reject_unlisted_recipient";
      message_size_limit = 1048576;
      mail_spool_directory = "/var/spool/mail";
      mailbox_size_limit = 16777216;
      queue_minfree = 1073741824;
      smtpd_client_message_rate_limit = 30;
      smtpd_client_recipient_rate_limit = 60;
      maximal_queue_lifetime = "2d";
      bounce_queue_lifetime = "2d";
      smtpd_client_connection_count_limit = 10;
      smtpd_client_connection_rate_limit = 30;
    };
    settings.master.audio-submit = {
      type = "unix";
      command = "smtpd";
      args = [
        "-o" "smtpd_relay_restrictions=check_sender_access,regexp:${senderAccess},reject_unauth_destination"
        "-o" "smtpd_sender_restrictions=check_sender_access,regexp:${senderAccess}"
        "-o" "cleanup_service_name=audio-cleanup"
        "-o" "smtpd_milters=unix:/run/opendkim/opendkim.sock"
        "-o" "milter_default_action=tempfail"
        "-o" "milter_macro_daemon_name=ORIGINATING"
      ];
    };
    settings.master.audio-cleanup = {
      private = false;
      maxproc = 0;
      command = "cleanup";
      args = [ "-o" "header_checks=regexp:${headerChecks}" ];
    };
  };

  systemd.tmpfiles.rules = [ "d /run/audio-mail 0750 root audio-mail -" ];
  systemd.sockets.audio-mail = {
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/audio-mail/submit.sock";
      SocketUser = "root";
      SocketGroup = "audio-mail";
      SocketMode = "0660";
      Service = "audio-mail.service";
    };
  };
  systemd.services.audio-mail = {
    description = "Restricted audio SMTP socket bridge";
    requires = [ "postfix.service" ];
    after = [ "postfix.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd /var/lib/postfix/queue/private/audio-submit";
      User = "root";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };
}
