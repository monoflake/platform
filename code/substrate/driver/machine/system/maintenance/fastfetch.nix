# fastfetch's configuration, its logo `logo.nix`, on unless `machine.maintenance` is off.
{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.machine.maintenance.enable {
  # The logo's colors are the viewer's own terminal's, `22` undoing fastfetch's bold; the modules
  # are fastfetch's defaults less what a server has no use for, both opened two lines down.
  environment.etc."xdg/fastfetch/config.jsonc".text = builtins.toJSON {
    logo = {
      type = "file";
      source = pkgs.writeText "logo.txt" (import ./logo.nix);
      padding = {
        top = 2;
        left = 1;
        right = 3;
      };
      color = {
        "1" = "22;34";
        "2" = "22;36";
        "3" = "22;37";
      };
    };
    modules = [
      "break"
      "break"
      "os"
      "host"
      "kernel"
      "uptime"
      "packages"
      "shell"
      "de"
      "wm"
      "wmtheme"
      "theme"
      "icons"
      "font"
      "cursor"
      "terminal"
      "terminalfont"
      "cpu"
      "gpu"
      "memory"
      "swap"
      "disk"
      "battery"
      "poweradapter"
      "break"
      "colors"
    ];
  };
}
