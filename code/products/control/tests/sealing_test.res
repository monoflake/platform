/*** `Sealing` held to RFC fhg6w, a secret sealed for its place and opened only there. */
open Node

let key = Some(Envelope.Base64url.encode(Uint8Array.fromArray(Array.make(~length=32, 3))))
let secret = Uint8Array.fromArray(Array.fromInitializer(~length=32, i => i))

let missing = "the control is given no SEALING_KEY, so it keeps and reads no secret"

let thrown = async f =>
  switch await f() {
  | _ => None
  | exception JsExn(e) => e->JsExn.message
  }

test("a secret sealed opens for its own place, a version byte and a nonce before it", async () => {
  let sealing = Sealing.ofKey(key)
  let text = await Sealing.seal(sealing, ~kind="organization", ~id=1., ~field="secret", secret)
  deepEqual(
    (text->String.slice(~start=0, ~end=2), text->String.length),
    ("01", 2 * (1 + 12 + 32 + 16)),
  )
  let again = await Sealing.seal(sealing, ~kind="organization", ~id=1., ~field="secret", secret)
  ok(again != text, ~message="two seals drew one nonce")
  deepEqual(
    await Sealing.read(sealing, ~kind="organization", ~id=1., ~field="secret", text),
    Sealing.Opened(secret),
  )
})

test(
  "a seal moved to another record or another key does not open, and is never plain",
  async () => {
    let sealing = Sealing.ofKey(key)
    let text = await Sealing.seal(sealing, ~kind="organization", ~id=1., ~field="secret", secret)
    let other = Sealing.ofKey(
      Some(Envelope.Base64url.encode(Uint8Array.fromArray(Array.make(~length=32, 4)))),
    )
    deepEqual(
      [
        await thrown(() =>
          Sealing.read(sealing, ~kind="organization", ~id=2., ~field="secret", text)
        ),
        await thrown(() => Sealing.read(sealing, ~kind="binding", ~id=1., ~field="secret", text)),
        await thrown(() =>
          Sealing.read(other, ~kind="organization", ~id=1., ~field="secret", text)
        ),
      ],
      [
        Some("the secret kept at organization:2:secret does not open under this key"),
        Some("the secret kept at binding:1:secret does not open under this key"),
        Some("the secret kept at organization:1:secret does not open under this key"),
      ],
    )
  },
)

test("a plain secret of 32 bytes is read as plain, and what is neither is refused", async () => {
  let sealing = Sealing.ofKey(key)
  deepEqual(
    await Sealing.read(
      sealing,
      ~kind="binding",
      ~id=1.,
      ~field="secret",
      Envelope.Hex.encode(secret),
    ),
    Sealing.Plain(secret),
  )
  deepEqual(
    await thrown(() => Sealing.read(sealing, ~kind="binding", ~id=1., ~field="secret", "02ab")),
    Some("the secret kept at binding:1:secret is neither sealed nor plain"),
  )
})

test("a secret not 32 bytes is refused, so no seal reads as plain", async () => {
  let sealing = Sealing.ofKey(key)
  let sealedOf = length =>
    thrown(() =>
      Sealing.seal(sealing, ~kind="binding", ~id=1., ~field="secret", Uint8Array.fromLength(length))
    )
  // A 3-byte secret once sealed to exactly 32 bytes, which a read took as a plain secret.
  deepEqual(
    [await sealedOf(3), await sealedOf(0), await sealedOf(33)],
    Array.make(~length=3, Some("the secret to seal at binding:1:secret is not 32 bytes")),
  )
})

test(
  "a control given no key, or a key not 32 bytes, refuses to keep or read a secret",
  async () => {
    let plain = Envelope.Hex.encode(secret)
    let refused = given => {
      let sealing = Sealing.ofKey(given)
      Promise.all([
        thrown(() => Sealing.seal(sealing, ~kind="binding", ~id=1., ~field="secret", secret)),
        thrown(() => Sealing.read(sealing, ~kind="binding", ~id=1., ~field="secret", plain)),
      ])
    }
    deepEqual(
      [await refused(None), await refused(Some("")), await refused(Some("AAAA"))],
      [
        [Some(missing), Some(missing)],
        [Some(missing), Some(missing)],
        [
          Some("the control's SEALING_KEY is not 32 bytes in base64url"),
          Some("the control's SEALING_KEY is not 32 bytes in base64url"),
        ],
      ],
    )
  },
)
