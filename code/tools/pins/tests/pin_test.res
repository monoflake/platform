/***
 * `Pin` held to what it decides, the registry read, the version taken and held back, the pin read
 * and written, and a newer NixOS.
 */
open Node

let day = 86_400_000.
let at = days => Date.fromString("2026-10-01T00:00:00.000Z")->Date.getTime +. days *. day

let document = `{
  "dist-tags": {"latest": "1.3.0", "beta": "0.9.0"},
  "versions": {"0.9.0": {}, "1.1.0": {}, "1.2.0": {}, "1.3.0": {}, "1.4.0": {}},
  "time": {
    "created": "2026-09-01T00:00:00.000Z",
    "modified": "2026-10-05T00:00:00.000Z",
    "0.9.0": "2026-09-20T00:00:00.000Z",
    "1.0.0": "2026-09-25T00:00:00.000Z",
    "1.1.0": "2026-10-01T00:00:00.000Z",
    "1.2.0": "2026-10-02T00:00:00.000Z",
    "1.3.0": "2026-10-03T00:00:00.000Z",
    "1.4.0": "2026-10-04T00:00:00.000Z"
  }
}`

let registry = switch Pin.registry(document) {
| Ok(registry) => registry
| Error(why) => JsError.throwWithMessage(why)
}

test("the registry's document is read: its latest tag, and each version still published", () => {
  deepEqual(registry.latest, "1.3.0")
  deepEqual(
    registry.published->Array.map(p => p.version)->Array.toSorted(String.compare),
    ["0.9.0", "1.1.0", "1.2.0", "1.3.0", "1.4.0"],
  )
  deepEqual(
    registry.published->Array.find(p => p.version == "1.2.0")->Option.map(p => p.at),
    Some(at(1.)),
  )
})

test("a document without a latest tag, versions or times is refused", () => {
  deepEqual(Pin.registry("not json")->Result.isError, true)
  deepEqual(Pin.registry(`{"versions": {}, "time": {}}`)->Result.isError, true)
  deepEqual(Pin.registry(`{"dist-tags": {"latest": "1"}, "time": {}}`)->Result.isError, true)
  deepEqual(Pin.registry(`{"dist-tags": {"latest": "1"}, "versions": {}}`)->Result.isError, true)
})

test("the delay is minimumReleaseAge's minutes, wherever the line lies", () => {
  deepEqual(Pin.delay(`packages:\n  - "code/**"\nminimumReleaseAge: 1440\n`), Ok(1440))
  deepEqual(Pin.delay("minimumReleaseAge: 60"), Ok(60))
  deepEqual(Pin.delay(`packages:\n  - "code/**"\n`)->Result.isError, true)
  deepEqual(Pin.delay("minimumReleaseAgeExclude:\n  - x\n")->Result.isError, true)
})

test(
  "the newest version past the delay is taken, and the newer ones are held, newest first",
  () => {
    deepEqual(Pin.choose(registry, ~delay=1440, ~now=at(10.)), {take: Some("1.3.0"), held: []})
    deepEqual(
      Pin.choose(registry, ~delay=1440, ~now=at(2.5)),
      {take: Some("1.2.0"), held: ["1.3.0"]},
    )
    deepEqual(
      Pin.choose(registry, ~delay=2880, ~now=at(2.5)),
      {take: Some("1.1.0"), held: ["1.3.0", "1.2.0"]},
    )
    // Published exactly the delay ago is past it.
    deepEqual(Pin.choose(registry, ~delay=1440, ~now=at(3.)), {take: Some("1.3.0"), held: []})
  },
)

test("nothing newer than latest is taken, and none is taken while every one is held", () => {
  deepEqual(
    Pin.choose(registry, ~delay=60 * 24 * 30, ~now=at(10.)),
    {take: None, held: ["1.3.0", "1.2.0", "1.1.0", "0.9.0"]},
  )
  deepEqual(Pin.choose(registry, ~delay=0, ~now=at(4.)).take, Some("1.3.0"))
})

let a = "a"->String.repeat(64)
let b = "b"->String.repeat(64)

let dockerfile = `# syntax=docker/dockerfile:1
FROM debian:bookworm-slim
ARG TARGETARCH
ARG WORKERD_VERSION=1.2.0
ARG WORKERD_SHA256_AMD64=${a}
  ARG WORKERD_SHA256_ARM64="${b}"
ADD --checksum=sha256:\${WORKERD_SHA256_AMD64} https://registry.npmjs.org/x/-/x-\${WORKERD_VERSION}.tgz /tmp/
`

test("the pin is read: one version, and a hash per architecture, quoted or not", () =>
  deepEqual(Pin.read(dockerfile), Ok({version: "1.2.0", hashes: dict{"amd64": a, "arm64": b}}))
)

test("the pin is written in place, every other byte as it was", () => {
  let c = "c"->String.repeat(64)
  let d = "d"->String.repeat(64)
  let pin: Pin.pin = {version: "1.3.0", hashes: dict{"arm64": d, "amd64": c}}
  let expected =
    dockerfile
    ->String.replace("WORKERD_VERSION=1.2.0", "WORKERD_VERSION=1.3.0")
    ->String.replace(`AMD64=${a}`, `AMD64=${c}`)
    ->String.replace(`ARM64="${b}"`, `ARM64="${d}"`)
  deepEqual(Pin.write(dockerfile, pin), Ok(expected))
  deepEqual(Pin.write(dockerfile, pin)->Result.flatMap(Pin.read), Ok(pin))
})

test(
  "a pin whose architectures are not the file's is refused, and so is a file not holding one",
  () => {
    deepEqual(
      Pin.write(dockerfile, {version: "1.3.0", hashes: dict{"amd64": a}})->Result.isError,
      true,
    )
    deepEqual(Pin.read(`ARG WORKERD_VERSION\nARG WORKERD_SHA256_AMD64=${a}`)->Result.isError, true)
    deepEqual(
      Pin.read(
        `ARG WORKERD_VERSION=1\nARG WORKERD_VERSION=2\nARG WORKERD_SHA256_AMD64=${a}`,
      )->Result.isError,
      true,
    )
    deepEqual(
      Pin.read(
        `ARG WORKERD_VERSION=1\nARG WORKERD_SHA256_AMD64=${a}\nARG WORKERD_SHA256_AMD64=${b}`,
      )->Result.isError,
      true,
    )
    deepEqual(Pin.read(`ARG WORKERD_VERSION=1\n`)->Result.isError, true)
    // A use of the ARG is not the ARG.
    deepEqual(
      Pin.read(`RUN echo WORKERD_VERSION=1\nARG WORKERD_SHA256_AMD64=${a}`)->Result.isError,
      true,
    )
  },
)

let flake = `{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
}`

test("the flake follows the release its nixpkgs input names", () => {
  deepEqual(Pin.follows(flake), Ok("nixos-26.05"))
  deepEqual(
    Pin.follows(`{ inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; }`)->Result.isError,
    true,
  )
})

let heads = releases =>
  releases->Array.map(branch => `0123abcd\trefs/heads/${branch}`)->Array.join("\n")

test("a release newer than the flake follows is named, and nothing else is", () => {
  deepEqual(
    Pin.release(
      heads(["nixos-25.11", "nixos-26.05", "nixos-26.11", "nixos-26.11-small"]),
      ~follows="nixos-26.05",
    ),
    Some("nixos-26.11"),
  )
  deepEqual(
    Pin.release(
      heads(["nixos-25.11", "nixos-26.05", "nixos-26.05-small", "nixos-unstable"]),
      ~follows="nixos-26.05",
    ),
    None,
  )
  deepEqual(
    Pin.release(
      heads(["nixos-27.05"])->String.replaceAll("\n", "\r\n") ++ "\r\n",
      ~follows="nixos-26.05",
    ),
    Some("nixos-27.05"),
  )
  deepEqual(Pin.release("", ~follows="nixos-26.05"), None)
})
