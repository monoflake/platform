---
name: "A Binding's Token"
title: "What a binding's token is as text, how a driver takes it and keeps it, and how a control presents it"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC vr5lw decides who makes a binding's token and who keeps it: its control makes it, the host's
holder enters it in the driver's own management -- on a machine, a file `monoflake.driver.bindings`
names -- and the driver shows it once and keeps it salted and hashed, never the token itself; every
management call carries it. What the token is, as bytes and as text, how it is salted and hashed,
and how a call carries it are written nowhere, and the machine driver's management cannot take its
first binding without them.

## Decided

Decided by the author on 2026-10-21, from the agent's proposal, with two changes of the author's:
the text names no vendor, and the hash takes no salt. vr5lw's "salted and hashed" is amended to
this.

1. **A token is the binding's id and 32 random bytes, written as one text, `<id>.<secret>`**, the
   id the binding's `capacity` space's integer in decimal and the secret base64url unpadded, RFC
   fhg6w. It carries no prefix naming the platform: a vendor's name is written in first-party code
   only where it is data, and the token's form is neutral. The id lets a driver find the binding a
   token is for without trying every hash.
2. **A driver keeps the id and `BLAKE3(secret)`, with no salt**, as vr5lw keeps an item's
   credential: the secret is 32 random bytes, so a salt adds nothing a guess could be slowed by, and
   the driver keeps no state for one. No password-hashing cost is paid on any call.
3. **A call carries it as `Authorization: Bearer <token>`**, over the driver's HTTPS, or over the
   tailnet where the machine is reached only there; a token absent or not matching is `denied`, RFC
   ge55b, the same for a binding that does not exist, so a caller learns nothing of which.
4. **A file holds one token and nothing else**, so a secret manager writes it whole; the driver
   reads each file at start and on a signal, takes a token it has not seen, and forgets a binding
   whose file is gone only when its control has ended it, `end`, so a file lost never ends what runs.
5. **Replacing a token is a second one beside the first**, as an item's credential is, vr5lw: the
   driver holds both until the control's next list names only the new one, by its hash.

## Open

Whether the token also names where its control is reached, so a driver could report to it rather
than wait to be asked, is left until a driver needs to call its control at all; today every call
goes from the control to the driver.
