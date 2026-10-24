/*** `Access` held to RFCs 3d3nt and rxmd9, a bearer and a token read, and a caller told. */
open Node

let secret = Uint8Array.fromArray(Array.make(~length=32, 7))

test("a bearer is the credential after its scheme, the scheme's case passed over", async () =>
  deepEqual(
    [Some("Bearer abc"), Some("bearer  abc "), Some("Basic abc"), Some("Bearer"), None]->Array.map(
      Access.bearer,
    ),
    [Some("abc"), Some("abc"), None, None, None],
  )
)

test("a token is a decimal id and 32 bytes in base64url, and reads back as written", async () => {
  let text = Access.tokenText(12., secret)
  deepEqual(Access.token(text), Some((12., secret)))
  deepEqual(
    [
      `012.${Envelope.Base64url.encode(secret)}`,
      "12.AAAA",
      "12",
      `x.${Envelope.Base64url.encode(secret)}`,
    ]->Array.map(Access.token),
    [None, None, None, None],
  )
})

test("bytes are equal only where every byte is, one length or another", async () => {
  let other = Uint8Array.fromArray(Array.make(~length=32, 7))
  other->TypedArray.set(31, 8)
  deepEqual(
    (
      Access.equal(secret, secret),
      Access.equal(secret, other),
      Access.equal(secret, Uint8Array.fromLength(31)),
    ),
    (true, false, false),
  )
})

test(
  "the operator is told by the Worker's secret, a host by its binding's, an organization by its own, anyone else is nobody",
  async () => {
    let held = async id => id == 12. ? Some(secret) : None
    let caller = header =>
      Access.caller(header, ~operator=Some("the operator"), ~secret=held, ~organizationSecret=held)
    let wrong = Uint8Array.fromLength(32)
    deepEqual(
      [
        await caller(Some("Bearer the operator")),
        await caller(Some("Bearer the operator ")),
        await caller(Some("Bearer someone")),
        await caller(Some(`Bearer ${Access.tokenText(12., secret)}`)),
        await caller(Some(`Bearer ${Access.tokenText(12., wrong)}`)),
        await caller(Some(`Bearer ${Access.tokenText(13., secret)}`)),
        await caller(Some(`Bearer ${Access.organizationText(12., secret)}`)),
        await caller(Some(`Bearer ${Access.organizationText(12., wrong)}`)),
        await caller(Some(`Bearer ${Access.organizationText(13., secret)}`)),
        await caller(None),
      ],
      [
        Operator,
        Operator,
        Nobody,
        Host(12.),
        Nobody,
        Nobody,
        Organization(12.),
        Nobody,
        Nobody,
        Nobody,
      ],
    )
    // A control given no operator's secret has no operator.
    deepEqual(
      await Access.caller(
        Some("Bearer "),
        ~operator=Some(""),
        ~secret=held,
        ~organizationSecret=held,
      ),
      Nobody,
    )
  },
)
