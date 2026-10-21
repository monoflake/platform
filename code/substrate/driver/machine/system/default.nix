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
    variables.CONTAINERD_SNAPSHOTTER = "btrfs";
    defaultPackages = [ ];
    systemPackages = [
      pkgs.unstable.btrfs-progs
      pkgs.unstable.runc
      crun
      youki
      pkgs.unstable.fastfetch-unwrapped
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
    containerd.unitConfig.RequiresMountsFor = [ "/data" ];
    nix-gc.preStart = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +3";
  };
}
