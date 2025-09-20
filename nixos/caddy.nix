{ domain, pkgs, lib, ... }:
let
  caddyfile = pkgs.replaceVars ../web/Caddyfile {
    DOMAIN = domain;
  };
in
{
  environment.etc."caddy/caddy_config".source = caddyfile;
  services.caddy = {
    enable = true;
  };
  systemd.tmpfiles.settings."srv-files" = {
    "/srv/files".d = {
      mode = "0755";
      user = "caddy";
      group = "caddy";
    };
  };
}
