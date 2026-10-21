# What this machine is alone; the rest is the platform's module.
{
  networking.hostName = "machine";
  machine = {
    disk = "/dev/vda";
    keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderReplaceWithYourOwnPublicKey0000" ];
    # tailnet.authKeyFile = "/var/lib/secrets/tailnet";
  };
  # monoflake.driver.bindings = [ "/var/lib/secrets/binding" ];
  system.stateVersion = "26.05";
}
