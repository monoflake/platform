open Envelope

type objects = {
  status: Contracts.ObjectStatus.t => promise<Contracts.Answer.t<Contracts.CallSteps.t>>,
  write: Contracts.ObjectWrite.t => promise<Contracts.Answer.t<Contracts.ObjectWritten.t>>,
  read: Contracts.ObjectRead.t => promise<Contracts.Answer.t<Contracts.ObjectContent.t>>,
  describe: Contracts.ObjectName.t => promise<Contracts.Answer.t<Contracts.ObjectDescribed.t>>,
  delete: Contracts.ObjectName.t => promise<Contracts.Answer.t<Contracts.ObjectDeleted.t>>,
  list: Contracts.ObjectList.t => promise<Contracts.Answer.t<Contracts.ObjectListed.t>>,
}
type context = {salt: Uint8Array.t, objects: objects}

/** The most bytes the `object` kind holds, `most` in model/contracts/kinds/objects.res. */
let most =
  16 * 1024 * 1024

let refused = (failure, reason, ~message=?): Contracts.Answer.t<'a> => Error({
  failure,
  reason,
  message: switch message {
  | Some(message) => message
  | None => Contracts.messages->Dict.get(reason)->Option.getOr("")
  },
})

/** An error the kind answered, passed on as it came. */
let passed = (error): Contracts.Answer.t<'a> => Error(error)

/** A name held whose content cannot be given, RFC 13ixj, the author's C20. */
let gone = () => refused(Unavailable, "unavailable")

/** A name records its object's size as decimal text, so a listing needs no content. */
let recorded = size =>
  Float.toString(size)
  ->String.split("")
  ->Array.map(digit => digit->String.charCodeAt(0)->Option.getOr(0))
  ->Uint8Array.fromArray
let sizeOf = bytes => {
  let text = ref("")
  bytes->TypedArray.forEach(byte => text := text.contents ++ String.fromCharCode(byte))
  Float.fromString(text.contents)
}

/** The reasons `object_write` may answer, its own and every operation's, RFC ge55b. */
let declared = Array.concat(
  Contracts.Interface.Storage.objectWrite.reasons,
  Contracts.reasons,
)->Array.map(reason => reason.name)

/** Said where the name's write threw, so whether it landed cannot be told. */
let untold = "Whether the object's name was written cannot be told now"

/**
 * The name's write, the call's second step, classified by RFC 49qyg's outcomes; the error's `call`
 * waits on the author and is never set.
 */
let named = (answer: Contracts.Answer.t<Contracts.ObjectWritten.t>, object) =>
  switch answer {
  | Success(_) => Contracts.Answer.Success(object)
  // Certainly not written: a declared reason keeps its declared failure, any other is unavailable.
  | Error({failure: (Rejected | Unavailable) as failure, reason, message}) =>
    declared->Array.includes(reason)
      ? Error({failure, reason, message})
      : Error({failure: Unavailable, reason: "unavailable", message})
  | Error({failure: Unknown, message}) => Error({failure: Unknown, reason: "fault", message})
  }

/** Takes a prefix off a name the kind listed under it, none for a name outside it. */
let unprefixed = (name, prefix) =>
  name->String.startsWith(prefix)
    ? Some(name->String.slice(~start=String.length(prefix), ~end=String.length(name)))
    : None

let write = async (context, input: Contracts.BucketObjectWrite.t) =>
  if TypedArray.length(input.content) > most {
    refused(Rejected, "too_large")
  } else {
    let extension = switch input.extension {
    | None => Ok(None)
    | Some(given) => Names.standard(given)->Result.map(standard => Some(standard))
    }
    switch (extension, Keys.Hash.keyed(~salt=context.salt, input.content)) {
    | (Error(broken), _) => refused(Rejected, "extension_invalid", ~message=Names.message(broken))
    | (Ok(_), Error(_)) => refused(Unknown, "fault")
    | (Ok(extension), Ok(hash)) =>
      let content = Names.content(hash)
      let held: result<unit, Contracts.Error.t> = switch await context.objects.describe({
        name: content,
      }) {
      | Error(error) => Error(error)
      | Success({size: ?Some(_)}) => Ok()
      | Success({size: ?None}) =>
        switch await context.objects.write({name: content, content: input.content}) {
        | Error(error) => Error(error)
        | Success(_) => Ok()
        }
      }
      switch held {
      | Error(error) => passed(error)
      | Ok() =>
        let object = Names.object(~hash, ~extension)
        let marker = Names.marker(~bucket=input.bucket, object)
        let size = TypedArray.length(input.content)->Int.toFloat
        // A write thrown after it was sent may have landed, so it is told as unknown.
        let answer = try await context.objects.write({
          name: marker,
          content: recorded(size),
          call: ?input.call,
        }) catch {
        | _ => refused(Unknown, "fault", ~message=untold)
        }
        named(answer, {Contracts.BucketObject.object, hash, size})
      }
    }
  }

let read = async (context, input: Contracts.BucketObjectRead.t) =>
  switch Names.parse(input.object) {
  | None => refused(Rejected, "not_found")
  | Some({hash}) =>
    let marker = Names.marker(~bucket=input.bucket, input.object)
    switch await context.objects.describe({name: marker}) {
    | Error(error) => passed(error)
    | Success({size: ?None}) => refused(Rejected, "not_found")
    | Success({size: ?Some(_)}) =>
      switch await context.objects.read({name: Names.content(hash), range: ?input.range}) {
      | Error({reason: "not_found"}) => gone()
      | Error(error) => passed(error)
      | Success(content) => Success(content)
      }
    }
  }

let describe = async (context, input: Contracts.BucketObjectName.t) =>
  switch Names.parse(input.object) {
  | None => Contracts.Answer.Success(({}: Contracts.ObjectDescribed.t))
  | Some({hash}) =>
    let marker = Names.marker(~bucket=input.bucket, input.object)
    switch await context.objects.describe({name: marker}) {
    | Error(error) => passed(error)
    | Success({size: ?None}) => Success({})
    | Success({size: ?Some(_)}) =>
      switch await context.objects.describe({name: Names.content(hash)}) {
      | Error(error) => passed(error)
      | Success({size: ?None}) => gone()
      | Success({size: ?Some(size)}) => Success({size: size})
      }
    }
  }

let delete = async (context, input: Contracts.BucketObjectName.t) =>
  switch Names.parse(input.object) {
  | None => Contracts.Answer.Success(({}: Contracts.ObjectDeleted.t))
  | Some(_) =>
    await context.objects.delete({name: Names.marker(~bucket=input.bucket, input.object)})
  }

let list = async (context, input: Contracts.BucketObjectList.t) => {
  let prefix = Names.bucket(input.bucket)
  let after = input.after->Option.map(after => Names.marker(~bucket=input.bucket, after))
  switch await context.objects.list({prefix, ?after, limit: ?input.limit}) {
  | Error(error) => passed(error)
  | Success(listed) =>
    // Each name's recorded size is read in the order listed, its content never asked.
    let found: array<Contracts.BucketObject.t> = []
    let failed: ref<option<Contracts.Error.t>> = ref(None)
    let names = listed.objects
    let i = ref(0)
    while failed.contents == None && i.contents < Array.length(names) {
      let one = names->Array.getUnsafe(i.contents)
      i := i.contents + 1
      switch unprefixed(one.name, prefix)->Option.flatMap(object =>
        Names.parse(object)->Option.map(named => (object, named))
      ) {
      | None => ()
      | Some((object, {hash})) =>
        switch await context.objects.read({name: one.name}) {
        | Error({reason: "not_found"}) => ()
        | Error(error) => failed := Some(error)
        | Success({content}) =>
          sizeOf(content)->Option.forEach(size => found->Array.push({object, hash, size}))
        }
      }
    }
    switch failed.contents {
    | Some(error) => passed(error)
    | None =>
      switch listed.next->Option.flatMap(next => unprefixed(next, prefix)) {
      | Some(next) => Success({Contracts.BucketObjectListed.objects: found, next})
      | None => Success({Contracts.BucketObjectListed.objects: found})
      }
    }
  }
}
