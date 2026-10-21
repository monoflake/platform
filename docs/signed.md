# Signed records

How `capability*` verifies every signed record, RFC b8f35, which
`code/libs/capability/src/signed.resi` implements. Each is a COSE Sign1 of RFC 9052, tagged 18, by
Ed25519, its protected header `alg` -19, `kid` the first 16 bytes of the BLAKE3 of the signer's
public key, and `typ` its kind's; its payload its content's CBOR, read as
`Codec.Cbor.decodeDeterministic` reads. A signature is verified strictly, by RFC 8032 and never
ZIP-215's encodings, so every runtime answers one signature alike. A signer is found by its `kid`
among the certificates given, a call's `kcwt` among them, or as the root, and every certificate
above it is verified so, to the root. Nothing here reads a clock: a time is the caller's, in
seconds.

## Who signs what

Nothing else is taken.

| Signer         | Signs                                                                                                      |
| -------------- | ---------------------------------------------------------------------------------------------------------- |
| the root       | a certificate of `intermediate`                                                                            |
| `intermediate` | a certificate of `authority`                                                                               |
| `authority`    | a certificate of `organization`, `issuer`, `bundle` or `account`; an authority's record; a directory's row |
| `organization` | a certificate of `component`, with its `sub`; a call                                                       |
| `issuer`       | a capability                                                                                               |
| `bundle`       | a bundle                                                                                                   |
| `account`      | an account credential                                                                                      |
| `component`    | a call                                                                                                     |

A signer holding a scope signs only what holds the same: a certificate's and a capability's `scope`,
a bundle's. What carries `iat` and `exp` -- a certificate, a capability, an account credential -- is
refused from `exp` on, and while its `iat` is more than 60 seconds ahead, each certificate of a
chain as much as what it signs.

## How a record is read

- **The whole record is deterministic CBOR**, `Codec.Cbor.decodeDeterministic`, its protected header
  and its payload as well, since a record is kept and compared by its bytes, and one record has one
  form.
- **The protected header holds `alg`, `kid` and `typ` alone**, `kid` of 16 bytes and `typ` text; the
  unprotected header is empty but for a call's, which holds `kcwt`, 13, a byte string, alone.
  Anything else is `Malformed`.
- **A content is read as far as verifying reads it**: a map; `iat` and `exp` integers of 0 to
  2^53 - 1; a scope an integer; a role a known code; `cnf` an Ed25519 `COSE_Key`, `x` of 32 bytes;
  `sub` text, which a component's certificate holds; a bundle's scope at key 2; a capability's
  rights not empty. The rest of each content is its reader's, by envelope.
- **Every certificate matching a `kid` is tried**, a call's `kcwt` first, then those given in their
  order, then the root, since a key renewed is certified twice while both certificates live: the
  first that verifies signs, and where none does, the refusal is the first candidate's. A
  certificate given that does not read as one is no candidate.
- **A signer holding a scope signs nothing that holds none.**
