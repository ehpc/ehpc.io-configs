{
  pkgs,
  pkgsTools,
  config,
  ...
}:

{
  imports = [
    ./programs/claude
    ./programs/omp.nix
    (import ./programs/codex { inherit pkgs pkgsTools; })
  ];

  home.username = "ehpc";
  home.homeDirectory = "/home/ehpc";

  home.packages = with pkgs; [
    binutils
    git
    btop
    pkgsTools.herdr
    pkgsTools.playwright-cli
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

  programs.tmux = {
    enable = true;
    extraConfig = ''
      set-environment -g DISPLAY :0
      set -g mouse on
      set -g history-limit 10000
      set -sg escape-time 0
      set -g status-interval 5
      set -g set-clipboard on
    '';
  };
}
