# A machine's memory, zswap in front of a swap file sized by the memory installed.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The swap file in MiB by the memory, RFC vr5lw, 2 GiB up to 2, the memory up to 8 and half
  # beyond, 8 to 16.
  memory = config.machine.memory;
  swap =
    if memory <= 2048 then
      2048
    else if memory <= 8192 then
      memory
    else
      lib.min 16384 (lib.max 8192 (memory / 2));
in
{
  boot.kernelParams = [
    # zswap before the swap file, a fifth of the memory at most, its coldest written back.
    "zswap.enabled=1"
    "zswap.max_pool_percent=20"
    "zswap.shrinker_enabled=1"
  ];

  # A file in a subvolume of its own, so no snapshot holds it; lz4 is a module, so the compressor is
  # set once the system is up rather than on the kernel's line.
  swapDevices = [
    {
      device = "/data/swap/swapfile";
      size = swap;
    }
  ];
  systemd = {
    tmpfiles.rules = [
      "w- /sys/module/zswap/parameters/compressor - - - - ${config.machine.swap.compressor}"
    ];
    services.mkswap-data-swap-swapfile.preStart = "[ -d /data/swap ] || ${pkgs.unstable.btrfs-progs}/bin/btrfs subvolume create /data/swap";
  };
}
