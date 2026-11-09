{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.dkimpy ]);
  check = pkgs.writeText "audio-mail-check.py" (builtins.readFile ./mail-check.py);
in
pkgs.testers.runNixOSTest {
  name = "audio-mail";
  nodes.machine = { pkgs, ... }: {
    imports = [ ../nixos/mail.nix ];
    virtualisation.memorySize = 768;
    virtualisation.diskSize = 4096;
    users.users.audio-mail-client = {
      isNormalUser = true;
      extraGroups = [ "audio-mail" ];
    };
    environment.systemPackages = [ python pkgs.util-linux pkgs.iproute2 ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("postfix.service")
    machine.wait_for_unit("opendkim.service")
    machine.wait_for_unit("audio-mail.socket")
    machine.succeed("test -S /run/audio-mail/submit.sock")
    machine.succeed("test -f /var/lib/opendkim/keys/vps2026.private")
    machine.succeed("test $(stat -c %a /var/lib/opendkim/keys/vps2026.private) = 600")
    machine.fail("ss -lnt6 | grep -E ':25[[:space:]]'")
    machine.succeed("${python}/bin/python3 ${check} ${pkgs.postfix}/bin/sendmail", timeout=180)
  '';
}
