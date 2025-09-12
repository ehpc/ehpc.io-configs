{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    wget
    age
  ];
}
