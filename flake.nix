{
  description = "ehpc.io NixOS configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # /etc as a flake input
    etc = {
      url = "path:/etc/nixos";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      etc,
      home-manager,
      ...
    }:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (etc + "/hardware-configuration.nix")
          ./nixos/configuration.nix
          (etc + "/secret.nix")
        ];
      };
      homeConfigurations."ehpc" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [ ./home.nix ];
      };
    };
}
