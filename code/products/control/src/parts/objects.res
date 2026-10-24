module Contracts = Envelope.Contracts

type t = {
  write: (string, Uint8Array.t) => promise<result<unit, string>>,
  read: string => promise<result<option<Uint8Array.t>, string>>,
  list: string => promise<result<array<string>, string>>,
}

let through = (~origin, ~token, fetch) => {
  let host: Driver.host = {
    // Called as a method, the global fetch would be given a receiver workerd refuses.
    reach: {origin: (~address as _, ~port as _) => origin, fetch: request => fetch(request)},
    address: "",
    port: 0,
    token,
  }
  let called = (call, decode) =>
    Driver.call(host, Contracts.Interface.Object.toJson({call, capabilities: []}), decode)
  let why = ({reason, message}: Driver.refused) => `${reason}, ${message}`
  let rec listed = async (prefix, after, names) =>
    switch await called(List({prefix, ?after}), Contracts.ObjectListed.fromJson) {
    | Error(refused) => Error(why(refused))
    | Ok({objects, ?next}) =>
      let names = names->Array.concat(objects->Array.map(o => o.name))
      switch next {
      | Some(after) => await listed(prefix, Some(after), names)
      | None => Ok(names)
      }
    }
  {
    write: async (name, content) =>
      (await called(Write({name, content}), Contracts.ObjectWritten.fromJson))
      ->Result.map(_ => ())
      ->Result.mapError(why),
    read: async name =>
      switch await called(Read({name: name}), Contracts.ObjectContent.fromJson) {
      | Ok({content}) => Ok(Some(content))
      | Error({reason: "not_found"}) => Ok(None)
      | Error(refused) => Error(why(refused))
      },
    list: prefix => listed(prefix, None, []),
  }
}
