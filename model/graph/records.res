/**
 * A kind of record, the half its truth is kept in and the components that write it, v7v3w.
 * Configuration is written by a control alone, `docs/scope.md`.
 */
type held = {
  half: Components.half,
  /**
   * Its name within its half, as each row's shell writes it, which may name one kind in each half.
   */
  kind: string,
  writes: array<string>,
  from: string,
  /** Whether its content is the platform half's own, so this model knows it by its id alone. */
  elsewhere?: bool,
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
  {half: #organization, kind: "extension", writes: ["control(organization)"], from: "v7v3w"},
  /* A share of what an extension holds, an item of its driver's list, vr5lw. */
  {half: #organization, kind: "capacity", writes: ["control(organization)"], from: "vr5lw"},
  {half: #organization, kind: "component", writes: ["control(organization)"], from: "nrs5v"},
  {half: #platform, kind: "account", writes: ["authority"], from: "v7v3w", elsewhere: true},
  {half: #platform, kind: "organization", writes: ["authority"], from: "v7v3w"},
  /*
   * A footing's own tables, b8f35. A tablet's rows and an app's database are their own schema, so
   * neither is a kind here.
   */
  // The footing advances it in the batch of every write it applies, 8yl4b.
  {
    half: #organization,
    kind: "generation",
    writes: ["footing(organization)"],
    from: "b8f35, v7v3w, 8yl4b",
  },
  {half: #organization, kind: "store", writes: ["control(organization)"], from: "b8f35"},
  {half: #organization, kind: "content", writes: ["blob"], from: "b8f35"},
  {half: #organization, kind: "piece", writes: ["blob"], from: "b8f35"},
  {half: #organization, kind: "parcel", writes: ["blob", "extent"], from: "b8f35, 8yl4b"},
  {half: #organization, kind: "journal", writes: ["blob", "extent"], from: "b8f35, 8yl4b"},
  {half: #organization, kind: "writer", writes: ["tablet"], from: "b8f35, vuanj"},
  /*
   * A clock's lock, who holds a name and until when, compute's alone since the executor stores
   * nothing, vuanj.
   */
  {half: #organization, kind: "lease", writes: ["compute"], from: "b8f35, v7v3w"},
]

/** Every kind with each writer named as the whole graph names it. */
let records: array<held> =
  own
  ->Array.concat(Fill.part("records")->Option.getOr([]))
  ->Array.map(r => {...r, writes: r.writes->Array.map(Components.named)})

/** The kind of record of a half by its name. */
let find = (half: Components.half, kind) =>
  records->Array.find(r => r.half == half && r.kind == kind)

/** The kind as this model declares it, a role's name kept, as contracts.json publishes it. */
let declared = (half: Components.half, kind) =>
  own->Array.find(r => r.half == half && r.kind == kind)
