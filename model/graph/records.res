/**
 * A kind of record, named within its half, the half its truth is kept in, and the components that
 * write it. A record a control writes is configuration: the platform's control for what spans
 * organizations, an organization's for its products'; data is what lives inside what was opened,
 * v7v3w. `check.res` refuses configuration any other component writes, since the data plane runs on
 * while a control is lost, `docs/scope.md`, and a record of the platform's half any component of an
 * organization's writes.
 */
type held = {
  half: Components.half,
  /**
   * Its name within its half, as the shell of each of its rows writes it: one name may be a kind of
   * each half, one concept kept in both, as an extension, or two, as an organization.
   */
  kind: string,
  writes: array<string>,
  from: string,
}

let own: array<held> = [
  {half: #organization, kind: "bucket", writes: ["control(organization)"], from: "13ixj, v7v3w"},
  {half: #organization, kind: "database", writes: ["control(organization)"], from: "zn3u5, v7v3w"},
  {half: #organization, kind: "app", writes: ["control(organization)"], from: "49qyg, v7v3w"},
  {half: #organization, kind: "name", writes: ["control(organization)"], from: "vr5lw"},
  {half: #organization, kind: "member", writes: ["control(organization)"], from: "v7v3w"},
  {half: #organization, kind: "invitation", writes: ["control(organization)"], from: "v7v3w"},
  {half: #organization, kind: "organization", writes: ["control(organization)"], from: "v7v3w"},
  {half: #organization, kind: "tree", writes: ["control(organization)"], from: "v7v3w"},
  {half: #organization, kind: "scope", writes: ["control(organization)"], from: "vr5lw"},
  {half: #platform, kind: "extension", writes: ["authority"], from: "v7v3w"},
  {half: #organization, kind: "extension", writes: ["control(organization)"], from: "v7v3w"},
  /* A share of what an extension holds, an item of its driver's list, vr5lw. */
  {half: #organization, kind: "capacity", writes: ["control(organization)"], from: "vr5lw"},
  {half: #platform, kind: "loan", writes: ["authority"], from: "v7v3w"},
  {half: #platform, kind: "account", writes: ["authority"], from: "v7v3w"},
  {half: #platform, kind: "organization", writes: ["authority"], from: "v7v3w"},
  {half: #platform, kind: "label", writes: ["authority"], from: "v7v3w, vr5lw"},
  {half: #platform, kind: "username", writes: ["authority"], from: "v7v3w"},
  {half: #platform, kind: "sign-in", writes: ["authority"], from: "v7v3w"},
  {half: #platform, kind: "membership", writes: ["authority"], from: "v7v3w"},
  {half: #platform, kind: "domain", writes: ["authority"], from: "vr5lw"},
  /* A footing's own tables, b8f35, each its keys and one versioned record; a product's tablet
   * holds rows of its own schema, a migration's to change, and an app's database its app's, so
   * neither is a kind of record here. */
  {
    half: #organization,
    kind: "generation",
    writes: ["control(organization)"],
    from: "b8f35, v7v3w",
  },
  {half: #organization, kind: "store", writes: ["control(organization)"], from: "b8f35"},
  {half: #organization, kind: "content", writes: ["blob"], from: "b8f35"},
  {half: #organization, kind: "piece", writes: ["blob"], from: "b8f35"},
  {half: #organization, kind: "parcel", writes: ["blob"], from: "b8f35"},
  {half: #organization, kind: "journal", writes: ["blob"], from: "b8f35"},
  {half: #organization, kind: "writer", writes: ["tablet"], from: "b8f35, vuanj"},
  /* A clock's lock: who holds a name, and until when, v7v3w, vr5lw. */
  {half: #organization, kind: "lease", writes: ["compute", "executor"], from: "b8f35, v7v3w"},
]

/** Every kind, each writer named as the whole graph names it: a filled role by its filler. */
let records: array<held> = own->Array.map(r => {
  ...r,
  writes: r.writes->Array.map(Components.named),
})

/** The kind of record of a half by its name. */
let find = (half: Components.half, kind) =>
  records->Array.find(r => r.half == half && r.kind == kind)

/** The kind as this model declares it, a role's name kept: what contracts.json publishes. */
let declared = (half: Components.half, kind) =>
  own->Array.find(r => r.half == half && r.kind == kind)
