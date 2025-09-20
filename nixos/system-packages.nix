{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    wget
    age
    sops
  ];

  programs.kubectl = {
    enable = true;
    kubeconfig = "/etc/rancher/k3s/k3s.yaml";
  };
}
