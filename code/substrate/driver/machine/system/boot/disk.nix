# A machine's disk, a BIOS boot and an EFI partition, 5 GB of ext4 for the host and btrfs with
# simple quotas for the rest, RFC vr5lw.
{ config, ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    device = config.machine.disk;
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
