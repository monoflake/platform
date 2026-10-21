# A machine's network, DHCP with fixed nameservers, nftables, and the tailnet's interface trusted.
{
  imports = [
    ./ssh.nix
    ./tailnet.nix
  ];

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
}
