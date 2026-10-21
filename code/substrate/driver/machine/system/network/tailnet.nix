# A machine's place on the tailnet, joined at boot by the machine's auth key, unstable's Tailscale.
{ config, pkgs, ... }:
{
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    openFirewall = true;
    authKeyFile = config.machine.tailnet.authKeyFile;
    # The tailnet's resolver would replace the nameservers `network/default.nix` sets, which a
    # container cannot reach.
    extraSetFlags = [ "--accept-dns=false" ];
  };
}
