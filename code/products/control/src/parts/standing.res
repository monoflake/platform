module Contracts = Envelope.Contracts

type reached = {address: string, tunnel: option<string>}

type t = {reach: unit => promise<result<reached, string>>}

let through = (~origin, ~token, fetch) => {
  let host: Driver.host = {
    // Called as a method, the global fetch would be given a receiver workerd refuses.
    reach: {origin: (~address as _, ~port as _) => origin, fetch: request => fetch(request)},
    address: "",
    port: 0,
    token,
  }
  {
    reach: async () =>
      switch await Driver.call(
        host,
        Contracts.Interface.Reaches.toJson({call: Open({}), capabilities: []}),
        Contracts.ReachOpened.fromJson,
      ) {
      | Ok({address, ?tunnel}) => Ok({address, tunnel: tunnel->Option.map(Web.fromUtf8)})
      | Error({reason, message}) => Error(`${reason}, ${message}`)
      },
  }
}
