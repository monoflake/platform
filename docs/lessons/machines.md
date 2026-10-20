# Machines

Facts on the system a machine runs, each with its source; see `docs/lessons.md`.

## A machine's system, read 2026-10-19

**NixOS 26.05 "Yarara" is the stable release, out 2026-05-30**, with fixes and security updates
until 2026-12-31; 25.11 lost its security updates after 2026-06-30. Its stage 1 runs systemd by
default. So a machine installed now crosses a release within months. Asked of a machine's system, RFC
vr5lw. Sources: https://nixos.org/blog/announcements/2026/nixos-2605/ and
https://www.phoronix.com/news/NixOS-26.05-Released

**containerd is spoken from Rust by `containerd-client`**, gRPC bindings generated from
containerd's protobuf definitions, in containerd's own `rust-extensions` repository, reached at
`/run/containerd/containerd.sock`; `containerd-shim-protos` beside it holds the shim v2 protocol.
docs.rs failed to build 0.8.0's documentation and shows 0.6.0's. Asked of a machine's driver, RFC
vr5lw. Source: https://docs.rs/containerd-client

**containerd runs crun through runc's shim**: `runtime_type` `io.containerd.runc.v2`, with
`options.BinaryName` naming crun's binary. The shim calls its runtime as runc is called, so only a
runtime compatible with it runs so; Kata brings a shim of its own. Whether youki does is not found.
Asked by checklist C32. Sources: https://blog.nuvotex.de/crun/ and
https://git.causa-arcana.com/kotovalexarian-likes-github/moby--moby/commit/6de52a29a8e8fbe9639178a25f716bfe4532ff11

**A container outlives containerd's restart**: its shim is its parent once runc has made it, so it
runs on while containerd is down, though nothing is created or deleted until containerd returns.
Asked by C32. Sources: https://github.com/moby/moby/discussions/46449 and
https://forums.docker.com/t/the-parent-process-issue/142026

**Docker's live restore keeps containers running while its daemon is down, across patch releases
alone**: set `"live-restore": true` in `/etc/docker/daemon.json`; it is "only supported" across
`YY.MM.x`, not a `YY.MM` upgrade, and restores only while the bridge's addresses and the graph driver
are unchanged; a long outage can fill a container's log buffer and block its logging; standalone
containers alone, not Swarm's. Asked by checklist C32. Source:
https://docs.docker.com/engine/daemon/live-restore/

**Btrfs has two quotas**: qgroups, which walk back-references on writes and commits and slow as
snapshots grow, and simple quotas from Linux 6.7, `btrfs quota enable --simple`, which charge each
extent for good to the subvolume that made it and cost about what no quota does, but cannot tell
shared from exclusive use. Asked by B22. Sources: https://lwn.net/Articles/944371,
https://blogs.oracle.com/linux/btrfs-qgroup-quota-vs-simple-quota and
https://btrfs.readthedocs.io/en/latest/btrfs-quota.html
