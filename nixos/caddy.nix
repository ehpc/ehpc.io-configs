{ domain, ... }:
{
  services.caddy = {
    enable = true;
    virtualHosts.${domain}.extraConfig = ''
      encode zstd gzip

      handle /proxy-health {
        respond "ok" 200
      }

      handle_path /files/* {
        root * /srv/files
        file_server browse
      }

      handle {
        reverse_proxy 127.0.0.1:8080
      }

      header {
        -Server
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      }

      log {
        level INFO
        output stderr
        format console
      }
    '';
  };
  systemd.tmpfiles.settings."srv-files" = {
    "/srv/files".d = {
      mode = "0755";
      user = "caddy";
      group = "caddy";
    };
  };
}
