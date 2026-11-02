module C = Envelope.Contracts

let octalDigits = /^[0-7]+$/

let ingressText = ingress =>
  ingress->Option.mapOr("", items =>
    JSON.stringify(JSON.Array(items->Array.map(C.AppIngress.toJson)))
  )

let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))
let text = (json, name) => field(json, name)->Option.flatMap(JSON.Decode.string)
let names = name =>
  name != "" &&
  !(name->String.startsWith("/")) &&
  !(name->String.includes("\\")) &&
  name->String.split("/")->Array.every(p => p != "" && p != "." && p != "..")

let metadata = (json, ~ingress) => {
  let allowed = ["main_module", "compatibility_date", "compatibility_flags", "kinds", "ingress"]
  let keys =
    json
    ->JSON.Decode.object
    ->Option.mapOr(false, o => o->Dict.keysToArray->Array.every(k => allowed->Array.includes(k)))
  let kinds = switch field(json, "kinds") {
  | None => true
  | Some(value) => value == JSON.Array([C.DeploymentKind.toJson(Function)])
  }
  let sameIngress = switch field(json, "ingress") {
  | None => true
  | Some(value) => JSON.stringify(value) == ingress
  }
  let date =
    text(json, "compatibility_date")->Option.mapOr(false, d =>
      /^\d{4}-\d{2}-\d{2}$/->RegExp.test(d)
    )
  let flags = switch field(json, "compatibility_flags") {
  | None => true
  | Some(value) =>
    value
    ->JSON.Decode.array
    ->Option.mapOr(false, a => a->Array.every(v => v->JSON.Decode.string->Option.isSome))
  }
  keys && kinds && sameIngress && date && flags
}

let valid = (bytes, ~ingress) => {
  let length = bytes->TypedArray.length
  let byte = at => bytes->TypedArray.get(at)->Option.getOr(0)
  let stringAt = (start, size) => Web.fromUtf8(bytes->TypedArray.slice(~start, ~end=start + size))
  let terminated = (start, size) =>
    stringAt(start, size)->String.split("\x00")->Array.at(0)->Option.getOr("")
  let octal = (start, size) => {
    let text = terminated(start, size)->String.trim
    octalDigits->RegExp.test(text) ? Int.fromString(text, ~radix=8) : None
  }
  let at = ref(0)
  let good = ref(length >= 2048 && mod(length, 512) == 0)
  let ended = ref(false)
  let files: dict<bool> = dict{}
  let main = ref(None)
  while good.contents && !ended.contents && at.contents + 512 <= length {
    let start = at.contents
    if byte(start) == 0 {
      ended := true
      good := length - start >= 1024
      for i in start to length - 1 {
        if byte(i) != 0 {
          good := false
        }
      }
    } else {
      let name = terminated(start, 100)
      let sum = ref(0)
      for i in 0 to 511 {
        sum := sum.contents + (i >= 148 && i < 156 ? 32 : byte(start + i))
      }
      switch (octal(start + 124, 12), octal(start + 148, 8)) {
      | (Some(size), Some(checksum)) if size >= 0 && size <= length - start - 512 =>
        let regular = byte(start + 156) == 48 || byte(start + 156) == 0
        good :=
          checksum == sum.contents &&
          regular &&
          names(name) &&
          files->Dict.get(name) == None &&
          terminated(start + 157, 100) == "" &&
          terminated(start + 345, 155) == "" &&
          stringAt(start + 257, 6) == "ustar\x00"
        files->Dict.set(name, true)
        if name == "metadata.json" {
          switch JSON.parseOrThrow(stringAt(start + 512, size)) {
          | json =>
            good := good.contents && metadata(json, ~ingress)
            main := text(json, "main_module")
          | exception JsExn(_) => good := false
          }
        }
        at := start + 512 + (size + 511) / 512 * 512
      | _ => good := false
      }
    }
  }
  good.contents &&
  ended.contents &&
  main.contents->Option.mapOr(false, name =>
    name != "metadata.json" && names(name) && files->Dict.get(name) == Some(true)
  )
}
