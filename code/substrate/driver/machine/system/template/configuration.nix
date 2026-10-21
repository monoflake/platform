# What this machine is alone; the rest is the platform's module.
{
  networking.hostName = "machine";
  disko.devices.disk.main.device = "/dev/vda";
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderReplaceWithYourOwnPublicKey0000"
  ];
  system.stateVersion = "26.05";
}
