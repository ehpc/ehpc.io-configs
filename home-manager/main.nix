{ pkgs, ... }:

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
    userName = "ehpc";
    userEmail = "ehpc@ehpc.io";
  };

  home.sessionVariables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
}
