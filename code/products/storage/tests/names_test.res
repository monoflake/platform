/***
 * The storage product's names and the extension rules of RFC 13ixj.
 */
open Node

let hashOf = byte => Uint8Array.fromArray(Array.make(~length=32, byte))

test("a character outside letters, digits and dots breaks Character", () => {
  ["a-b", "a_b", "a b", "é", "a/b"]->Array.forEach(text =>
    deepEqual(Names.standard(text), Error(Names.Character))
  )
})

test("an empty or too long extension breaks Length", () => {
  deepEqual(Names.standard(""), Error(Names.Length))
  deepEqual(Names.standard("a"->String.repeat(17)), Error(Names.Length))
  deepEqual(Names.standard("a"->String.repeat(16)), Ok("a"->String.repeat(16)))
})

test("a leading, trailing or doubled dot breaks Dot", () => {
  [".js", "js.", "a..b", "."]->Array.forEach(text =>
    deepEqual(Names.standard(text), Error(Names.Dot))
  )
})

test("the first broken rule wins in the order Character, Length, Dot", () => {
  deepEqual(Names.standard("-" ++ "a"->String.repeat(20)), Error(Names.Character))
  deepEqual(Names.standard("." ++ "a"->String.repeat(20)), Error(Names.Length))
})

test("an extension is lowered", () => deepEqual(Names.standard("PNG"), Ok("png")))

test("every row of the table of spellings is rewritten", () => {
  [
    ("jpg", "jpeg"),
    ("jpe", "jpeg"),
    ("tif", "tiff"),
    ("htm", "html"),
    ("xht", "xhtml"),
    ("mht", "mhtml"),
    ("mpg", "mpeg"),
    ("mpe", "mpeg"),
    ("mid", "midi"),
    ("aif", "aiff"),
    ("pct", "pict"),
    ("yml", "yaml"),
    ("sgm", "sgml"),
    ("djv", "djvu"),
    ("igs", "iges"),
    ("stp", "step"),
    ("tgz", "tar.gz"),
    ("tbz2", "tar.bz2"),
    ("tbz", "tar.bz2"),
    ("txz", "tar.xz"),
    ("tzst", "tar.zst"),
    ("markdown", "md"),
    ("text", "txt"),
    ("wave", "wav"),
  ]->Array.forEach(((spelled, full)) => {
    deepEqual(Names.standard(spelled), Ok(full))
    deepEqual(Names.standard(String.toUpperCase(spelled)), Ok(full))
  })
})

test("only the last part is rewritten and an unknown part is kept", () => {
  deepEqual(Names.standard("min.jpg"), Ok("min.jpeg"))
  deepEqual(Names.standard("jpg.min"), Ok("jpg.min"))
  deepEqual(Names.standard("tar.gz"), Ok("tar.gz"))
  deepEqual(Names.standard("a.tgz"), Ok("a.tar.gz"))
  deepEqual(Names.standard("svgz"), Ok("svgz"))
  deepEqual(Names.standard("ini"), Ok("ini"))
})

test("every rule has a plain message", () => {
  [Names.Character, Names.Length, Names.Dot]->Array.forEach(broken =>
    deepEqual(String.endsWith(Names.message(broken), "."), true)
  )
})

test("an object is its hash in hex and its extension", () => {
  deepEqual(Names.object(~hash=hashOf(171), ~extension=None), "ab"->String.repeat(32))
  deepEqual(
    Names.object(~hash=hashOf(1), ~extension=Some("tar.gz")),
    "01"->String.repeat(32) ++ ".tar.gz",
  )
})

test("parse reads an object back", () => {
  let bare = Names.object(~hash=hashOf(171), ~extension=None)
  let named = Names.object(~hash=hashOf(18), ~extension=Some("min.js"))
  deepEqual(Names.parse(bare), Some({Names.hash: hashOf(171), extension: None}))
  deepEqual(Names.parse(named), Some({Names.hash: hashOf(18), extension: Some("min.js")}))
})

test("parse refuses what is not an object", () => {
  let h = "ab"->String.repeat(32)
  [
    "",
    "ab",
    String.toUpperCase(h),
    h ++ "0",
    h ++ ".",
    h ++ ".JPG",
    h ++ ".jpg",
    h ++ ".a-b",
    h ++ "..js",
    "zz"->String.repeat(32),
  ]->Array.forEach(text => deepEqual(Names.parse(text), None))
})

test("content is content/{hash}", () => {
  deepEqual(Names.content(hashOf(171)), "content/" ++ "ab"->String.repeat(32))
})

test("a bucket is 8 lowercase hex digits and a slash", () => {
  deepEqual(Names.bucket(0.), "00000000/")
  deepEqual(Names.bucket(255.), "000000ff/")
  deepEqual(Names.bucket(4294967295.), "ffffffff/")
})

test("a marker is the bucket then the object", () => {
  deepEqual(Names.marker(~bucket=4294967295., "abc.png"), "ffffffff/abc.png")
})

test("a media type is by the last part of the extension", () => {
  deepEqual(Names.mediaType(None), "application/octet-stream")
  deepEqual(Names.mediaType(Some("png")), "image/png")
  deepEqual(Names.mediaType(Some("ico")), "image/vnd.microsoft.icon")
  deepEqual(Names.mediaType(Some("opus")), "audio/ogg")
  deepEqual(Names.mediaType(Some("min.js")), "text/javascript")
  deepEqual(Names.mediaType(Some("tar.gz")), "application/octet-stream")
  deepEqual(Names.mediaType(Some("unknown")), "application/octet-stream")
})
