{
  description = "NixOS configuration for a Linux container host";

  inputs = {
    platform.url = "github:monoflake/platform";
    nixpkgs.follows = "platform/nixpkgs";
  };

  outputs =
    { platform, nixpkgs, ... }:
    {
      nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          platform.nixosModules.machine
          ./configuration.nix
        ];
      };
    };
}
