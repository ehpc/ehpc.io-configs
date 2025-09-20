{ domain, pkgs, ... }:
let
  caddyfile = pkgs.replaceVars ../web/Caddyfile {
    DOMAIN = domain;
  };
in
{
  environment.etc."caddy/Caddyfile".source = caddyfile;
  services.caddy = {
    enable = true;
    configFile = "/etc/caddy/Caddyfile";
  };
  systemd.tmpfiles.settings."srv-files" = {
    "/srv/files".d = {
      mode = "0755";
      user = "caddy";
      group = "caddy";
    };
  };
}
