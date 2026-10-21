/***
 * A component's interfaces served, alike on a Worker and on workerd, RFC vr5lw and RFC ge55b: a
 * request `POST /{interface}/{operation}` read as a `call` of an interface the component answers,
 * in the form its `Content-Type` names; a call a certificate made, a COSE Sign1 under tag 18 whose
 * payload is the call's CBOR, verified by `capability*` to the trust given, its signer handed on; the
 * call handed to its interface's handler; and the handler's output or error written back as an
 * `answer`, in the form `Accept` names, CBOR where it names neither, its HTTP status the error's,
 * `400` for `rejected` but `403` for `denied` and `404` for `not_found`, `503` for `unavailable`
 * but `429` for `rate_limited`, the caller's own pace rather than the implementation's load,
 * `500` for `unknown`, `200` for an output. A request read as no call is `malformed`; a call whose
 * signature does not verify is `denied`; a handler that throws is `fault`. Which calls must be
 * signed, and by whom, is each handler's to say, answering `denied`. What a component reads of its
 * bundle and its footing is its own. The model's interface, `docs/code.md`.
 */

/** A request as both runtimes give it: its method, its path, its two headers, its body. */
type request = {
  method_: string,
  path: string,
  contentType: option<string>,
  accept: option<string>,
  body: Uint8Array.t,
}

/** A response: its HTTP status, its `Content-Type`, its body. */
type response = {status: int, contentType: string, body: Uint8Array.t}

/** Who made a call: a certificate's signer, verified, or nobody, where it came unsigned. */
type caller = Signed(Capability.Signed.signer) | Unsigned

/** What a handler answers: its output, written in either form, or an error. */
type output

/** An output, by its type's writers, as each of `Envelope.Contracts`' types holds them. */
let output: ('a, ~toJson: 'a => JSON.t, ~toCbor: 'a => Codec.Cbor.value) => output

/**
 * What a handler answers: an output, or an error by its reason, its message the reason's own
 * unless one is given, its failure the reason's as its operation or every operation declares it.
 */
type answer = Output(output) | Refused({reason: string, message: option<string>})

/**
 * An interface a component answers: its name, how its `envelope` is read in each form, as
 * `Envelope.Contracts.Interface.*.envelope` reads, the reasons its operations declare, and its
 * handler.
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
