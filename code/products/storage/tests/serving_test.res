/***
 * `Serving` held to RFC 13ixj's serving rules over the `object` kind in memory.
 */
open Node
open Envelope

let salt = Uint8Array.fromArray(Array.fromInitializer(~length=32, i => i))
let hello = Uint8Array.fromArray([104, 101, 108, 108, 111])

let fresh = () => {
  let fake = Objects.make()
  (fake, {Operations.salt, objects: fake.objects})
}

let stored = async (context, ~extension=?) =>
  switch await Operations.write(context, {bucket: 1., content: hello, ?extension}) {
  | Success({object, hash}) => (object, Hex.encode(hash))
  | Error({reason}) => throw(Failure(`write answered ${reason}`))
  }

let get = async (context, ~method="GET", ~headers=dict{}, path) => {
  let response = await Serving.fetch(
    context,
    Web.request(`http://storage${path}`, {method, headers}),
  )
  (response, await response->Web.text)
}

let headerOf = (response, name) =>
  response->Web.responseHeaders->Web.header(name)->Nullable.toOption

let cache = "public, max-age=31536000, immutable"

testAsync("a 200 carries the content and every header", async () => {
  let (_, context) = fresh()
  let (object, hash) = await stored(context, ~extension="png")
  let (response, text) = await get(context, `/v1/storage/00000001/${object}`)
  deepEqual(response->Web.status, 200)
  deepEqual(text, "hello")
  deepEqual(response->headerOf("content-type"), Some("image/png"))
  deepEqual(response->headerOf("content-length"), Some("5"))
  deepEqual(response->headerOf("etag"), Some(`"${hash}"`))
  deepEqual(response->headerOf("cache-control"), Some(cache))
  deepEqual(response->headerOf("x-content-type-options"), Some("nosniff"))
  deepEqual(response->headerOf("content-security-policy"), Some("sandbox"))
  deepEqual(response->headerOf("access-control-allow-origin"), Some("*"))
})

testAsync("a pdf is the one type served without the sandbox", async () => {
  let (_, context) = fresh()
  let (object, _) = await stored(context, ~extension="pdf")
  let (response, _) = await get(context, `/v1/storage/00000001/${object}`)
  deepEqual(response->headerOf("content-type"), Some("application/pdf"))
  deepEqual(response->headerOf("content-security-policy"), None)
})

testAsync("an object without an extension is served as octet-stream", async () => {
  let (_, context) = fresh()
  let (object, _) = await stored(context)
  let (response, _) = await get(context, `/v1/storage/00000001/${object}`)
  deepEqual(response->headerOf("content-type"), Some("application/octet-stream"))
})

testAsync("HEAD answers as GET with no body", async () => {
  let (_, context) = fresh()
  let (object, hash) = await stored(context, ~extension="png")
  let (response, text) = await get(context, ~method="HEAD", `/v1/storage/00000001/${object}`)
  deepEqual(response->Web.status, 200)
  deepEqual(text, "")
  deepEqual(response->headerOf("content-length"), Some("5"))
  deepEqual(response->headerOf("etag"), Some(`"${hash}"`))
})

testAsync("an If-None-Match of the ETag answers 304 with no body", async () => {
  let (_, context) = fresh()
  let (object, hash) = await stored(context, ~extension="png")
  let path = `/v1/storage/00000001/${object}`
  let (response, text) = await get(context, ~headers=dict{"if-none-match": `"${hash}"`}, path)
  deepEqual(response->Web.status, 304)
  deepEqual(text, "")
  deepEqual(response->headerOf("etag"), Some(`"${hash}"`))
  deepEqual(response->headerOf("cache-control"), Some(cache))
  let (other, _) = await get(context, ~headers=dict{"if-none-match": `"abc"`}, path)
  deepEqual(other->Web.status, 200)
})

testAsync("a bad version, bucket, hash or an unwritten name answers 404", async () => {
  let (_, context) = fresh()
  let (object, _) = await stored(context, ~extension="png")
  let hash = object->String.slice(~start=0, ~end=64)
  let paths = [
    `/v2/storage/00000001/${object}`,
    `/V1/storage/00000001/${object}`,
    `/1/storage/00000001/${object}`,
    `/v1/storage/1/${object}`,
    `/v1/storage/0000000G/${object}`,
    `/v1/storage/0000000A/${object}`,
    `/v1/storage/00000001/${hash->String.slice(~start=0, ~end=63)}.png`,
    `/v1/storage/00000001/${hash->String.toUpperCase}.png`,
    `/v1/storage/00000001/${object}/more`,
    `/v1/storage/00000002/${object}`,
    `/v1/storage/00000001/${object->String.replace(".png", ".jpeg")}`,
    `/v1/storage/00000001/${object->String.replace(".png", ".PNG")}`,
    `/elsewhere`,
  ]
  let statuses = await Promise.all(
    paths->Array.map(async path => {
      let (response, _) = await get(context, path)
      response->Web.status
    }),
  )
  deepEqual(statuses, paths->Array.map(_ => 404))
})

testAsync("content lost answers 503", async () => {
  let (fake, context) = fresh()
  let (object, hash) = await stored(context, ~extension="png")
  fake.held->Dict.delete(`content/${hash}`)
  let (response, _) = await get(context, `/v1/storage/00000001/${object}`)
  deepEqual(response->Web.status, 503)
})

testAsync("a method other than GET and HEAD answers 405", async () => {
  let (_, context) = fresh()
  let (object, _) = await stored(context, ~extension="png")
  let methods = ["POST", "PUT", "DELETE", "PATCH"]
  let statuses = await Promise.all(
    methods->Array.map(async method => {
      let (response, _) = await get(context, ~method, `/v1/storage/00000001/${object}`)
      response->Web.status
    }),
  )
  deepEqual(statuses, methods->Array.map(_ => 405))
})
