# A machine's SSH, root alone by the machine's keys and never by a password.
{ config, lib, ... }:
{
  services.openssh = {
    enable = true;
    openFirewall = lib.mkDefault false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users = {
    mutableUsers = false;
    users.root.openssh.authorizedKeys.keys = config.machine.keys;
  };
}
