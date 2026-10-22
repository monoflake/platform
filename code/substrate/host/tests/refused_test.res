/***
 * `Handed.call` refusing what would post past its deployment's address, and a driver's answer for
 * another deployment, each before anything is posted.
 */
open Node
module Contracts = Envelope.Contracts

let asked: Contracts.DeploymentRuns.t = App({id: 7.})

let address = "https://host.invalid/app-7"

/** A driver describing `asked` running at `address`, as `reports` names it, counting its asks. */
let driver = (~reports=asked, asks) => {
  Handed.describe: async _ => {
    asks := asks.contents + 1
    Contracts.Answer.Success({
      runs: reports,
      version: Uint8Array.fromLength(32),
      state: Running({address, runtime: Workers, isolation: [Isolate]}),
    })
  },
}

let request: Handed.request = {contentType: None, accept: None, body: utf8("{}")}

let answered: Handed.response = {status: 200, contentType: None, body: utf8("{}")}

/** A call made, what it came to, its URLs posted and how often its driver was asked. */
let made = async (~reports=?, export, key) => {
  let asks = ref(0)
  let posted = []
  let post = async (url, _) => {
    posted->Array.push(url)
    Ok(answered)
  }
  let answer = await Handed.call(
    driver(~reports?, asks),
    ~post,
    {runs: asked, export, key, request},
  )
  let answer = switch answer {
  | Refused({failure, reason}) => Handed.Refused({failure, reason, message: ""})
  | Answered(_) => answer
  }
  (answer, posted, asks.contents)
}

let malformed = Handed.Refused({failure: Rejected, reason: "malformed", message: ""})

// Each once reached past the address, `..` to `/echo` and the export to another deployment.
[
  ("a key of ..", "echo", Some("..")),
  ("a key of .", "echo", Some(".")),
  ("an export climbing to another deployment", "../app-8/echo", None),
  ("an export adding a query and a fragment", "echo?x=1#", None),
  ("an export of two segments", "echo/again", None),
  ("an export of an interface of an interface", "a.b.echo", None),
  ("an export that is no kebab-case label", "Echo-it", None),
  ("an empty export", "", None),
]->Array.forEach(((description, export, key)) =>
  test(`${description} is malformed, its driver never asked`, async () => {
    let (answer, posted, asks) = await made(export, key)
    deepEqual((answer, posted, asks), (malformed, [], 0), ~message=description)
  })
)

test("an export of an interface is posted under the address alone", async () => {
  let (answer, posted, _) = await made("store.get-it", Some("a"))
  deepEqual((answer, posted), (Answered(answered), [`${address}/a/store.get-it`]))
})

// A driver describing another deployment once had the call posted to that one's address.
test("an answer for another deployment is a fault, nothing posted", async () => {
  let (answer, posted, _) = await made(~reports=App({id: 8.}), "echo", None)
  deepEqual(
    (answer, posted),
    (Handed.Refused({failure: Unknown, reason: "fault", message: ""}), []),
  )
})
