# What a machine is, RFC vr5lw: NixOS and four things on it -- containerd, the host's driver, the
# tailnet and a firewall -- with bash its one shell. Its disk is `disk.nix`; what is the machine's
# own, its name and what `options.nix` asks, is its own flake's, `template/`. It downloads its sets
# and builds none, so neither nixpkgs' source nor the tools that build a system are on it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.unstable) crun youki;
  # The serial console: a PC's first UART, an Arm machine's PL011.
  serial = if pkgs.stdenv.hostPlatform.isAarch64 then "ttyAMA0" else "ttyS0";
  # The swap file, in MiB, by the memory, RFC vr5lw: 2 GiB up to 2, as much as the memory up to 8,
  # half of it beyond, never under 8 nor over 16.
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
  imports = [
    ./options.nix
    ./disk.nix
  ];

  # The system is the release; what it runs, containerd, its runtimes and the tailnet, is unstable's.
  nixpkgs.overlays = [ (final: _: { inherit (final.unstable) containerd; }) ];

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
      # zswap before the swap file, a fifth of the memory at most, its coldest written back.
      "zswap.enabled=1"
      "zswap.max_pool_percent=20"
      "zswap.shrinker_enabled=1"
    ];
  };

  # A file in a subvolume of its own, so no snapshot holds it; lz4 is a module, so the compressor is
  # set once the system is up rather than on the kernel's line.
  swapDevices = [
    {
      device = "/data/swap/swapfile";
      size = swap;
    }
  ];
  systemd.tmpfiles.rules = [
    "w- /sys/module/zswap/parameters/compressor - - - - ${config.machine.swap.compressor}"
  ];

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

  networking = {
    useDHCP = true;
    dhcpcd.extraConfig = "nohook resolv.conf";
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    nftables.enable = true;
    firewall.trustedInterfaces = [ "tailscale0" ];
  };

  services = {
    openssh = {
      enable = true;
      openFirewall = lib.mkDefault false;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };
    tailscale = {
      enable = true;
      package = pkgs.unstable.tailscale;
      openFirewall = true;
      authKeyFile = config.machine.tailnet.authKeyFile;
      # The tailnet's resolver would replace the nameservers above, which a container cannot reach.
      extraSetFlags = [ "--accept-dns=false" ];
    };
    journald.extraConfig = "SystemMaxUse=256M";
  };
  users = {
    mutableUsers = false;
    users.root.openssh.authorizedKeys.keys = config.machine.keys;
  };

  # The btrfs snapshotter, each layer a subvolume a qgroup holds, RFC vr5lw; runc, crun and youki.
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
      plugins."io.containerd.grpc.v1.cri".containerd = {
        snapshotter = "btrfs";
        runtimes = {
          crun = {
            runtime_type = "io.containerd.runc.v2";
            options.BinaryName = "${crun}/bin/crun";
          };
          youki = {
            runtime_type = "io.containerd.runc.v2";
            options.BinaryName = "${youki}/bin/youki";
          };
        };
      };
    };
  };

  environment = {
    # The logo's colors are the viewer's own terminal's, `22` undoing fastfetch's bold; the modules
    # are fastfetch's defaults less what a server has no use for, both opened three lines down.
    etc."xdg/fastfetch/config.jsonc".text = builtins.toJSON {
      logo = {
        type = "file";
        source = pkgs.writeText "logo.txt" (import ./logo.nix);
        padding.top = 3;
        color = {
          "1" = "22;34";
          "2" = "22;36";
          "3" = "22;37";
        };
      };
      modules = [
        "break"
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
    variables.CONTAINERD_SNAPSHOTTER = "btrfs";
    defaultPackages = [ ];
    systemPackages = [
      pkgs.unstable.btrfs-progs
      pkgs.unstable.runc
      crun
      youki
      pkgs.unstable.fastfetch-unwrapped
      pkgs.unstable.htop
    ];
  };
  documentation.enable = false;
  system.disableInstallerTools = true;
  nixpkgs.flake = {
    setNixPath = false;
    setFlakeRegistry = false;
  };

  time.timeZone = "UTC";
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    # The last three systems kept, as the boot menu keeps them, until the driver holds them, RFC vr5lw.
    gc = {
      automatic = true;
      dates = "daily";
      persistent = true;
    };
  };
  systemd.services = {
    containerd.unitConfig.RequiresMountsFor = [
      "/data"
      "/run/monoflake/secrets"
    ];
    mkswap-data-swap-swapfile.preStart = "[ -d /data/swap ] || ${pkgs.unstable.btrfs-progs}/bin/btrfs subvolume create /data/swap";
    nix-gc.preStart = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +3";
  };
}
