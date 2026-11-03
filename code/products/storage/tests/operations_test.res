/***
 * `Operations` held to RFC 13ixj through the `object` kind in memory, every test but `too_large`
 * reaching `Names`.
 */
open Node
open Envelope

let salt = Uint8Array.fromArray(Array.fromInitializer(~length=32, i => i))
let hello = Uint8Array.fromArray([104, 101, 108, 108, 111])
let world = Uint8Array.fromArray([119, 111, 114, 108, 100])
let hashOf = content =>
  switch Keys.Hash.keyed(~salt, content) {
  | Ok(hash) => hash
  | Error(_) => throw(Failure("the salt is 32 bytes"))
  }

/** The kind's names spelled here apart from `Names`, bucket 1 alone. */
let contentOf = content => `content/${Hex.encode(hashOf(content))}`
let markerOf = object => `00000001/${object}`

let fresh = () => {
  let fake = Objects.make()
  (fake, {Operations.salt, objects: fake.objects})
}

let written = async (context, ~content=hello, ~extension=?) =>
  switch await Operations.write(context, {bucket: 1., content, ?extension}) {
  | Success(object) => object
  | Error({reason}) => throw(Failure(`write answered ${reason}`))
  }

let gone: Contracts.Answer.t<'a> = Error({
  failure: Unavailable,
  reason: "unavailable",
  message: "What the name holds cannot be given now",
})

let absent: Contracts.Answer.t<Contracts.ObjectDescribed.t> = Success({})
let deleted: Contracts.Answer.t<Contracts.ObjectDeleted.t> = Success({})

let notFound: Contracts.Answer.t<'a> = Error({
  failure: Rejected,
  reason: "not_found",
  message: "Nothing of that name or id exists",
})

testAsync("an object written is read and described by its name", async () => {
  let (fake, context) = fresh()
  let {object, hash, size} = await written(context, ~extension="txt")
  deepEqual(hash, hashOf(hello))
  deepEqual(size, 5.)
  deepEqual(
    fake.calls,
    [`describe ${contentOf(hello)}`, `write ${contentOf(hello)}`, `write ${markerOf(object)}`],
  )
  deepEqual(fake.held->Dict.get(markerOf(object)), Some(Uint8Array.fromArray([53])))
  deepEqual(
    await Operations.read(context, {bucket: 1., object}),
    Success({content: hello, size: 5.}),
  )
  deepEqual(await Operations.describe(context, {bucket: 1., object}), Success({size: 5.}))
})

testAsync("the same content written twice is written once", async () => {
  let (fake, context) = fresh()
  let first = await written(context, ~extension="txt")
  let second = await written(context, ~extension="txt")
  deepEqual(first, second)
  deepEqual(fake.calls->Array.filter(call => call == `write ${contentOf(hello)}`)->Array.length, 1)
  deepEqual(
    fake.calls->Array.slice(~start=3, ~end=5),
    [`describe ${contentOf(hello)}`, `write ${markerOf(second.object)}`],
  )
})

testAsync("two extensions give two objects over one content", async () => {
  let (fake, context) = fresh()
  let text = await written(context, ~extension="txt")
  let markdown = await written(context, ~extension="md")
  deepEqual(text.hash, markdown.hash)
  deepEqual(text.object == markdown.object, false)
  deepEqual(
    fake.held->Dict.keysToArray->Array.toSorted(String.compare),
    [contentOf(hello), markerOf(text.object), markerOf(markdown.object)]->Array.toSorted(
      String.compare,
    ),
  )
})

testAsync("a range reads that part of the content beside its whole size", async () => {
  let (_, context) = fresh()
  let {object} = await written(context)
  deepEqual(
    await Operations.read(context, {bucket: 1., object, range: {start: 1., length: 3.}}),
    Success({content: Uint8Array.fromArray([101, 108, 108]), size: 5.}),
  )
})

testAsync("a delete removes the name and leaves the content", async () => {
  let (fake, context) = fresh()
  let {object} = await written(context, ~extension="txt")
  deepEqual(await Operations.delete(context, {bucket: 1., object}), deleted)
  deepEqual(fake.held->Dict.has(contentOf(hello)), true)
  deepEqual(fake.held->Dict.has(markerOf(object)), false)
  deepEqual(await Operations.describe(context, {bucket: 1., object}), absent)
  deepEqual(await Operations.read(context, {bucket: 1., object}), notFound)
})

testAsync("an object never written is not found, absent, and deleted as absent", async () => {
  let (_, context) = fresh()
  let object = `${"0"->String.repeat(64)}.txt`
  deepEqual(await Operations.read(context, {bucket: 1., object}), notFound)
  deepEqual(await Operations.describe(context, {bucket: 1., object}), absent)
  deepEqual(await Operations.delete(context, {bucket: 1., object}), deleted)
})

testAsync("a lost content's object is listed by its name, then read as unavailable", async () => {
  let (fake, context) = fresh()
  let {object, hash} = await written(context, ~extension="txt")
  fake.held->Dict.delete(contentOf(hello))
  deepEqual(
    await Operations.list(context, {bucket: 1.}),
    Success({Contracts.BucketObjectListed.objects: [{object, hash, size: 5.}]}),
  )
  deepEqual(await Operations.read(context, {bucket: 1., object}), gone)
  deepEqual(await Operations.describe(context, {bucket: 1., object}), gone)
})

testAsync("content past 16 MiB is too large and reaches no kind", async () => {
  let (fake, context) = fresh()
  let content = Uint8Array.fromLength(16 * 1024 * 1024 + 1)
  deepEqual(
    await Operations.write(context, {bucket: 1., content}),
    Error({failure: Rejected, reason: "too_large", message: "The input is larger than its bound"}),
  )
  deepEqual(fake.calls, [])
})

testAsync("an extension breaking a rule is refused saying which", async () => {
  let (fake, context) = fresh()
  deepEqual(
    await Operations.write(context, {bucket: 1., content: hello, extension: "a..b"}),
    Error({failure: Rejected, reason: "extension_invalid", message: Names.message(Dot)}),
  )
  deepEqual(fake.calls, [])
})

testAsync("a bucket's objects are listed a page at a time", async () => {
  let (fake, context) = fresh()
  let one = await written(context, ~extension="txt")
  let two = await written(context, ~content=world, ~extension="txt")
  let calls = Array.length(fake.calls)
  let first = switch await Operations.list(context, {bucket: 1., limit: 1.}) {
  | Success(listed) => listed
  | Error({reason}) => throw(Failure(`list answered ${reason}`))
  }
  deepEqual(fake.calls->Array.at(calls), Some("list 00000001/"))
  deepEqual(Array.length(first.objects), 1)
  let second = switch await Operations.list(context, {bucket: 1., after: ?first.next}) {
  | Success(listed) => listed
  | Error({reason}) => throw(Failure(`list answered ${reason}`))
  }
  deepEqual(second.next, None)
  let sorted = [one, two]->Array.toSorted((a, b) => String.compare(a.object, b.object))
  deepEqual(Array.concat(first.objects, second.objects), sorted)
  let firstObject = first.objects->Array.map(o => o.object)
  deepEqual(first.next, firstObject->Array.get(0))
})

/** A call's step as the driver adds it, RFC 49qyg. */
let step: Contracts.CallStep.t = {
  id: "0123456789abcdef",
  sequence: 2.,
  expires: 1767225600000.,
  last: true,
}

/** The kind with its name writes answered by `answer` and every write it is given kept. */
let named = (fake: Objects.t, answer) => {
  let writes: array<Contracts.ObjectWrite.t> = []
  let objects = {
    ...fake.objects,
    write: input => {
      writes->Array.push(input)
      input.name->String.startsWith(markerOf("")) ? answer(input) : fake.objects.write(input)
    },
  }
  (writes, {Operations.salt, objects})
}

let callOf = (answer: Contracts.Answer.t<Contracts.BucketObject.t>) =>
  switch answer {
  | Error({?call}) => call
  | Success(_) => None
  }

testAsync(
  "a call's step goes unchanged to the name's write and never to the content's",
  async () => {
    let (fake, _) = fresh()
    let (writes, context) = named(fake, fake.objects.write)
    let {object} = switch await Operations.write(
      context,
      {bucket: 1., content: hello, extension: "txt", call: step},
    ) {
    | Success(object) => object
    | Error({reason}) => throw(Failure(`write answered ${reason}`))
    }
    deepEqual(
      writes->Array.map(write => (write.name, write.call)),
      [(contentOf(hello), None), (markerOf(object), Some(step))],
    )
  },
)

testAsync(
  "a name's write refused is an object certainly not written, its reason kept where declared",
  async () => {
    let refusals = [
      (Contracts.Failure.Rejected, "expired", Contracts.Failure.Unavailable, "unavailable"),
      (Rejected, "too_large", Rejected, "too_large"),
      (Unavailable, "storage_full", Unavailable, "storage_full"),
      (Unavailable, "unreachable", Unavailable, "unavailable"),
    ]
    for i in 0 to Array.length(refusals) - 1 {
      let (failure, reason, toldFailure, told) = refusals->Array.getUnsafe(i)
      let message = Contracts.messages->Dict.get(reason)->Option.getOr("")
      let (fake, _) = fresh()
      let (_, context) = named(fake, async _ => Error({
        failure,
        reason,
        message,
        call: {id: step.id, looked: 5., step: 2.},
      }))
      let answer = await Operations.write(context, {bucket: 1., content: hello, call: step})
      deepEqual(answer, Error({failure: toldFailure, reason: told, message}), ~message=reason)
      deepEqual(callOf(answer), None)
    }
  },
)

testAsync("a name's write answered unknown may have landed, and is unknown", async () => {
  let (fake, _) = fresh()
  let message = "The implementation failed while answering"
  let (_, context) = named(fake, async _ => Error({
    failure: Unknown,
    reason: "fault",
    message,
    call: {id: step.id, looked: 5.},
  }))
  let answer = await Operations.write(context, {bucket: 1., content: hello, call: step})
  deepEqual(answer, Error({failure: Unknown, reason: "fault", message}))
  deepEqual(callOf(answer), None)
})

testAsync("a name's write thrown after it was sent may have landed, and is unknown", async () => {
  let (fake, _) = fresh()
  let (writes, context) = named(fake, async _ => throw(Failure("the connection closed")))
  let answer = await Operations.write(context, {bucket: 1., content: hello, call: step})
  switch answer {
  | Error({failure, reason}) => deepEqual((failure, reason), (Unknown, "fault"))
  | Success(_) => deepEqual(answer, Error({failure: Unknown, reason: "fault", message: ""}))
  }
  deepEqual(callOf(answer), None)
  deepEqual(Array.length(writes), 2)
})
