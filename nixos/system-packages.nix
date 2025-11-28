{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    nixfmt-rfc-style
    vim
    htop
    curl
    wget
    age
    sops
    jq
    kubectl
    nfs-utils
    cryptsetup
    lvm2
    tailscale
  ];
}
