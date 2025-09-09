{
  description = "ehpc.io NixOS configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    etc.url = "path:/etc/nixos";
    etc.flake = false;
  };

  outputs = { self, nixpkgs, etc, ... }:
  {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        (etc + "/hardware-configuration.nix")
        ./configuration.nix
        (etc + "/secret.nix")
        ./system-packages.nix
      ];
    };
  };
}
