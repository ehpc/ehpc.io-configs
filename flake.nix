{
  description = "ehpc.io NixOS configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    # Match the desktop's agent packages without updating the server package set.
    nixpkgs-tools.url = "github:nixos/nixpkgs/55bfb4d7437bd4e09ab7cba58a43bd68eb310044";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      home-manager,
      nixpkgs-tools,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      domain = "ehpc.io";
      pkgsStable = nixpkgs-stable.legacyPackages.${system};
      pkgsTools = import nixpkgs-tools {
        inherit system;
        overlays = [
          (final: prev: {
            playwright-cli = final.callPackage ./pkgs/playwright-cli.nix { pkgs = final; };
          })
        ];
      };
    in
    {
      overlays.default = final: prev: {
        longhornctl = prev.callPackage ./pkgs/longhornctl.nix { };
        # rke2 1.34.5 in nixos-unstable is broken (boringcrypto Go build fails its own version check)
        rke2 = pkgsStable.rke2;
        # helmfile: use upstream pre-built binary to avoid slow Go rebuilds when cache misses
        helmfile = prev.callPackage ./pkgs/helmfile.nix { };
      };

      nixosConfigurations.ehpc-io-vps = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit domain pkgsStable sops-nix;
        };
        modules = [
          { nixpkgs.overlays = [ self.overlays.default ]; }
          ./nixos/main.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit pkgsTools; };

            home-manager.users.ehpc = import ./home-manager/main.nix;
          }
          sops-nix.nixosModules.sops
        ];
      };
    };
}
