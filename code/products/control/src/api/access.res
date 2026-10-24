type caller = Operator | Host(float) | Organization(float) | Nobody

let bearer = header =>
  header->Option.flatMap(text =>
    switch text->String.trim->String.indexOf(" ") {
    | -1 => None
    | at =>
      let scheme = text->String.trim->String.slice(~start=0, ~end=at)
      let credential = text->String.trim->String.slice(~start=at + 1)->String.trim
      scheme->String.toLowerCase == "bearer" && credential != "" ? Some(credential) : None
    }
  )

let decimal = /^[1-9][0-9]{0,9}$/

let token = text =>
  switch text->String.split(".") {
  | [id, secret] if decimal->RegExp.test(id) =>
    switch (Float.fromString(id), Envelope.Base64url.decode(secret)) {
    | (Some(id), Some(bytes)) if bytes->TypedArray.length == 32 && id <= 4294967295. =>
      Some((id, bytes))
    | _ => None
    }
  | _ => None
  }

let tokenText = (id, secret) => `${Float.toString(id)}.${Envelope.Base64url.encode(secret)}`

let organizationToken = text =>
  text->String.startsWith("o") ? token(text->String.slice(~start=1)) : None

let organizationText = (id, secret) => `o${tokenText(id, secret)}`

let equal = (a, b) =>
  a->TypedArray.length == b->TypedArray.length && {
      let differ = ref(0)
      for i in 0 to a->TypedArray.length - 1 {
        let x = a->TypedArray.get(i)->Option.getOr(0)
        let y = b->TypedArray.get(i)->Option.getOr(0)
        differ := differ.contents->Int.bitwiseOr(x->Int.bitwiseXor(y))
      }
      differ.contents == 0
    }

let presented = async (kept, presented, called) =>
  switch await kept {
  | Some(kept) if equal(kept, presented) => called
  | Some(_) | None => Nobody
  }

let caller = async (header, ~operator, ~secret, ~organizationSecret) =>
  switch bearer(header) {
  | None => Nobody
  | Some(given) =>
    switch (token(given), organizationToken(given)) {
    | (Some((id, bytes)), _) => await presented(secret(id), bytes, Host(id))
    | (None, Some((id, bytes))) => await presented(organizationSecret(id), bytes, Organization(id))
    | (None, None) =>
      switch operator {
      | Some(kept) if kept != "" =>
        equal(await Web.sha256(Web.utf8(kept)), await Web.sha256(Web.utf8(given)))
          ? Operator
          : Nobody
      | Some(_) | None => Nobody
      }
    }
  }
