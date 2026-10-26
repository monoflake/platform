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
runtime compatible with it runs so; Kata brings a shim of its own. **youki does too**, tried on
2026-10-21: youki 0.7.0 under containerd 2.4.1's `io.containerd.runc.v2`, by `BinaryName`, ran
alpine on the btrfs snapshotter in cgroup v2, as runc and crun did beside it. Sources: https://blog.nuvotex.de/crun/ and
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

## A machine tried, 2026-10-20

Measured on one virtual machine, two cores and 3.4 GB of memory, BIOS, reinstalled to NixOS 26.05,
Linux 6.18.57, btrfs-progs 6.19.1, to answer B23.

**A NixOS set is about 1.1 GiB once trimmed**, `nix path-info -Sh` of the system: the installer's
default 1.1 GiB; with containerd, runc, crun, nftables and the tailnet 1.4 GiB; trimmed -- no git, no
documentation, crun built without criu and libkrun, no shell but bash -- 1.0 GiB, and 1.1 GiB with
workerd. The largest paths left are the kernel's modules, 144 MiB, workerd, 133 MiB, containerd, 95
MiB, and the CNI plugins, 71 MiB.

**Python comes in through what a server does not need**: nixpkgs' crun links criu, which holds
Python 3, 295 MiB in all against 76 MiB without it and libkrun; fish holds it too, for its
completions, and git holds both it and perl. crun's derivation adds `-lcriu` to `NIX_LDFLAGS` whatever
its inputs, so dropping criu means dropping that flag as well, or its configure finds no working C
compiler.

**A machine that boots by BIOS keeps perl**: NixOS installs GRUB by `install-grub.pl`, so the
`perlless` profile's forbidden dependencies fail its build. Only `system.forbiddenDependenciesRegexes`
need be lifted; the rest of the profile holds.

**workerd is not in nixpkgs 26.05**: Cloudflare's own build, from the npm package
`@cloudflare/workerd-linux-64`, is one 135 MiB executable linking glibc alone, which
`autoPatchelfHook` makes run.

**A qgroup above subvolumes holds their limit under simple quotas**: with `btrfs quota enable
--simple`, a level-1 qgroup limited to 1 GiB over two subvolumes refuses the write that takes their
sum past it, `EDQUOT`, and a level-2 qgroup above that one holds its own limit as well.

**A subvolume joins a qgroup only when told**: `btrfs subvolume create` and `btrfs subvolume
snapshot` take `-i <qgroup>`; without it a new subvolume, a snapshot of a member among them, is in
none. `btrfs qgroup assign` adds one already made, and under simple quotas the parent's usage counts
it at once, with no rescan.

**An extent stays charged to the subvolume that wrote it**: a snapshot costs nothing when taken, and
what is written into it is charged to it. Deleting the subvolume a snapshot came from leaves its
qgroup, shown as `<squota space holder>`, and its charge in every parent, until the last extent it
wrote is freed.

**A NixOS installed from a flake holds nixpkgs' source and Python unless told not to**: its nix
registry and `NIX_PATH` pin nixpkgs' source, 197 MiB, and `nixos-rebuild-ng` brings Python 3, 128
MiB. A machine that downloads its sets and builds none sets `nixpkgs.flake.setNixPath` and
`setFlakeRegistry` false and `system.disableInstallerTools` true, and is switched from outside by
`nixos-rebuild-ng --target-host`. So the machine's system measured 1.2 GiB installed, and its ext4 of
5 GB held 1.4 GB once it had rebooted and collected its garbage; until a reboot, what the processes
of the generation before run keeps that generation's paths alive.

**nixos-anywhere installs a machine from a flake over SSH**, `--build-on remote` for a Mac that cannot
build Linux, partitioning by disko. `--copy-host-keys` keeps the SSH host keys, and `--extra-files`
with `--chown` carries `/var/lib/tailscale`, so the machine came back to its tailnet as the same node.
A flake read as `path:` from macOS's temporary directory needs its real path, `/private/var/...`, as
Nix refuses `/var`, a symlink.

**Far from the machine, nixos-anywhere is better left at its kexec**, tried on 2026-10-21 with 1.13.0
on an aarch64 machine reached through a jump host across the Pacific. It evaluates where it runs and
sends every derivation over SSH one at a time, so 1,652 of them took 26 minutes and the connection
dropped before disko began. In the installer the kexec left running, the machine's own flake copied
over, `disko --mode destroy,format,mount --flake` then `nixos-install --flake`, run under
`systemd-run` so no SSH session holds them, took 3 minutes, fetching everything from the cache. The
installer keeps the old system's SSH host keys, so copying `/etc/ssh/ssh_host_*` into `/mnt` keeps
them too. A tarball made on macOS carries the Mac's user id onto every directory in its path and
AppleDouble `._*` files beside each one, so a carried `/var/lib/tailscale` needs `/var` and
`/var/lib` given back to root and those files deleted, or the tarball made with
`COPYFILE_DISABLE=1` and `--uid 0 --gid 0`. `nixos-install` leaves its build behind in the store,
900 MiB of the 5 GB ext4, which a garbage collection after the first boot frees.

**A path unit watching the system profile's link never fires**, tried on 2026-10-21 with systemd
260: Nix replaces `/nix/var/nix/profiles/system` by renaming a new link over it, and inotify
follows the old link to its target, which does not change. `PathChanged=` on the directory fires
once for a rename into it, and not again for the links the collection it starts deletes there. A
command `systemd-run` starts has no `PATH` on NixOS, so a test of one names each program by its
path under `/run/current-system/sw/bin`, or it tests nothing.

**A machine's own firewall can look like the provider's**: SYNs to port 22 that time out from
everywhere may still reach the machine. A capture on its interface, an `AF_PACKET` socket where
no tcpdump is installed, shows whether they arrive and whether any SYN-ACK leaves; here they
arrived, and an nftables table of the old system's, with an input policy of drop, answered none.

**NixOS laid over a running Debian by `NIXOS_LUSTRATE` failed to boot** on a machine running Docker
and a firewall of its own: Debian's units, `networking.service` among them, still started, found the
loader replaced by NixOS's `stub-ld`, and the emergency shell could not start. A machine is
reinstalled from the provider's image by https://github.com/bin456789/reinstall instead, `nixos
26.05 --username root --ssh-key <key>`, which installs NixOS through its own netboot.

**reinstall's own NixOS install can die in `nix-build`**, tried on 2026-10-25 with reinstall at
01e1e259: in its Alpine its nix 2.34.9 hit a bus error in `nix-build` itself, twice at the same
place on an Oracle Ampere machine with 20 GB of memory free and the disk nearly empty, and once on a
1 GB x86 machine while it fetched from the cache, so it is intermittent and not tied to the
architecture; three other x86 machines of about 1 GB, two at Oracle and one at Azure, installed
through the same script that night. The Ampere machine's kexec from Ubuntu into the 26.05 installer
had never answered on SSH either. Nothing needs evaluating on the machine, though: the system is
built elsewhere and copied into reinstall's Alpine, which installs it. disko's own script needs 445
MiB in the store, more than a 1 GB machine's tmpfs holds, so the six machines installed that night
were partitioned by `sgdisk` with disk.nix's labels in disko's order, and formatted by hand. Alpine
there has no udev, so `/dev/disk/by-partlabel` appears only after `mdev -s`; eudev added instead
deletes the partition nodes a repartitioning makes. reinstall's nix lives on the disk that is wiped,
so its closure is moved to the tmpfs first, and `nixos-install` is not in a system's closure, so
`nixos-install-tools` is copied beside it. That Alpine opens a swap file on `/os` after a failed
install, so `swapoff -a` comes before `/os` is unmounted.

**A copy into a machine's store that breaks can leave its nix-daemon holding the path's lock**,
seen on 2026-10-25: two copies across the Pacific dropped together, the daemon each had started
on its target kept running, and the copy run again waited on that path with nothing moving until
the old daemon was killed. Copied through a jump host on the tailnet instead, they did not drop.

**A machine installed with public SSH closed is locked out until it is on the tailnet**, seen on
2026-10-25: monoflake/machine's module trusts the tailnet alone, so a new machine booted to its
login prompt and answered nothing on 22, and only the provider's console reached it; on Oracle
the GRUB menu shows on the VNC console alone, not the serial one. A new machine's first
configuration opens SSH for its install, monoflake/cloud's `docs/upgrades.md`.

**A small provider's virtual machine may offer no DHCP and no router advertisement**, seen on
2026-10-26: a DHCP discover went unanswered three times, no router advertisement came in a minute
nor to a solicitation, and the Debian it ran held its addresses only in netplan, written by
cloud-init from the provider's NoCloud seed, an iso9660 disk labeled `cidata` left attached. A
machine configured for DHCP alone would come up there with no network, so such a machine reads that
seed at boot, monoflake/machine's `docs/network.md`.

**U-Boot reads ext4 without replaying its journal**, seen on 2026-10-25 on a board booted from an
extlinux `/boot`: power was lost right after a switch had rewritten `extlinux.conf`, Linux then
read the new default, and U-Boot had booted the generation before it. So after a bootloader write
to such a `/boot`, `sync` comes before any power event.

**What the machine runs moved to unstable, 2026-10-21**: the release, 26.05, carried tailscale
1.98.10, containerd 2.3.3, runc 1.4.3, crun 1.27.1 and btrfs-progs 6.19.1 the day unstable carried
1.104.1, 2.4.1, 1.5.2, 1.30.1 and 7.1, both locked the same day; the kernel, 6.18.57, was one. Taking
those five and workerd from unstable, the release keeping the rest, put a second glibc and libstdc++
in the set, 1.2 GiB to 1.4 GiB, and three systems kept held 1.9 GB of the ext4.

**containerd 2 unpacks a pull through its transfer service**, whose unpack platforms name overlayfs
alone: with btrfs the default, `ctr image pull` failed with "no unpack platforms defined" until
`io.containerd.transfer.v1.local`'s `unpack_config` named btrfs too. The CRI's snapshotter is set
apart from it, and a layer pulled lands as a subvolume under `/data/containerd`.

**Tailscale replaces `/etc/resolv.conf` with its own resolver**, `100.100.100.100`, which a
container's network cannot reach; `tailscale set --accept-dns=false`, the module's `extraSetFlags`,
leaves the machine's nameservers in place.

**nixpkgs' crun carries criu, and criu Python**, measured 2026-10-21: the host without workerd and
with crun as nixpkgs builds it weighed 1463.6 MiB against 1417.0 MiB before, workerd's 133.1 MiB
gone and Python 3.14's 137.1 MiB, libkrunfw's 22.4 MiB, libkrun's 5.2 MiB and criu's 2.5 MiB come,
crun's own closure 316.7 MiB. An override dropping criu and libkrun makes a crun no binary cache
holds, which every machine would compile, so nixpkgs' stands until the system is reviewed whole.

**workerd links glibc alone, wasmtime glibc and libgcc_s**, read from their ELF headers on
2026-10-21: workerd 1.20261019.1 needs `libc.so.6` and `libm.so.6`, GLIBC_2.35, so distroless
`base-nossl` holds it; wasmtime 49.0.4 needs `libgcc_s` beside glibc, GLIBC_2.28, so distroless
`cc`. Both images build for arm64 on an amd64 builder with nothing emulated, since only the stage
fetching the release runs a command, on the build's own platform.

**A container driven through containerd's API alone, tried on 2026-10-21** on containerd 2.4.1,
by `containerd-client` 0.9 from Rust, an alpine image with busybox httpd run by runc, crun and
youki in turn:

- `containerd-client` generates its code from containerd's protobufs as it builds, so `protoc`
  must be on the build's path; platform's `mise.toml` pins it.
- **containerd's garbage collector takes a snapshot nothing holds**: one prepared for a container
  not yet created was gone before `Containers.Create`, until a lease held it from `Prepare` to the
  container's creation.
- A task listed by the tasks service names its container by `id`, not `container_id`.
- `ctr run -d --rm` is refused; a detached task is killed and its container removed apart.
- busybox httpd as PID 1 ignores SIGTERM, so a stop waits its whole grace before the kill.
- A CNI bridge plugin run by hand leaves an nftables table, `cni_plugins_masquerade`, which its
  `DEL` does not remove when the bridge goes.

**zswap on NixOS's kernel, read on 2026-10-21** from a test machine's `/proc/config.gz`, Linux 6.18: zswap and
zsmalloc are built in, and so is zstd, its default compressor, while lz4 is a module; a compressor
named on the kernel's line that is not yet loaded falls back to the default, so lz4 is written to
`/sys/module/zswap/parameters/compressor` once the system is up, which loads the module. No
`zpool` parameter is left, zsmalloc being the one pool. NixOS makes a swap file on btrfs by `btrfs
filesystem mkswapfile`, which marks it no copy on write, and encrypts swap at random only through
`cryptsetup` over what it names, a loop device for a file. A tmpfs holds pages swap can take unless
it is mounted `noswap`, Linux 6.4 on.

**fastfetch shows what its configuration names and nothing else**, tried on 2026-10-21 with 2.70.0:
a configuration file with no `modules` prints the logo alone, so one that sets only the logo lists
fastfetch's defaults, as `--gen-config` writes them. It opens every logo line with bold, which a
logo undoes with `22` before each of its colors. A `file-raw` logo is printed as its bytes, its
colors fixed; a `file` logo colors by `$1` to `$9`, each a color of the terminal's own palette
that the configuration names, so it follows the viewer's theme. A palette's names are slots, which
a theme may fill as it likes: Rose Pine's cyan is a pink. chafa writes `ESC[?25l` before its
picture and `ESC[?25h` after, hiding the cursor, which a logo leaves out; and its edges are grays
of each color, so a picture reduced to a few colors by nearest distance paints a white edge pink,
where one sorted by hue, the grays first, keeps each edge with its own leg. A logo drawn in
letters is matched cell by cell against the picture's shape, each letter drawn in the terminal's
font, both softened first so a slanted edge does not flip on a pixel; a logo is drawn by a program
from the picture, never by hand. Its columns are its rows times the picture's width over its height,
divided by a cell's width over its height, 0.52 in Menlo -- not another drawing's proportions,
which made one 6 percent too wide.

**A service that makes network namespaces cannot have a mount namespace of its own**, tried on a test machine
on 2026-10-22 under `systemd-run`, NixOS 26.05: `ip netns add` mounts the namespace under
`/run/netns`, and under `ProtectSystem`, `ProtectHome`, `PrivateTmp` or any setting that gives the
unit its own mount namespace that mount stays inside the unit, so containerd, outside it, never
sees the namespace a container is to join. CNI, btrfs quota groups and containerd's socket all work
inside such a sandbox; the namespace alone does not reach out. A unit sharing PID 1's mount
namespace keeps `NoNewPrivileges`, `ProtectClock`, `ProtectHostname`, `RestrictRealtime`,
`RestrictSUIDSGID`, `LockPersonality`, `MemoryDenyWriteExecute`, `SystemCallArchitectures`,
`RestrictAddressFamilies` and a capability bounding set, monoflake/machine's `system/driver.nix`.
