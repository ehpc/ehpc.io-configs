{ pkgs, config, ... }:

{
  home.username = "ehpc";
  home.homeDirectory = "/home/ehpc";

  home.packages = with pkgs; [
    binutils
    git
    btop
  ];

  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "ehpc";
        email = "ehpc@ehpc.io";
      };
    };
  };

  programs.k9s.enable = true;
}
