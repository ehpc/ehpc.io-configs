{ domain, ... }:
{
  services.caddy = {
    enable = true;
    virtualHosts.${domain}.extraConfig = ''
      encode zstd gzip
      @health path /proxy-health
      respond @health "ok" 200
      reverse_proxy 127.0.0.1:8080
      header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      }
    '';
  };
}
