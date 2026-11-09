{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    kitty.terminfo
    nixfmt-rfc-style
    vim
    htop
    curl
    wget
    openssl
    age
    sops
    jq
    kubectl
    nfs-utils
    cryptsetup
    lvm2
    tailscale
    lazygit
    xdg-utils
  ];
}
