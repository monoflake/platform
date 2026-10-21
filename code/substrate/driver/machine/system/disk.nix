# A machine's disk, RFC vr5lw: ext4 of 5 GB for the host, and btrfs, with simple quotas, for the rest.
# A BIOS boot partition and an EFI system partition stand before them, so one layout boots either way.
{ lib, ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    device = lib.mkDefault "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        efi = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        host = {
          size = "5G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
        data = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [
              "-f"
              "-O"
              "squota"
            ];
            mountpoint = "/data";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
