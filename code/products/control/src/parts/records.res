/***
 * What both of the state's stores keep a record by, its secret sealed, its form and kinds by name,
 * and its JSON as read.
 */
module DeploymentForm = Envelope.Contracts.DeploymentForm
module DeploymentKind = Envelope.Contracts.DeploymentKind

// The key is the control's own until the keys library derives it from the masters.
// RFCs fhg6w and b8f35 hold that step.
/** A record's secret sealed for its place. */
let sealed = (sealing, ~kind, ~id, secret) =>
  Sealing.seal(sealing, ~kind, ~id, ~field="secret", secret)

/** Thrown before any write where the secret could not be sealed, no key given or not 32 bytes. */
let sealable = async (sealing, ~kind, secret) => {
  // Id 0 is no record's, and this seal is never kept.
  let _: string = await sealed(sealing, ~kind, ~id=0., secret)
}

/**
 * A record's secret read, a plain one handed to `writeBack` sealed where one is given, an empty one
 * a fault and never a secret.
 */
let opened = async (sealing, ~kind, ~id, text, ~writeBack=?) => {
  if text == "" {
    JsError.throwWithMessage(`the ${kind} ${Float.toString(id)} holds an empty secret`)
  }
  switch await Sealing.read(sealing, ~kind, ~id, ~field="secret", text) {
  | Opened(secret) => secret
  | Plain(secret) =>
    switch writeBack {
    | Some(writeBack) => await writeBack(await sealed(sealing, ~kind, ~id, secret))
    | None => ()
    }
    secret
  }
}

let formName = (form: DeploymentForm.t) =>
  switch form {
  | Modules => "modules"
  | Component => "component"
  | Image => "image"
  }

let formOf = name =>
  switch name {
  | "component" => Some(DeploymentForm.Component)
  | "image" => Some(Image)
  | "modules" => Some(Modules)
  | _ => None
  }

let kindName = (kind: DeploymentKind.t) => (kind :> string)

let kindOf = name =>
  switch name {
  | "function" => Some(DeploymentKind.Function)
  | "instance" => Some(Instance)
  | "container" => Some(Container)
  | _ => None
  }

/** Kinds read by their names, none where one is no kind's. */
let kindsOf = names => {
  let kinds = names->Array.filterMap(kindOf)
  kinds->Array.length == names->Array.length ? Some(kinds) : None
}

/** A release's kinds as D1 keeps them, their names joined by commas, an empty list as ''. */
let kindsText = kinds => kinds->Array.map(kindName)->Array.join(",")

let kindsOfText = text => text == "" ? Some([]) : kindsOf(text->String.split(","))

/** What the store answered, thrown where it did not answer, as the API answers what throws. */
let held = result =>
  switch result {
  | Ok(value) => value
  | Error(why) => JsError.throwWithMessage(`the objects were not reached, ${why}`)
  }

let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))
let number = (json, name) => json->field(name)->Option.flatMap(JSON.Decode.float)
let text = (json, name) => json->field(name)->Option.flatMap(JSON.Decode.string)

let organizationJson = (id, label, sealed) => JSON.Object(
  dict{
    "id": Number(id),
    "label": String(label),
    "secret": String(sealed),
  },
)
