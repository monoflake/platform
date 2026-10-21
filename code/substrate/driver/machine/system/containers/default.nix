# A machine's containers, containerd on the data disk with the btrfs snapshotter.
{ pkgs, ... }:
{
  imports = [ ./secrets.nix ];

  # The btrfs snapshotter, each layer a subvolume a qgroup holds, RFC vr5lw.
  virtualisation.containerd = {
    enable = true;
    settings = {
      root = "/data/containerd";
      plugins."io.containerd.transfer.v1.local".unpack_config = [
        {
          platform = "linux/${pkgs.stdenv.hostPlatform.go.GOARCH}";
          snapshotter = "btrfs";
        }
      ];
      plugins."io.containerd.grpc.v1.cri".containerd.snapshotter = "btrfs";
    };
  };

  environment = {
    variables.CONTAINERD_SNAPSHOTTER = "btrfs";
    systemPackages = [ pkgs.unstable.btrfs-progs ];
  };
}
