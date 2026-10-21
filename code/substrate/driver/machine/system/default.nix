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
  crun = pkgs.callPackage ./crun.nix { };
  workerd = pkgs.callPackage ./workerd.nix { };
in
{
  imports = [
    ./options.nix
    ./disk.nix
  ];

  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      configurationLimit = 3;
    };
    kernelParams = [
      "console=ttyS0,115200n8"
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
      openFirewall = true;
      authKeyFile = config.machine.tailnet.authKeyFile;
    };
    journald.extraConfig = "SystemMaxUse=256M";
  };
  users = {
    mutableUsers = false;
    users.root.openssh.authorizedKeys.keys = config.machine.keys;
  };

  virtualisation.containerd = {
    enable = true;
    settings.root = "/data/containerd";
  };
  systemd.services.containerd.unitConfig.RequiresMountsFor = [ "/data" ];

  environment = {
    defaultPackages = [ ];
    systemPackages = [
      pkgs.btrfs-progs
      pkgs.runc
      crun
      workerd
    ];
  };
  documentation.enable = false;
  system.disableInstallerTools = true;
  nixpkgs.flake = {
    setNixPath = false;
    setFlakeRegistry = false;
  };

  time.timeZone = "UTC";
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
