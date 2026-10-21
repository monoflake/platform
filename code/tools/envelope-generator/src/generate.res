/***
 * The generator, `src/generate.resi`: the contracts read, `generate/read.res`, and written whole,
 * here, by `generate/write.res`. `generate.rs` beside it is the same in Rust.
 */
open Model
open Names
open Write

type unread = Model.unread = {at: string, expected: string}
type contracts = Model.contracts

let read = Read.read

let rescript = (contracts: contracts) =>
  caught(() => {
    let modules =
      contracts.types->Array.mapWithIndex(((name, _), _) => upper(name, ["types", name]))
    modules->Array.forEachWithIndex((m, i) => {
      let (name, _) = contracts.types->Array.getUnsafe(i)
      if reserved->Array.includes(m) || modules->Array.slice(~start=0, ~end=i)->Array.includes(m) {
        fail(["types", name], "a name whose module no other has")
      }
    })
    let names = {
      modules: Map.fromArray(
        contracts.types->Array.mapWithIndex(((name, _), i) => (name, modules->Array.getUnsafe(i))),
      ),
    }
    let lines = [
      "/***\n * Written by envelope-generator from `model/contracts.json`, `model/graph/tools.res`: what\n * `src/malformed.resi` says this module holds. Never edited; `mise run generate` writes it again.\n */",
    ]
    groups(contracts.types)->Array.forEach(((group, recursive)) =>
      if recursive {
        group->Array.forEachWithIndex(
          ((name, def), i) => {
            let (types, functions) = typeModule(names, def, ["types", name])
            let m = moduleOf(names, name, [])
            lines->Array.push(
              `${i == 0 ? "module rec" : "and"} ${m}: { ${[...types, ...signature]->Array.join(
                  "\n",
                )} } = { ${[...types, ...functions]->Array.join("\n")} }`,
            )
          },
        )
      } else {
        group->Array.forEach(
          ((name, def)) => {
            let (types, functions) = typeModule(names, def, ["types", name])
            lines->Array.push(
              `module ${moduleOf(names, name, [])} = { ${[...types, ...functions]->Array.join(
                  "\n",
                )} }`,
            )
          },
        )
      }
    )
    let (types, functions) = typeModule({modules: Map.make()}, Record(contracts.shell), ["shell"])
    lines->Array.push(`module Shell = { ${[...types, ...functions]->Array.join("\n")} }`)
    lines->Array.push(answerModule(names, contracts))
    // The reasons, their failure a choice of the type `failure`.
    let failures = switch contracts.types->Array.find(((name, _)) => name == "failure") {
    | Some((_, Enum(choices))) => choices->Array.map(c => c.name)
    | Some((_, Record(_) | Union(_) | Flags(_))) | None =>
      fail(["types", "failure"], "an enumeration, the failures a reason is one of")
    }
    let reason = (r: reason, at) => {
      if !(failures->Array.includes(r.failure)) {
        fail([...at, "failure"], `one of ${failures->Array.join(", ")}`)
      }
      let message = switch contracts.messages->Array.find(((name, _)) => name == r.name) {
      | Some((_, message)) => message
      | None => fail([...at, "name"], "a reason messages gives a message")
      }
      `{name: ${quote(r.name)}, failure: Failure.${upper(
          r.failure,
          [...at, "failure"],
        )}, message: ${quote(message)}}`
    }
    let reasons = (rs, at) =>
      `[${rs->Array.mapWithIndex((r, i) => reason(r, [...at, Int.toString(i)]))->Array.join(", ")}]`
    lines->Array.pushMany([
      "type reason = {name: string, failure: Failure.t, message: string}",
      "type operation = {interface: string, version: int, name: string, input: string, output: string, reasons: array<reason>}",
      `let reasons: array<reason> = ${reasons(contracts.reasons, ["reasons"])}`,
      `let calling: array<reason> = ${reasons(contracts.calling, ["calling"])}`,
      `let messages: dict<string> = Dict.fromArray([${contracts.messages
        ->Array.map(((name, message)) => `(${quote(name)}, ${quote(message)})`)
        ->Array.join(", ")}])`,
    ])
    let (callFields, interfaceField, operationField, inputField, capabilitiesField) = roles(
      contracts.call,
    )
    // Within `Interface`, a module of an interface's hides any of the same name the rest names.
    let named =
      contracts.interfaces->Array.flatMap(i =>
        i.operations->Array.mapWithIndex(
          (o, k) =>
            moduleOf(
              names,
              o.input,
              ["interfaces", i.name, "operations", Int.toString(k), "input"],
            ),
        )
      )
    let interfaces = contracts.interfaces->Array.map(i => {
      let at = ["interfaces", i.name]
      let m = upper(i.name, at)
      if m == "Failure" || reserved->Array.includes(m) || named->Array.includes(m) {
        fail(at, "a name whose module hides no type's this module names")
      }
      if i.operations->Array.length == 0 {
        fail([...at, "operations"], "an operation at least")
      }
      let values =
        i.operations->Array.mapWithIndex(
          (o, n) => lower(o.name, [...at, "operations", Int.toString(n), "name"]),
        )
      let own = ["version", "toJson", "fromJson", "toCbor", "fromCbor"]
      distinct(
        [...own, ...values],
        n => [...at, "operations", Int.toString(n - own->Array.length), "name"],
        "a name no other operation has, nor version, toJson, fromJson, toCbor or fromCbor",
      )
      let constructors =
        i.operations->Array.mapWithIndex(
          (o, n) => upper(o.name, [...at, "operations", Int.toString(n), "name"]),
        )
      distinct(
        constructors,
        n => [...at, "operations", Int.toString(n), "name"],
        "a name no other operation has in upper camel case",
      )
      let each = f =>
        i.operations
        ->Array.mapWithIndex(
          (o, n) => f(o, constructors->Array.getUnsafe(n), moduleOf(names, o.input, [])),
        )
        ->Array.join(" ")
      let isJson = side =>
        switch side {
        | ToJson | FromJson => true
        | ToCbor | FromCbor => false
        }
      let refer = (side, f: callField) =>
        isJson(side) ? quote(f.name) : `${Int.toString(f.key)}, ${quote(f.name)}`
      let written = side => {
        let w = `Wire.${sideName(side)}`
        let items = callFields->Array.map(
          ((f, role)) => {
            let name = isJson(side) ? quote(f.name) : Int.toString(f.key)
            switch role {
            | InterfaceName => `${w}.field(${name}, ${quote(i.name)}, ${w}.string)`
            | OperationName => `${w}.field(${name}, operation, ${w}.string)`
            | OperationInput => `${w}.field(${name}, input, ${w}.${isJson(side) ? "json" : "cbor"})`
            | Capabilities =>
              `${w}.optional(${name}, Wire.nonEmpty(v.capabilities), ${w}.list(${w}.bytes))`
            }
          },
        )
        `let ${function(side)} = (v: envelope) => { let (operation, input) = switch v.call { ${each(
            (o, k, m) => `| ${k}(input) => (${quote(o.name)}, ${m}.${function(side)}(input))`,
          )} }
${w}.record([${items->Array.join(", ")}]) }`
      }
      let read = side => {
        let w = `Wire.${sideName(side)}`
        let value = isJson(side) ? "json" : "cbor"
        let unknown = isJson(side) ? "unknown" : "unknownText"
        let names_ = i.operations->Array.map(o => quote(o.name))->Array.join(", ")
        `let ${function(side)} = ${value} => ${w}.record(${value}, o => { ${w}.field(o, ${refer(
            side,
            interfaceField,
          )}, ${w}.exactly(${quote(i.name)}))->ignore
let call = switch ${w}.field(o, ${refer(side, operationField)}, ${w}.string) { ${each(
            (o, k, m) =>
              `| ${quote(o.name)} => ${k}(${w}.field(o, ${refer(
                  side,
                  inputField,
                )}, ${w}.named(${m}.${function(side)})))`,
          )} | _ => ${w}.${unknown}(${quote(operationField.name)}, [${names_}]) }
{call, capabilities: Wire.orEmpty(${w}.optional(o, ${refer(
            side,
            capabilitiesField,
          )}, ${w}.list(${w}.bytes)))} })`
      }
      let call = [
        `type call = ${each((_, k, m) => `| ${k}(${m}.t)`)}`,
        "type envelope = {call: call, capabilities: array<Uint8Array.t>}",
        written(ToJson),
        read(FromJson),
        written(ToCbor),
        read(FromCbor),
      ]
      let operations = i.operations->Array.mapWithIndex(
        (o, n) => {
          let at = [...at, "operations", Int.toString(n)]
          let _: string = moduleOf(names, o.input, [...at, "input"])
          let _: string = moduleOf(names, o.output, [...at, "output"])
          `let ${values->Array.getUnsafe(n)}: operation = {interface: ${quote(
              i.name,
            )}, version: ${Int.toString(i.version)}, name: ${quote(o.name)}, input: ${quote(
              o.input,
            )}, output: ${quote(o.output)}, reasons: ${reasons(o.reasons, [...at, "reasons"])}}`
        },
      )
      `module ${m} = { let version = ${Int.toString(i.version)}\n${[
          ...operations,
          ...call,
        ]->Array.join("\n")} }`
    })
    distinct(
      contracts.interfaces->Array.map(i => upper(i.name, ["interfaces", i.name])),
      n => ["interfaces", (contracts.interfaces->Array.getUnsafe(n)).name],
      "a name whose module no other interface has",
    )
    lines->Array.push(`module Interface = { ${interfaces->Array.join("\n")} }`)
    let byName = (f, (name, _)) =>
      `| ${quote(name)} => Some(${f(moduleOf(names, name, ["types", name]))})`
    let switched = f =>
      `switch name { ${contracts.types
        ->Array.map(t => byName(f, t))
        ->Array.join(" ")} | _ => None }`
    let calls = f =>
      `switch interface { ${contracts.interfaces
        ->Array.map(i =>
          `| ${quote(i.name)} => Some(${f(`Interface.${upper(i.name, ["interfaces", i.name])}`)})`
        )
        ->Array.join(" ")} | _ => None }`
    lines->Array.pushMany([
      `let callJsonToCbor = (interface, json) => ${calls(m =>
          `Wire.jsonToCbor(json, ${m}.fromJson, ${m}.toCbor)`
        )}`,
      `let callCborToJson = (interface, cbor) => ${calls(m =>
          `Wire.cborToJson(cbor, ${m}.fromCbor, ${m}.toJson)`
        )}`,
    ])
    lines->Array.pushMany([
      `let jsonToCbor = (name, json) => ${switched(m =>
          `Wire.jsonToCbor(json, ${m}.fromJson, ${m}.toCbor)`
        )}`,
      `let cborToJson = (name, cbor) => ${switched(m =>
          `Wire.cborToJson(cbor, ${m}.fromCbor, ${m}.toJson)`
        )}`,
    ])
    lines->Array.join("\n\n") ++ "\n"
  })
