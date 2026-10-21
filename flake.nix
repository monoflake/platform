{
  description = "NixOS module and template for a Linux container host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      unstable,
      disko,
      ...
    }:
    let
      system = ./code/substrate/driver/machine/system;
      linux = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      systems = linux ++ [ "aarch64-darwin" ];
      each = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      # Unstable beside the release, RFC vr5lw, as `pkgs.unstable`.
      nixosModules.machine = {
        imports = [
          disko.nixosModules.disko
          system
        ];
        nixpkgs.overlays = [
          (final: _: {
            unstable = import unstable { inherit (final.stdenv.hostPlatform) system; };
          })
        ];
      };

      templates.machine = {
        path = system + "/template";
        description = "NixOS configuration for a Linux container host";
      };

      # The template, as it stands, built as a machine of each system would be, so the module is
      # held to it; the system is what a machine's hardware configuration names.
      checks = nixpkgs.lib.genAttrs linux (s: {
        machine =
          (nixpkgs.lib.nixosSystem {
            modules = [
              self.nixosModules.machine
              (system + "/template/configuration.nix")
              { nixpkgs.hostPlatform = s; }
            ];
          }).config.system.build.toplevel;
      });

      formatter = each (pkgs: pkgs.nixfmt);
    };
}
