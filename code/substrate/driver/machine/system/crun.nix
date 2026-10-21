# crun without criu and libkrun, which a machine never uses and which bring Python with them,
# `docs/lessons/machines.md`. Its derivation links criu whatever its inputs, so the flag goes too.
{
  crun,
  criu,
  lib,
}:
(crun.override { withLibkrun = false; }).overrideAttrs (previous: {
  buildInputs = lib.remove criu previous.buildInputs;
  env = removeAttrs (previous.env or { }) [ "NIX_LDFLAGS" ];
  configureFlags = (previous.configureFlags or [ ]) ++ [ "--disable-criu" ];
})
