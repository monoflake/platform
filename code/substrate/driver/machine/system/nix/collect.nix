# How a machine collects its store, daily and whenever a new system lands, the last three kept.
{ config, ... }:
{
  # The last three systems kept, as the boot menu keeps them, until the driver holds them, RFC
  # vr5lw.
  nix.gc = {
    automatic = true;
    dates = "daily";
    persistent = true;
  };
  systemd = {
    services.nix-gc.preStart = "${config.nix.package}/bin/nix-env --profile /nix/var/nix/profiles/system --delete-generations +3";
    # A new system also collects, as the profile's link is renamed in this directory, which the
    # collection's own deletions do not trigger again.
    paths.nix-gc = {
      wantedBy = [ "paths.target" ];
      pathConfig.PathChanged = "/nix/var/nix/profiles";
    };
  };
}
