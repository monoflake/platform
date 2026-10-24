/***
 * The samples' fixtures built from their sources, and the manifest a run serves them by, RFC
 * p8e8k.
 */
type built = {form: string, file: string, hash: string, architecture: option<string>}

type padded = {file: string, from: string, size: float}

type manifest = {
  built: dict<built>,
  files: array<string>,
  padded: array<padded>,
  unbuilt: dict<string>,
}

let manifestFile = "fixtures.json"

/** The date a bundle's modules are run as of, one every workerd since takes. */
let compatibilityDate = "2025-01-01"

let block = 512

/** A number in octal digits, zeros before it to `width`, then a NUL. */
let octal = (n, width) => Int.toString(n, ~radix=8)->String.padStart(width - 1, "0") ++ "\x00"

/** An entry of a ustar archive, a file of its mode or a directory. */
type entry = File(string, int, Uint8Array.t) | Directory(string)

/** An entry's header, its checksum the sum of its bytes with that field read as spaces. */
let header = entry => {
  let (name, mode, size, kind) = switch entry {
  | File(name, mode, bytes) => (name, mode, bytes->TypedArray.length, "0")
  | Directory(name) => (name, 0o755, 0, "5")
  }
  let h = Uint8Array.fromLength(block)
  let put = (at, text) => h->Web.copyInto(Web.utf8(text), at)
  h->Web.copyInto(Web.utf8(name), 0)
  put(100, octal(mode, 8))
  put(108, octal(0, 8))
  put(116, octal(0, 8))
  put(124, octal(size, 12))
  put(136, octal(0, 12))
  put(148, "        ")
  put(156, kind)
  put(257, "ustar\x0000")
  let sum = ref(0)
  for at in 0 to block - 1 {
    sum := sum.contents + h->TypedArray.get(at)->Option.getOr(0)
  }
  put(148, Int.toString(sum.contents, ~radix=8)->String.padStart(6, "0") ++ "\x00 ")
  h
}

/** The bytes a length takes in whole blocks. */
let padded = length => (length + block - 1) / block * block

let contentOf = entry =>
  switch entry {
  | File(_, _, bytes) => bytes
  | Directory(_) => Uint8Array.fromLength(0)
  }

/** The entries as a ustar archive, every name short enough as the runner writes them. */
let tar = entries => {
  let total =
    entries->Array.reduce(0, (sum, e) => sum + block + padded(contentOf(e)->TypedArray.length)) +
      2 * block
  let archive = Uint8Array.fromLength(total)
  let at = ref(0)
  entries->Array.forEach(e => {
    archive->Web.copyInto(header(e), at.contents)
    archive->Web.copyInto(contentOf(e), at.contents + block)
    at := at.contents + block + padded(contentOf(e)->TypedArray.length)
  })
  archive
}

let hex = bytes => Envelope.Hex.encode(Noble.sha256(bytes))

let bundle = (~main, modules) => {
  let metadata = JSON.Object(
    dict{"main_module": JSON.String(main), "compatibility_date": JSON.String(compatibilityDate)},
  )
  tar(
    [
      File("metadata.json", 0o644, Web.utf8(JSON.stringify(metadata))),
      ...modules
      ->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))
      ->Array.map(((name, bytes)) => File(name, 0o644, bytes)),
    ],
  )
}

/** A blob of an image's layout, its media type and its bytes, described as OCI describes one. */
let descriptor = (mediaType, bytes) =>
  dict{
    "mediaType": JSON.String(mediaType),
    "digest": JSON.String(`sha256:${hex(bytes)}`),
    "size": JSON.Number(Int.toFloat(bytes->TypedArray.length)),
  }

let image = (~program, ~architecture, ~port) => {
  let layer = tar([File("program", 0o755, program)])
  let platform = dict{"architecture": JSON.String(architecture), "os": JSON.String("linux")}
  let config = Web.utf8(
    JSON.stringify(
      JSON.Object(
        dict{
          "architecture": JSON.String(architecture),
          "os": JSON.String("linux"),
          "config": JSON.Object(
            dict{
              "Cmd": JSON.Array([JSON.String("/program")]),
              "ExposedPorts": JSON.Object(
                Dict.fromArray([(`${Int.toString(port)}/tcp`, JSON.Object(dict{}))]),
              ),
            },
          ),
          "rootfs": JSON.Object(
            dict{
              "type": JSON.String("layers"),
              "diff_ids": JSON.Array([JSON.String(`sha256:${hex(layer)}`)]),
            },
          ),
        },
      ),
    ),
  )
  let manifest = Web.utf8(
    JSON.stringify(
      JSON.Object(
        dict{
          "schemaVersion": JSON.Number(2.),
          "mediaType": JSON.String("application/vnd.oci.image.manifest.v1+json"),
          "config": JSON.Object(descriptor("application/vnd.oci.image.config.v1+json", config)),
          "layers": JSON.Array([
            JSON.Object(descriptor("application/vnd.oci.image.layer.v1.tar", layer)),
          ]),
        },
      ),
    ),
  )
  let described = descriptor("application/vnd.oci.image.manifest.v1+json", manifest)
  described->Dict.set("platform", JSON.Object(platform))
  let index = Web.utf8(
    JSON.stringify(
      JSON.Object(
        dict{
          "schemaVersion": JSON.Number(2.),
          "mediaType": JSON.String("application/vnd.oci.image.index.v1+json"),
          "manifests": JSON.Array([JSON.Object(described)]),
        },
      ),
    ),
  )
  let blob = bytes => File(`blobs/sha256/${hex(bytes)}`, 0o644, bytes)
  tar([
    File("oci-layout", 0o644, Web.utf8(`{"imageLayoutVersion":"1.0.0"}`)),
    File("index.json", 0o644, index),
    Directory("blobs/"),
    Directory("blobs/sha256/"),
    blob(config),
    blob(manifest),
    blob(layer),
  ])
}

/** The Rust target a program is built for, by the architecture OCI names. */
let targetOf = architecture =>
  switch architecture {
  | "arm64" => Some("aarch64-unknown-linux-musl")
  | "amd64" => Some("x86_64-unknown-linux-musl")
  | _ => None
  }

/** The port an image fixture listens on, the one the samples deploy it with. */
let imagePort = 8080

let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

let text = (json, name) => field(json, name)->Option.flatMap(JSON.Decode.string)

/** The files of a source directory ending so, by name. */
let sources = (directory, ending) =>
  System.list(directory)
  ->Array.filter(name => name->String.endsWith(ending))
  ->Array.toSorted(String.compare)

/** A fixture of its own form built from its source directory, or why it is not. */
let fromSource = (~name, ~form, ~into, ~architecture) => {
  let directory = System.rootPath(`code/tools/runner/fixtures/${name}`)
  if form == "component" {
    Error("a component, which nothing in the toolchain builds yet")
  } else if !System.exists(directory) {
    Error(`no source in code/tools/runner/fixtures/${name}`)
  } else {
    switch (form, architecture) {
    | ("modules", _) =>
      switch sources(directory, ".js") {
      | [] => Error(`no module in code/tools/runner/fixtures/${name}`)
      | modules =>
        let read = modules->Array.map(m => (m, System.readBytes(`${directory}/${m}`)))
        Ok((bundle(~main=modules->Array.getUnsafe(0), read), None))
      }
    | ("image", None) => Error("an image, and the run is given no architecture to build it for")
    | ("image", Some(architecture)) =>
      switch (targetOf(architecture), sources(directory, ".rs")) {
      | (None, _) => Error(`an image for ${architecture}, which no Rust target here builds for`)
      | (Some(_), []) => Error(`no program in code/tools/runner/fixtures/${name}`)
      | (Some(target), sources) =>
        let program = `${into}/${name}.program`
        System.ran(
          "rustc",
          [
            "--edition",
            "2024",
            "--target",
            target,
            "-C",
            "linker=rust-lld",
            "-C",
            "opt-level=s",
            "-C",
            "strip=symbols",
            "-C",
            "codegen-units=1",
            "--remap-path-prefix",
            `${directory}=fixtures/${name}`,
            "-o",
            program,
            `${directory}/${sources->Array.getUnsafe(0)}`,
          ],
        )->Result.map(_ => (
          image(~program=System.readBytes(program), ~architecture, ~port=imagePort),
          Some(architecture),
        ))
      }
    | (form, _) => Error(`a form ${form}, which the runner builds none of`)
    }
  }
}

let builtJson = (b: built) => {
  let fields = dict{
    "form": JSON.String(b.form),
    "file": JSON.String(b.file),
    "hash": JSON.String(b.hash),
  }
  b.architecture->Option.forEach(a => fields->Dict.set("architecture", JSON.String(a)))
  JSON.Object(fields)
}

let toJson = manifest => JSON.Object(
  dict{
    "built": JSON.Object(manifest.built->Dict.mapValues(builtJson)),
    "files": JSON.Array(manifest.files->Array.map(f => JSON.String(f))),
    "padded": JSON.Array(
      manifest.padded->Array.map(p => JSON.Object(
        dict{
          "file": JSON.String(p.file),
          "from": JSON.String(p.from),
          "size": JSON.Number(p.size),
        },
      )),
    ),
    "unbuilt": JSON.Object(manifest.unbuilt->Dict.mapValues(why => JSON.String(why))),
  },
)

let strings = json =>
  json->JSON.Decode.array->Option.mapOr([], a => a->Array.filterMap(JSON.Decode.string))

let read = text_ =>
  switch JSON.parseOrThrow(text_) {
  | exception JsExn(_) => Error("no JSON")
  | json =>
    let built =
      field(json, "built")
      ->Option.flatMap(JSON.Decode.object)
      ->Option.getOr(dict{})
      ->Dict.toArray
      ->Array.filterMap(((name, b)) =>
        switch (text(b, "form"), text(b, "file"), text(b, "hash")) {
        | (Some(form), Some(file), Some(hash)) =>
          Some((name, {form, file, hash, architecture: text(b, "architecture")}))
        | (Some(_) | None, Some(_) | None, Some(_) | None) => None
        }
      )
    let padded =
      field(json, "padded")
      ->Option.flatMap(JSON.Decode.array)
      ->Option.getOr([])
      ->Array.filterMap(p =>
        switch (
          text(p, "file"),
          text(p, "from"),
          field(p, "size")->Option.flatMap(JSON.Decode.float),
        ) {
        | (Some(file), Some(from), Some(size)) => Some({file, from, size})
        | (Some(_) | None, Some(_) | None, Some(_) | None) => None
        }
      )
    switch field(json, "built")->Option.flatMap(JSON.Decode.object) {
    | None => Error("no fixtures built")
    | Some(_) =>
      Ok({
        built: Dict.fromArray(built),
        files: field(json, "files")->Option.mapOr([], strings),
        padded,
        unbuilt: field(json, "unbuilt")
        ->Option.flatMap(JSON.Decode.object)
        ->Option.mapOr(dict{}, u =>
          u
          ->Dict.toArray
          ->Array.filterMap(((name, why)) =>
            why->JSON.Decode.string->Option.map(why => (name, why))
          )
          ->Dict.fromArray
        ),
      })
    }
  }

let served = (manifest, ~at) => {
  let at = at->String.endsWith("/") ? at->String.slice(~start=0, ~end=-1) : at
  name =>
    switch (manifest.built->Dict.get(name), manifest.unbuilt->Dict.get(name)) {
    | (Some(b), _) =>
      Ok({Run.form: b.form, address: `${at}/${b.file}`, hash: b.hash, architecture: b.architecture})
    | (None, Some(why)) => Error(`not built, ${why}`)
    | (None, None) => Error("no fixture of tests/fixtures/ the run built")
    }
}

let build = (~into, ~bounds, ~architecture) => {
  System.mkdir(into, {recursive: true})
  let names =
    System.list(System.rootPath("tests/fixtures"))
    ->Array.filter(name => System.exists(System.rootPath(`tests/fixtures/${name}/fixture.json`)))
    ->Array.toSorted(String.compare)
  let described =
    names
    ->Array.map(name => (
      name,
      JSON.parseOrThrow(System.fromRoot(`tests/fixtures/${name}/fixture.json`)),
    ))
    ->Dict.fromArray
  let built = Dict.make()
  let files = []
  let padded = []
  let unbuilt = Dict.make()
  // Those of their own form first, so each made of another finds it built.
  let (own, others) = names->Array.reduce(([], []), ((own, others), name) =>
    switch described->Dict.get(name)->Option.flatMap(d => text(d, "of")) {
    | None => (own->Array.concat([name]), others)
    | Some(_) => (own, others->Array.concat([name]))
    }
  )
  own->Array.forEach(name => {
    let form = described->Dict.get(name)->Option.flatMap(d => text(d, "form"))->Option.getOr("")
    switch fromSource(~name, ~form, ~into, ~architecture) {
    | Error(why) => unbuilt->Dict.set(name, why)
    | Ok((bytes, architecture)) =>
      let file = `${name}.tar`
      System.writeBytes(`${into}/${file}`, bytes)
      files->Array.push(file)
      built->Dict.set(name, {form, file, hash: hex(bytes), architecture})
    }
  })
  others->Array.forEach(name => {
    let d = described->Dict.get(name)->Option.getOr(JSON.Null)
    let base = text(d, "of")->Option.getOr("")
    switch (built->Dict.get(base), unbuilt->Dict.get(base)) {
    | (None, why) =>
      unbuilt->Dict.set(name, `of ${base}, ${why->Option.getOr("which is no fixture")}`)
    | (Some(of_), _) =>
      let own = `${name}.tar`
      switch (text(d, "served"), field(d, "padded")) {
      | (Some("hash_mismatched"), _) =>
        // Any hash but its bytes' own, so the name's is taken.
        built->Dict.set(name, {...of_, hash: hex(Web.utf8(name))})
      | (Some("unfetchable"), _) => built->Dict.set(name, {...of_, file: own})
      | (_, Some(p)) =>
        let past = field(p, "plus")->Option.flatMap(JSON.Decode.float)->Option.getOr(0.)
        switch text(p, "bound")->Option.flatMap(b => bounds->Dict.get(b)) {
        | Some(bound) =>
          padded->Array.push({file: own, from: of_.file, size: bound +. past})
          built->Dict.set(name, {...of_, file: own})
        | None =>
          unbuilt->Dict.set(
            name,
            `padded past the bound ${text(p, "bound")->Option.getOr(
                "",
              )}, which the run is given no value of`,
          )
        }
      | (Some(_) | None, None) => built->Dict.set(name, of_)
      }
    }
  })
  let manifest = {built, files, padded, unbuilt}
  System.writeText(`${into}/${manifestFile}`, JSON.stringify(toJson(manifest)))
  manifest
}
