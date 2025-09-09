{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git vim htop curl wget
  ];
}