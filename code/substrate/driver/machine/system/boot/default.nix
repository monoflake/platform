# How a machine boots, GRUB on BIOS and EFI and a console on the serial line and the screen.
{ pkgs, ... }:
let
  # The serial console, a PC's first UART or an Arm machine's PL011.
  serial = if pkgs.stdenv.hostPlatform.isAarch64 then "ttyAMA0" else "ttyS0";
in
{
  imports = [ ./disk.nix ];

  boot = {
    # BIOS and EFI on a PC; EFI alone on Arm, which has no BIOS GRUB, so its partition idles.
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      configurationLimit = 3;
    };
    kernelParams = [
      "console=${serial},115200n8"
      "console=tty0"
    ];
  };
}
