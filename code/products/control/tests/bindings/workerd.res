/*** What workerd gives a Worker, stood in for where node gives nothing alike. */

/** A binding as workerd gives one, every name read on it a function, `fetch` answering. */
let everyName: unit => Stores.env = %raw(`() => ({
  HOSTS: new Proxy({}, {
    get: (_, name) => name === "fetch" ? async () => new Response("through") : () => undefined,
  }),
})`)
