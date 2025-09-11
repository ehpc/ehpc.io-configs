{ pkgs, ... }:

{
  home.username = "ehpc";
  home.homeDirectory = "/home/ehpc";

  home.packages = [
    pkgs.binutils
    pkgs.git
  ];

  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "ehpc";
    userEmail = "ehpc@ehpc.io";
  };
}
