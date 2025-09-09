{
  description = "ehpc.io NixOS configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs }:
  {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        ./system-packages.nix
        (if builtins.pathExists /etc/nixos/secret.nix then /etc/nixos/secret.nix else ./secret.nix)
      ];
    };
  };
}
