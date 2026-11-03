type broken = Character | Length | Dot
let longest = 16

let message = broken =>
  switch broken {
  | Character => "An extension may hold only ASCII letters, digits and dots."
  | Length => "An extension must hold from 1 to 16 characters."
  | Dot => "An extension must not begin or end with a dot or hold two dots in a row."
  }

// RFC 13ixj, the table of spellings. A row once written is never changed or removed.
let spellings = [
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
]

let isLetterOrDigit = code =>
  (code >= 48 && code <= 57) || code >= 65 && code <= 90 || (code >= 97 && code <= 122)

let characterBroken = text =>
  text
  ->String.split("")
  ->Array.some(c => {
    let code = c->String.charCodeAt(0)->Option.getOr(0)
    !(isLetterOrDigit(code) || c == ".")
  })

let standard = extension => {
  let length = String.length(extension)
  if characterBroken(extension) {
    Error(Character)
  } else if length < 1 || length > longest {
    Error(Length)
  } else if (
    String.startsWith(extension, ".") ||
    String.endsWith(extension, ".") ||
    String.includes(extension, "..")
  ) {
    Error(Dot)
  } else {
    let parts = extension->String.toLowerCase->String.split(".")
    let last = parts->Array.length - 1
    let spelled = switch parts->Array.get(last) {
    | Some(part) =>
      switch spellings->Array.find(((from, _)) => from == part) {
      | Some((_, full)) => full
      | None => part
      }
    | None => ""
    }
    Ok(Array.concat(parts->Array.slice(~start=0, ~end=last), [spelled])->Array.join("."))
  }
}

let object = (~hash, ~extension) => {
  let name = Envelope.Hex.encode(hash)
  switch extension {
  | Some(extension) => name ++ "." ++ extension
  | None => name
  }
}

type named = {hash: Uint8Array.t, extension: option<string>}

let hashLength = 64

let parse = text => {
  let decode = hex =>
    if String.length(hex) == hashLength {
      Envelope.Hex.decode(hex)
    } else {
      None
    }
  switch text->String.indexOf(".") {
  | -1 => decode(text)->Option.map(hash => {hash, extension: None})
  | at =>
    let extension = text->String.slice(~start=at + 1)
    switch (decode(text->String.slice(~start=0, ~end=at)), standard(extension)) {
    | (Some(hash), Ok(kept)) if kept == extension => Some({hash, extension: Some(extension)})
    | (None, _) | (_, Error(_)) | (Some(_), Ok(_)) => None
    }
  }
}

let content = hash => "content/" ++ Envelope.Hex.encode(hash)

let bucket = id => {
  let hex = id->Float.toString(~radix=16)
  "0"->String.repeat(8 - String.length(hex)) ++ hex ++ "/"
}

let marker = (~bucket as id, name) => bucket(id) ++ name

let types = [
  ("png", "image/png"),
  ("jpeg", "image/jpeg"),
  ("gif", "image/gif"),
  ("webp", "image/webp"),
  ("avif", "image/avif"),
  ("apng", "image/apng"),
  ("jxl", "image/jxl"),
  ("bmp", "image/bmp"),
  ("ico", "image/vnd.microsoft.icon"),
  ("tiff", "image/tiff"),
  ("heic", "image/heic"),
  ("heif", "image/heif"),
  ("svg", "image/svg+xml"),
  ("mp3", "audio/mpeg"),
  ("m4a", "audio/mp4"),
  ("aac", "audio/aac"),
  ("ogg", "audio/ogg"),
  ("oga", "audio/ogg"),
  ("opus", "audio/ogg"),
  ("flac", "audio/flac"),
  ("wav", "audio/wav"),
  ("weba", "audio/webm"),
  ("mp4", "video/mp4"),
  ("webm", "video/webm"),
  ("ogv", "video/ogg"),
  ("mov", "video/quicktime"),
  ("woff2", "font/woff2"),
  ("woff", "font/woff"),
  ("ttf", "font/ttf"),
  ("otf", "font/otf"),
  ("txt", "text/plain"),
  ("md", "text/markdown"),
  ("csv", "text/csv"),
  ("tsv", "text/tab-separated-values"),
  ("vtt", "text/vtt"),
  ("html", "text/html"),
  ("css", "text/css"),
  ("js", "text/javascript"),
  ("mjs", "text/javascript"),
  ("json", "application/json"),
  ("xml", "application/xml"),
  ("xhtml", "application/xhtml+xml"),
  ("wasm", "application/wasm"),
  ("pdf", "application/pdf"),
]

let mediaType = extension =>
  switch extension {
  | None => "application/octet-stream"
  | Some(extension) =>
    let last = extension->String.split(".")->Array.at(-1)->Option.getOr("")
    switch types->Array.find(((name, _)) => name == last) {
    | Some((_, mediaType)) => mediaType
    | None => "application/octet-stream"
    }
  }
