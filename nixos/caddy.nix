{ domain, ... }:
{
  services.caddy = {
    enable = true;
    virtualHosts.${domain}.extraConfig = ''
      encode zstd gzip

      @caddyhealth path_exact /proxy-health
      handle @caddyhealth {
        respond "ok" 200
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

      log
    '';
  };
}
