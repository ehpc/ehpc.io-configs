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
  ];
}
