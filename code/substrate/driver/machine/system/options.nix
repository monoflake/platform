# What a machine's own flake sets, and nothing else, RFC vr5lw. A secret is a path to a file the
# machine holds, never its text.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  file = types.addCheck types.str (lib.hasPrefix "/");
in
{
  options = {
    machine = {
      disk = mkOption {
        type = types.str;
        description = "Block device to partition and install the system onto.";
        example = "/dev/vda";
      };
      keys = mkOption {
        type = types.listOf types.str;
        description = "SSH public keys authorized to log in as root.";
      };
      memory = mkOption {
        type = types.ints.positive;
        description = "Memory installed, in MiB, from which the swap file's size is derived.";
        example = 4096;
      };
      swap.compressor = mkOption {
        type = types.enum [
          "zstd"
          "lz4"
        ];
        default = "zstd";
        description = "Compressor zswap uses for swapped pages; lz4 for a weak processor.";
      };
      tailnet.authKeyFile = mkOption {
        type = types.nullOr file;
        default = null;
        description = "Path to a file containing a Tailscale auth key, used to join the tailnet at boot.";
      };
    };
    monoflake.driver.bindings = mkOption {
      type = types.listOf file;
      default = [ ];
      description = "Paths to files each containing a binding token for the driver.";
    };
  };

  config.assertions = [
    {
      assertion = config.machine.keys != [ ];
      message = "machine.keys must not be empty, or no SSH key could log in as root.";
    }
  ];
}
