# What a machine's own flake sets, and nothing else, RFC vr5lw: in technical words, but for what
# names the platform. A secret is a path to a file the machine holds, never its text, which the Nix
# store would show every user; how the file comes there is the machine's holder's.
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
        description = "The disk the machine's system and its workloads lie on, all of it, by its device.";
        example = "/dev/vda";
      };
      keys = mkOption {
        type = types.listOf types.str;
        description = "The SSH public keys that reach the machine as root, its holder's among them.";
      };
      tailnet.authKeyFile = mkOption {
        type = types.nullOr file;
        default = null;
        description = "A file holding a tailnet's auth key, with which the machine joins it at boot.";
      };
    };
    monoflake.driver.bindings = mkOption {
      type = types.listOf file;
      default = [ ];
      description = "Files each holding a binding's token, which a control made and the driver takes, RFC vr5lw; read once the driver is built.";
    };
  };

  config.assertions = [
    {
      assertion = config.machine.keys != [ ];
      message = "machine.keys is empty, so nothing would reach the machine once it is installed.";
    }
  ];
}
