/**
 * What each block here provides beside the name it is named for, and the edges it adds where the
 * design has none, RFC s42ex. A block not listed provides its own name alone.
 */
type block = {
  provides: array<string>,
  extra: array<Components.edge>,
}

let blocks: dict<block> = dict{
  "control(organization)": {
    provides: ["authority", "?entry", "?builder"],
    extra: [
      {
        ...Components.e(
          "control(organization)",
          #serve,
          Components.hard,
          "relays a request to a host and keeps its records as objects through the control it stands on, in place of RFC 94y0d's export and import",
          ~contract=["?relay"],
        ),
        beneath: true,
      },
    ],
  },
}
