{ ... }:
{
  security = {
    sudo = {
      enable = true;
      execWheelOnly = true;
      extraConfig = ''
        Defaults timestamp_timeout=30
      '';
    };
    polkit.enable = true;
  };
}
