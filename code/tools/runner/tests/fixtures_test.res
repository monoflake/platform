/***
 * `Fixtures` held to RFC p8e8k, a bundle and an image laid out as their kinds take them, every
 * fixture of `tests/fixtures/` built or said why not, and each served at its address.
 */
open Node

/** Each entry of a ustar archive, its name, its mode and its content, to the two empty blocks. */
let entries = (archive: Uint8Array.t) => {
  let found = []
  let rec go = at => {
    let header = archive->TypedArray.slice(~start=at, ~end=at + 512)
    if header->TypedArray.every(b => b == 0) {
      ()
    } else {
      let field = (from, length) =>
        Web.text(header->TypedArray.slice(~start=from, ~end=from + length))
        ->String.split("\x00")
        ->Array.getUnsafe(0)
        ->String.trim
      let size = Int.fromString(field(124, 12), ~radix=8)->Option.getOr(0)
      let mode = Int.fromString(field(100, 8), ~radix=8)->Option.getOr(0)
      found->Array.push((
        field(0, 100),
        mode,
        archive->TypedArray.slice(~start=at + 512, ~end=at + 512 + size),
      ))
      go(at + 512 + (size + 511) / 512 * 512)
    }
  }
  go(0)
  found
}

let named = (archive, name) =>
  entries(archive)->Array.find(((n, _, _)) => n == name)->Option.map(((_, _, bytes)) => bytes)

let json = bytes => JSON.parseOrThrow(Web.text(bytes))

let field = (json, path) =>
  path->Array.reduce(Some(json), (at, key) =>
    at->Option.flatMap(at =>
      switch (at->JSON.Decode.object, at->JSON.Decode.array, Int.fromString(key)) {
      | (Some(o), _, _) => o->Dict.get(key)
      | (None, Some(a), Some(i)) => a->Array.get(i)
      | (None, Some(_) | None, Some(_) | None) => None
      }
    )
  )

let digestOf = bytes => `sha256:${Envelope.Hex.encode(Noble.sha256(bytes))}`

test("a bundle is metadata.json naming its main module, then each module by its name", () => {
  let bundle = Fixtures.bundle(
    ~main="b.js",
    [("b.js", Web.utf8("export default {}")), ("a.js", Web.utf8("export const a = 1"))],
  )
  deepEqual(bundle->TypedArray.length % 512, 0)
  deepEqual(entries(bundle)->Array.map(((name, _, _)) => name), ["metadata.json", "a.js", "b.js"])
  let metadata = json(named(bundle, "metadata.json")->Option.getOrThrow)
  deepEqual(field(metadata, ["main_module"]), Some(JSON.String("b.js")))
  ok(field(metadata, ["compatibility_date"])->Option.flatMap(JSON.Decode.string) != None)
  deepEqual(named(bundle, "b.js")->Option.map(Web.text), Some("export default {}"))
})

test("an image is an OCI layout, its index naming the manifest and each blob by its digest", () => {
  let program = Web.utf8("a program")
  let image = Fixtures.image(~program, ~architecture="arm64", ~port=8080)
  let blob = digest => named(image, `blobs/sha256/${digest->String.slice(~start=7)}`)
  deepEqual(
    named(image, "oci-layout")->Option.map(json),
    Some(json(Web.utf8(`{"imageLayoutVersion":"1.0.0"}`))),
  )
  let index = json(named(image, "index.json")->Option.getOrThrow)
  let described = field(index, ["manifests", "0"])->Option.getOrThrow
  deepEqual(field(described, ["platform", "architecture"]), Some(JSON.String("arm64")))
  let digest = field(described, ["digest"])->Option.flatMap(JSON.Decode.string)->Option.getOrThrow
  let manifest = blob(digest)->Option.getOrThrow
  deepEqual(digestOf(manifest), digest)
  let manifest = json(manifest)
  let layerDigest =
    field(manifest, ["layers", "0", "digest"])
    ->Option.flatMap(JSON.Decode.string)
    ->Option.getOrThrow
  let configDigest =
    field(manifest, ["config", "digest"])->Option.flatMap(JSON.Decode.string)->Option.getOrThrow
  let layer = blob(layerDigest)->Option.getOrThrow
  let config = json(blob(configDigest)->Option.getOrThrow)
  deepEqual(field(config, ["rootfs", "diff_ids", "0"]), Some(JSON.String(digestOf(layer))))
  deepEqual(field(config, ["config", "Cmd", "0"]), Some(JSON.String("/program")))
  ok(field(config, ["config", "ExposedPorts", "8080/tcp"]) != None)
  deepEqual(
    entries(layer)->Array.map(((name, mode, bytes)) => (name, mode, Web.text(bytes))),
    [("program", 0o755, "a program")],
  )
})

let scratch = () => System.mkdtemp(`${System.tmpdir()}/runner-fixtures-`)

test("every fixture is built or said why not, a variant made of what it is of", () => {
  let into = scratch()
  let manifest = Fixtures.build(~into, ~bounds=dict{"artifact": 100.}, ~architecture=None)
  let built = name => manifest.built->Dict.get(name)->Option.getOrThrow
  let echo = built("echo-modules")
  deepEqual(echo.form, "modules")
  deepEqual(echo.hash, Envelope.Hex.encode(Noble.sha256(System.readBytes(`${into}/${echo.file}`))))
  ok(built("counter-modules").hash != echo.hash)
  // Served under a hash not its own, the same bytes.
  let mismatched = built("echo-modules-mismatched")
  deepEqual((mismatched.file, mismatched.hash != echo.hash), (echo.file, true))
  // Named where nothing is, its hash its own.
  let unfetchable = built("echo-modules-unfetchable")
  deepEqual(unfetchable.hash, echo.hash)
  ok(!(manifest.files->Array.includes(unfetchable.file)))
  ok(!System.exists(`${into}/${unfetchable.file}`))
  // Padded a byte past the bound where it is served.
  deepEqual(
    manifest.padded,
    [{file: built("echo-modules-oversized").file, from: echo.file, size: 101.}],
  )
  ok(manifest.unbuilt->Dict.get("echo-image")->Option.getOr("")->String.includes("architecture"))
  ok(manifest.unbuilt->Dict.get("echo-component")->Option.getOr("")->String.includes("component"))
  deepEqual(Fixtures.read(System.readFileSync(`${into}/${Fixtures.manifestFile}`)), Ok(manifest))
  System.rm(into, {recursive: true, force: true})
})

test("a fixture padded past a bound the run has no value of is not built", () => {
  let into = scratch()
  let manifest = Fixtures.build(~into, ~bounds=dict{}, ~architecture=None)
  ok(
    manifest.unbuilt
    ->Dict.get("echo-modules-oversized")
    ->Option.getOr("")
    ->String.includes("the bound artifact"),
  )
  System.rm(into, {recursive: true, force: true})
})

test("a fixture is served at its file's address, and one not built says why", () => {
  let manifest: Fixtures.manifest = {
    built: dict{"echo": {form: "image", file: "echo.tar", hash: "ab", architecture: Some("arm64")}},
    files: ["echo.tar"],
    padded: [],
    unbuilt: dict{"other": "a component, which nothing builds"},
  }
  let served = Fixtures.served(manifest, ~at="file:///srv/fixtures/")
  deepEqual(
    served("echo"),
    Ok({
      Run.form: "image",
      address: "file:///srv/fixtures/echo.tar",
      hash: "ab",
      architecture: Some("arm64"),
    }),
  )
  deepEqual(served("other"), Error("not built, a component, which nothing builds"))
  ok(served("none")->Result.isError)
  deepEqual(Fixtures.read(JSON.stringify(Fixtures.toJson(manifest))), Ok(manifest))
  ok(Fixtures.read("[]")->Result.isError)
})
