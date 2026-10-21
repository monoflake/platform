/***
 * A component's interfaces served alike on a Worker and on workerd, each call read, verified,
 * handled and answered as RFCs vr5lw and ge55b lay out. The model's interface, `docs/code.md`.
 */

/** A request as both runtimes give it, its method, path, two headers and body. */
type request = {
  method_: string,
  path: string,
  contentType: option<string>,
  accept: option<string>,
  body: Uint8Array.t,
}

/** A response, its HTTP status, its `Content-Type` and its body. */
type response = {status: int, contentType: string, body: Uint8Array.t}

/** Who made a call, a certificate's verified signer, or nobody where it came unsigned. */
type caller = Signed(Capability.Signed.signer) | Unsigned

/** What a handler answers, its output written in either form, or an error. */
type output

/** An output, by its type's writers, as each of `Envelope.Contracts`' types holds them. */
let output: ('a, ~toJson: 'a => JSON.t, ~toCbor: 'a => Codec.Cbor.value) => output

/**
 * What a handler answers, an output or an error by its reason, with the reason's own message unless
 * one is given.
 */
type answer = Output(output) | Refused({reason: string, message: option<string>})

/**
 * An interface a component answers, its name, how its `envelope` is read, its declared reasons and
 * its handler.
 */
type interface_<'envelope> = {
  name: string,
  fromJson: JSON.t => result<'envelope, Envelope.Malformed.t>,
  fromCbor: Codec.Cbor.value => result<'envelope, Envelope.Malformed.t>,
  reasons: array<Envelope.Contracts.operation>,
  handle: (caller, 'envelope) => promise<answer>,
}

/** An interface, whatever its envelope, among the others a component answers. */
type route

let route: interface_<'envelope> => route

/** The trust a signed call is verified by, read at each request so a newer bundle takes effect. */
type trust = unit => Capability.Signed.trust

/** A request answered by the interfaces given, a signed call verified by the trust. */
let serve: (array<route>, ~trust: trust, request) => promise<response>
