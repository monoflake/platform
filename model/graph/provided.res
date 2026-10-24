/**
 * What each block here provides beside the name it is named for, and the edges it adds where the
 * design has none, RFC s42ex. A block not listed provides its own name alone.
 */
/** A design edge of a name the block provides, and the contract it carries as built instead. */
type carried = {from: string, to_: string, contract: array<string>}

type block = {
  provides: array<string>,
  extra: array<Components.edge>,
  carries?: array<carried>,
}

/** The platform beneath, reached through its products at layer 0 alone, RFC 94y0d. */
let beneath: Components.component = {
  layer: Components.vendor,
  kind: #ground,
  answers: ["storage", "database", "wit"],
  edges: [],
  uses: [],
}

let blocks: dict<block> = dict{
  "control(organization)": {
    // Its releases stand in for the deployer, and its bindings' tunnels and network for the roster.
    provides: ["authority", "?entry", "?builder", "?deployer", "?roster"],
    // Its own tables, read and written by SQL, stand where the footing's contract is drawn.
    carries: [{from: "control(organization)", to_: "footing(organization)", contract: ["?tables"]}],
    extra: [
      {
        ...Components.e(
          "control(organization)",
          #serve,
          Components.hard,
          "relays a request to a host through the control it stands on, in place of RFC 94y0d's export and import",
          ~contract=["?relay"],
        ),
        beneath: true,
      },
      {
        ...Components.e(
          "control(organization)",
          #serve,
          Components.hard,
          "keeps its records and artifacts as objects passed through the control it stands on, in place of RFC 94y0d's export and import",
          ~contract=["object"],
        ),
        beneath: true,
      },
      {
        ...Components.e(
          "control(organization)",
          #deploy,
          Components.hard,
          "opens a reach of the control it stands on for a host it binds, in place of RFC 94y0d's export and import",
          ~contract=["reaches"],
        ),
        beneath: true,
      },
    ],
  },
}

/** What a sibling repository's blocks provide, given in the fill, its code written there. */
let elsewhere: dict<block> = Fill.part(Fill.provided)->Option.getOr(dict{})

/** Every block's declaration, this repository's and its siblings'. */
let all = Dict.fromArray(Array.concat(blocks->Dict.toArray, elsewhere->Dict.toArray))

/**
 * What fills a name in one deployment, RFC vgvx6, a block by its main name, a vendor's resource, or
 * a user's workload, whose code the model never holds.
 */
type filler =
  | Block(string)
  | Vendor({vendor: string, resource: string})
  | Workload(string)

/** One deployment, each name with what fills it as it runs now, and the targets bound to it. */
type deployed = {fills: array<(string, filler)>, targets: array<string>}

/** Each deployment by its name, given in the fill; none where no fill gives them. */
let deployments: dict<deployed> = Fill.part(Fill.deployments)->Option.getOr(dict{})
