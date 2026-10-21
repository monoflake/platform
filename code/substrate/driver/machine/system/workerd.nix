# workerd as Cloudflare builds it, from its npm package, since nixpkgs carries none,
# `docs/lessons/machines.md`: one executable, linking glibc and libstdc++ alone.
{
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
stdenv.mkDerivation (self: {
  pname = "workerd";
  version = "1.20261019.1";
  src = fetchurl {
    url = "https://registry.npmjs.org/@cloudflare/workerd-linux-64/-/workerd-linux-64-${self.version}.tgz";
    hash = "sha256-+mEMR9xToJ6uAILIGo8DpdIk1HSltAe/5WA/bQCHIB0=";
  };
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  installPhase = "install -Dm755 bin/workerd $out/bin/workerd";
  meta.platforms = [ "x86_64-linux" ];
})
