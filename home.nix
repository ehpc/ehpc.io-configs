{ ... }:

{
  home.username = "ehpc";
  home.homeDirectory = "/home/ehpc";

  home.packages = [
  ];

  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "ehpc";
    userEmail = "ehpc@ehpc.io";
  };
}
