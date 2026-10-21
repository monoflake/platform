# Where a container's secrets live, a tmpfs containerd waits for along with the data disk.
{
  # A container's secrets, never swapped, root's alone, RFC vr5lw.
  fileSystems."/run/monoflake/secrets" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [
      "noswap"
      "mode=0700"
      "size=64M"
      "nosuid"
      "nodev"
      "noexec"
    ];
  };

  systemd.services.containerd.unitConfig.RequiresMountsFor = [
    "/data"
    "/run/monoflake/secrets"
  ];
}
