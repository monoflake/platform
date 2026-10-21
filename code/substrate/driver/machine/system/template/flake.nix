{
  description = "NixOS configuration for a Linux container host";

  inputs = {
    platform.url = "github:monoflake/platform";
    nixpkgs.follows = "platform/nixpkgs";
  };

  outputs =
    { platform, nixpkgs, ... }:
    {
      # The system is the hardware configuration's, `nixpkgs.hostPlatform`.
      nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
        modules = [
          platform.nixosModules.machine
          ./configuration.nix
        ];
      };
    };
}
