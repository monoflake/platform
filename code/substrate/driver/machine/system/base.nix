# A machine's ground, its clock on UTC, a small journal, and no documentation or default packages.
{
  time.timeZone = "UTC";
  services.journald.extraConfig = "SystemMaxUse=256M";
  documentation.enable = false;
  environment.defaultPackages = [ ];
}
