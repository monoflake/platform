open Node
open Called

let operations = () => [
  organizations(Open({label: "grant-gate"})),
  bindings(Open({organization: 1.})),
  bindings(Bind({reach: Tunnel})),
  reaches(Open({})),
  releases(Put({form: Modules, artifact})),
  releases(Deploy({binding: 1., app: 1., release: Uint8Array.fromLength(32)})),
  releases(Describe({app: 1.})),
  releases(Forget({app: 1.})),
  releases(Retire({app: 1.})),
]

test("grant bearer proofs are refused by every existing control operation", async () => {
  let stood = stand()
  let secret = Uint8Array.fromLength(32)
  let checked = ["deploy", "health", "invalid"]->Array.map(async id => {
    let given = `dg1.synthetic-${id}.${Envelope.Base64url.encode(secret)}`
    let caller = await Access.caller(
      Some(`Bearer ${given}`),
      ~operator=Some(given),
      ~secret=async _ => Some(secret),
      ~organizationSecret=async _ => Some(secret),
    )
    let refused = operations()->Array.map(
      async operation => {
        let (status, answer) = await called(stood, caller, operation)
        deepEqual((status, answer->reason), (403, Some("denied")))
      },
    )
    ignore(await Promise.all(refused))
  })
  ignore(await Promise.all(checked))
  deepEqual(stood.artifacts->Dict.keysToArray, [])
  deepEqual(await stood.parts.state.hasOrganization(1.), false)
})
