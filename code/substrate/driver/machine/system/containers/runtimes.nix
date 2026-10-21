# The runtimes containerd runs a container with, runc, crun and youki.
{ pkgs, ... }:
let
  inherit (pkgs.unstable) crun youki;
in
{
  virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri".containerd.runtimes = {
    crun = {
      runtime_type = "io.containerd.runc.v2";
      options.BinaryName = "${crun}/bin/crun";
    };
    youki = {
      runtime_type = "io.containerd.runc.v2";
      options.BinaryName = "${youki}/bin/youki";
    };
  };

  environment.systemPackages = [
    pkgs.unstable.runc
    crun
    youki
  ];
}
