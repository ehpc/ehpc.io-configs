{
  description = "ehpc.io NixOS configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      domain = "ehpc.io";
    in
    {
      overlays.default = final: prev: {
        longhornctl = prev.callPackage ./pkgs/longhornctl.nix { };
      };

      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit domain;
        };
        modules = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          ./nixos/main.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.ehpc = import ./home-manager/main.nix;
          }
          sops-nix.nixosModules.sops
        ];
      };
    };
}
