/*** Organization crossings stop at the public export, RFC nge39. */
open Testing

let column = (~organization=?, ~exports=[], fills): Provided.deployed => {
  fills,
  targets: [],
  ?organization,
  exports,
}

let capability: Provided.exported = {
  name: "database",
  app: "service",
  endpoint: "https://data.example/database",
  contracts: ["database"],
}

let source = (~exports=[capability], fills) => column(~organization="supplier", ~exports, fills)
let supplier = source([("service", Workload("database-service"))])
let consumer = fills => column(~organization="customer", fills)
let imported = [("database", Provided.Import({deployment: "supplier", name: "database"}))]

let messages = deployments => Imports.check(~deployments, ()).violations->Array.map(f => f.text)

test("another organization's public export fills a deployment name", () => {
  let d = consumer(imported)
  deepEqual(messages(dict{"customer": d, "supplier": supplier}), [])
  deepEqual(Realized.filledApart(d), [("database", "database, an export imported from supplier")])
  deepEqual(Realized.filledBeneath(d), [])
  deepEqual(Realized.runningIn(d).under, Some(Nothing))
  deepEqual(
    Derivations.providedLines(
      ~deployments=dict{"supplier": supplier},
      "customer",
      Derivations.viewOf("customer", d),
      d,
    )->Array.filter(l => l->String.startsWith("database:")),
    ["database: database, an export imported from supplier"],
  )
})

test("an internal name cannot reach another organization, even one exporting it", () => {
  deepEqual(
    messages(
      dict{
        "customer": consumer([("database", Beneath({deployment: "supplier", name: "service"}))]),
        "supplier": supplier,
      },
    ),
    [
      "customer: internal path database -> service in supplier crosses organizations; use an import of an export, RFC nge39",
    ],
  )
})

test("an import cannot name an internal app that the other organization does not export", () => {
  deepEqual(
    messages(
      dict{
        "customer": consumer([("database", Import({deployment: "supplier", name: "service"}))]),
        "supplier": supplier,
      },
    ),
    ["customer: import database names service, which supplier does not export once, RFC nge39"],
  )
})

test("a path through a deployment in the same organization still refuses its crossing", () => {
  deepEqual(
    messages(
      dict{
        "customer": consumer([("database", Beneath({deployment: "middle", name: "database"}))]),
        "middle": consumer([("database", Beneath({deployment: "supplier", name: "service"}))]),
        "supplier": supplier,
      },
    ),
    [
      "middle: internal path database -> service in supplier crosses organizations; use an import of an export, RFC nge39",
    ],
  )
})

test("an import must answer the filled name's contracts", () => {
  deepEqual(
    messages(
      dict{
        "customer": consumer(imported),
        "supplier": source(~exports=[{...capability, contracts: ["storage"]}], supplier.fills),
      },
    ),
    ["customer: import database leaves database unanswered, RFC nge39"],
  )
})

test("a non HTTPS endpoint or a borrowed app cannot become an export", () => {
  [
    "http://data.example/database",
    "https://",
    "https://data.example/has space",
  ]->Array.forEach(endpoint => {
    let found = messages(
      dict{
        "customer": consumer(imported),
        "supplier": source(~exports=[{...capability, endpoint}], supplier.fills),
      },
    )
    deepEqual(found->Array.length, 2)
    deepEqual(
      found->Array.includes(
        "supplier: export database requires a public HTTPS endpoint, RFC nge39",
      ),
      true,
    )
  })
  deepEqual(
    messages(
      dict{
        "supplier": source([("service", Import({deployment: "elsewhere", name: "database"}))]),
      },
    )->Array.includes("supplier: export database names service, no app of its own, RFC nge39"),
    true,
  )
})

test("imports require two named organizations and exactly one export", () => {
  deepEqual(
    messages(dict{"customer": column(imported), "supplier": supplier}),
    ["customer: import database requires both organizations, RFC nge39"],
  )
  deepEqual(
    messages(
      dict{"customer": consumer(imported), "supplier": {...supplier, organization: "customer"}},
    ),
    ["customer: import database requires another organization, RFC nge39"],
  )
  deepEqual(
    messages(dict{"customer": consumer(imported)}),
    ["customer: import database names supplier, no deployment, RFC nge39"],
  )
  deepEqual(
    messages(
      dict{
        "customer": consumer(imported),
        "supplier": source(~exports=[capability, capability], supplier.fills),
      },
    )->Array.length,
    3,
  )
})

test("legacy columns and internal paths within one organization keep their meaning", () => {
  let fills = [("database", Provided.Beneath({deployment: "other", name: "database"}))]
  deepEqual(messages(dict{"own": column(fills), "other": column([])}), [])
  deepEqual(messages(dict{"own": consumer(fills), "other": consumer([])}), [])
  deepEqual(messages(dict{"own": consumer(fills), "other": column([])})->Array.length, 1)
})
