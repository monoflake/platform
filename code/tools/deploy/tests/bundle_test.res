/***
 * `Bundle` held to RFC dg903, a wrangler configuration read as wrangler reads JSONC, the modules
 * taken and the archive's ustar headers as a reader parses them.
 */
open Node

let file = (name, text): Bundle.file => {name, bytes: Bytes.utf8(text)}

let config: Bundle.config = {
  main: "src/index.js",
  compatibilityDate: "2026-10-21",
  compatibilityFlags: [],
}

test("command line ingress keeps metadata kinds and refuses a second ingress declaration", () => {
  let ingress: array<Bundle.Contracts.AppIngress.t> = [Domain({domain: "example.com"}), Binding]
  deepEqual(
    Bundle.release(~ingress, `{"kinds":["container","function"]}`),
    Ok({kinds: Some([Container, Function]), ingress: Some(ingress)}),
  )
  deepEqual(Bundle.release(~ingress, `{}`), Ok({kinds: None, ingress: Some(ingress)}))
  [`{"ingress":[]}`, `{"ingress":[{"name":"binding"}]}`, `{"ingress":null}`]->Array.forEach(text =>
    deepEqual(Bundle.release(~ingress, text), Error("and --ingress both declare ingress"))
  )
  deepEqual(Bundle.release(`{"kinds":["function"]}`), Ok({kinds: Some([Function]), ingress: None}))
})

/** A field of a header, its text up to the first NUL. */
let field = (archive, at, length) =>
  Bytes.text(archive->TypedArray.slice(~start=at, ~end=at + length))
  ->String.split("\x00")
  ->Array.get(0)
  ->Option.getOr("")

let octal = text => Int.fromString(text->String.trim, ~radix=8)->Option.getOr(-1)

/** Each entry of an archive by its name and content, read as ustar lays them out. */
let entries = archive => {
  let rec read = (at, found) =>
    switch field(archive, at, 100) {
    | "" => found
    | name =>
      let size = octal(field(archive, at + 124, 12))
      let content = Bytes.text(archive->TypedArray.slice(~start=at + 512, ~end=at + 512 + size))
      read(at + 512 + (size + 511) / 512 * 512, [...found, (name, content)])
    }
  read(0, [])
}

test("a comment and a trailing comma are dropped, a string holding // kept", () => {
  let text = `{
	// the entry
	"$schema": "./node_modules/wrangler/config-schema.json",
	/* a block, "quoted" */
	"main": "src/index.js",
	"say": "a \\"quoted\\" // word",
	"flags": ["a", "b",],
}`
  deepEqual(
    JSON.parseOrThrow(Bundle.uncommented(text)),
    JSON.parseOrThrow(`{"$schema": "./node_modules/wrangler/config-schema.json", "main": "src/index.js", "say": "a \\"quoted\\" // word", "flags": ["a", "b"]}`),
  )
})

test("a configuration gives its main, date and flags, and one missing either is refused", () => {
  deepEqual(
    Bundle.config(`{"main": "src/index.ts", "compatibility_date": "2026-10-21", "compatibility_flags": ["nodejs_compat"]}`),
    Ok({
      main: "src/index.ts",
      compatibilityDate: "2026-10-21",
      compatibilityFlags: ["nodejs_compat"],
    }),
  )
  deepEqual(
    Bundle.config(`{"main": "src/index.js", "compatibility_date": "2026-10-21"}`),
    Ok(config),
  )
  ok(Bundle.config(`{"compatibility_date": "2026-10-21"}`)->Result.isError)
  ok(Bundle.config(`{"main": "a.js"}`)->Result.isError)
  ok(Bundle.config(`{"main": "a.js", "compatibility_date": "21 October"}`)->Result.isError)
  ok(
    Bundle.config(`{"main": "a.js", "compatibility_date": "2026-10-21", "compatibility_flags": [1]}`)->Result.isError,
  )
  ok(Bundle.config("main = 'a.js'")->Result.isError)
})

test(
  "the main module is main's file name ending .js, and wrangler's note and maps are no module",
  () => {
    deepEqual(Bundle.mainModule(config), "index.js")
    deepEqual(Bundle.mainModule({...config, main: "./worker/app.ts"}), "app.js")
    deepEqual(Bundle.mainModule({...config, main: "entry"}), "entry.js")
    deepEqual(
      ["index.js", "index.js.map", "README.md", "a.wasm"]->Array.filter(Bundle.isModule),
      ["index.js", "a.wasm"],
    )
  },
)

test("the metadata names the main module and the date, and flags only where there are some", () => {
  deepEqual(
    JSON.parseOrThrow(Bundle.metadata(config)),
    JSON.parseOrThrow(`{"main_module": "index.js", "compatibility_date": "2026-10-21"}`),
  )
  deepEqual(
    JSON.parseOrThrow(Bundle.metadata({...config, compatibilityFlags: ["nodejs_compat"]})),
    JSON.parseOrThrow(`{"main_module": "index.js", "compatibility_date": "2026-10-21", "compatibility_flags": ["nodejs_compat"]}`),
  )
})

test(
  "an archive is whole blocks, each header's checksum its bytes with the field as spaces",
  () => {
    switch Bundle.tar([
      file("a.js", "export default {}"),
      file("b/c.txt", String.repeat("x", 600)),
    ]) {
    | Error(why) => ok(false, ~message=why)
    | Ok(archive) =>
      // Two headers, one block and two of content, and the two blocks of zeros that end it.
      deepEqual(archive->TypedArray.length, 512 * (1 + 1 + 1 + 2 + 2))
      deepEqual(
        entries(archive),
        [("a.js", "export default {}"), ("b/c.txt", String.repeat("x", 600))],
      )
      [0, 1024]->Array.forEach(at => {
        let header = archive->TypedArray.slice(~start=at, ~end=at + 512)
        let sum = ref(0)
        for i in 0 to 511 {
          let inField = i >= 148 && i < 156
          sum := sum.contents + (inField ? 32 : header->TypedArray.get(i)->Option.getOr(0))
        }
        deepEqual(octal(field(archive, at + 148, 8)), sum.contents)
        deepEqual(field(archive, at + 100, 8), "0000644")
        deepEqual(field(archive, at + 136, 12), "00000000000")
        deepEqual(field(archive, at + 156, 1), "0")
        deepEqual(field(archive, at + 257, 6), "ustar")
        deepEqual(field(archive, at + 263, 2), "00")
      })
      let tail = archive->TypedArray.slice(~start=512 * 5, ~end=512 * 7)
      ok(tail->TypedArray.every(b => b == 0))
    }
  },
)

test("a name past 100 bytes is refused", () =>
  ok(Bundle.tar([file(String.repeat("a", 101), "")])->Result.isError)
)

test("a bundle is its metadata then its modules by name, the same files the same bytes", () => {
  let wrote = [
    file("z.txt", "z"),
    file("README.md", "a note"),
    file("index.js", "x"),
    file("index.js.map", "{}"),
  ]
  switch (Bundle.packed(config, wrote), Bundle.packed(config, wrote->Array.toReversed)) {
  | (Ok(one), Ok(two)) =>
    deepEqual(entries(one)->Array.map(((name, _)) => name), ["metadata.json", "index.js", "z.txt"])
    deepEqual(one, two)
  | (Error(why), _) | (_, Error(why)) => ok(false, ~message=why)
  }
  ok(Bundle.packed(config, [file("other.js", "x")])->Result.isError)
})

test("a declaration of kinds is read in its order, and one not read whole is refused", () => {
  deepEqual(Bundle.declared(`{"kinds": ["function"]}`), Ok([Function]))
  deepEqual(Bundle.declared(`{"kinds": ["container", "function"]}`), Ok([Container, Function]))
  deepEqual(Bundle.declared(`{"kinds": ["instance"]}`), Ok([Instance]))
  ok(Bundle.declared(`{"kinds": ["function"],}`)->Result.isError)
  deepEqual(Bundle.declared(`["function"]`), Error("is no JSON object"))
  deepEqual(
    Bundle.declared(`{"kinds": ["function"], "main": "src/index.js"}`),
    Error("holds kinds and ingress alone, not main"),
  )
  deepEqual(Bundle.declared(`{}`), Error("holds no kinds"))
  deepEqual(
    Bundle.declared(`{"kinds": "function"}`),
    Error("declares kinds that are not an array of strings"),
  )
  deepEqual(
    Bundle.declared(`{"kinds": ["function", 1]}`),
    Error("declares kinds that are not an array of strings"),
  )
  deepEqual(
    Bundle.declared(`{"kinds": ["vm"]}`),
    Error("declares kind vm, not function, instance or container"),
  )
  deepEqual(Bundle.declared(`{"kinds": []}`), Error("declares an empty list of kinds"))
  deepEqual(
    Bundle.declared(`{"kinds": ["function", "container", "function"]}`),
    Error("declares kind function twice"),
  )
})

test("kinds declared go last in the bundle's metadata, in the order declared", () => {
  deepEqual(
    Bundle.metadata(~kinds=[Function], config),
    `{"main_module":"index.js","compatibility_date":"2026-10-21","kinds":["function"]}`,
  )
  switch Bundle.packed(~kinds=[Container, Function], config, [file("index.js", "x")]) {
  | Error(why) => ok(false, ~message=why)
  | Ok(archive) =>
    deepEqual(
      entries(archive)->Array.get(0),
      Some((
        "metadata.json",
        `{"main_module":"index.js","compatibility_date":"2026-10-21","kinds":["container","function"]}`,
      )),
    )
  }
})

test("an undeclared bundle is the bytes it was before kinds, its hash fixed", () => {
  let config = {...config, compatibilityFlags: ["nodejs_compat"]}
  let wrote = [file("index.js", "export default {}"), file("z.txt", "z")]
  deepEqual(
    Bundle.metadata(config),
    `{"main_module":"index.js","compatibility_date":"2026-10-21","compatibility_flags":["nodejs_compat"]}`,
  )
  // The hash the base code packed these files to, before emgxf.
  deepEqual(
    Bundle.packed(config, wrote)->Result.map(archive => Envelope.Hex.encode(Host.sha256(archive))),
    Ok("ce2cd032089790763f70d1bafb883d58d1e053dcb1272befde7cd06652587fe3"),
  )
  deepEqual(Bundle.packed(~kinds=?None, config, wrote), Bundle.packed(config, wrote))
})

test("metadata reads and packs ingress with or without kinds", () => {
  let text = `{"kinds":["function"],"ingress":[{"name":"domain","domain":"example.com"},{"name":"mount","scope":"hello"},{"name":"binding"}]}`
  let ingress: array<Bundle.Contracts.AppIngress.t> = [
    Domain({domain: "example.com"}),
    Mount({scope: "hello"}),
    Binding,
  ]
  deepEqual(Bundle.release(text), Ok({kinds: Some([Function]), ingress: Some(ingress)}))
  deepEqual(Bundle.release(`{"ingress":[]}`), Ok({kinds: None, ingress: Some([])}))
  deepEqual(Bundle.release(`{}`), Ok({kinds: None, ingress: None}))
  ok(Bundle.release(`{"ingress":"example.com"}`)->Result.isError)
  ok(Bundle.release(`{"ingress":[{"name":"unknown"}]}`)->Result.isError)
  ok(Bundle.release(`{"other":[]}`)->Result.isError)
  deepEqual(Bundle.declared(text), Ok([Function]))
  let metadata =
    Bundle.metadata(~ingress, config)->JSON.parseOrThrow->JSON.Decode.object->Option.getOrThrow
  deepEqual(
    metadata->Dict.get("ingress"),
    Some(
      JSON.parseOrThrow(`[{"name":"domain","domain":"example.com"},{"name":"mount","scope":"hello"},{"name":"binding"}]`),
    ),
  )
  ok(Bundle.packed(~ingress, config, [file("index.js", "x")])->Result.isOk)
})
