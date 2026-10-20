/**
 * A kind of record, named within its half, the half its truth is kept in, and the components that write it. A record a control
 * writes is configuration: the platform's control for what spans organizations, an organization's
 * for its products'; data is what lives inside what was opened, v7v3w. `check.res` refuses
 * configuration any other component writes, since the data plane runs on while a control is lost,
 * `docs/scope.md`, and a record of the platform's half any component of an organization's writes.
 */
type held = {
  half: Components.half,
  /** Its name within its half, as the shell of each of its rows writes it: one name may be a kind of
   * each half, one concept kept in both, as an extension, or two, as an organization. */
  kind: string,
  writes: array<string>,
  from: string,
}

let records: array<held> = [
  {half: #organization, kind: "bucket", writes: ["control(organization)"], from: "13ixj, v7v3w"},
  {half: #organization, kind: "database", writes: ["control(organization)"], from: "zn3u5, v7v3w"},
  {half: #organization, kind: "app", writes: ["control(organization)"], from: "49qyg, v7v3w"},
  {half: #organization, kind: "name", writes: ["control(organization)"], from: "vr5lw"},
  {half: #organization, kind: "member", writes: ["control(organization)"], from: "v7v3w"},
  {half: #organization, kind: "invitation", writes: ["control(organization)"], from: "v7v3w"},
  {half: #organization, kind: "organization", writes: ["control(organization)"], from: "v7v3w"},
  {half: #organization, kind: "tree", writes: ["control(organization)"], from: "v7v3w"},
  {half: #organization, kind: "scope", writes: ["control(organization)"], from: "vr5lw"},
  {half: #platform, kind: "extension", writes: ["control(platform)"], from: "v7v3w"},
  {half: #organization, kind: "extension", writes: ["control(organization)"], from: "v7v3w"},
  /* A share of what an extension holds, an item of its driver's list, vr5lw. */
  {half: #organization, kind: "capacity", writes: ["control(organization)"], from: "vr5lw"},
  {half: #platform, kind: "lease", writes: ["control(platform)"], from: "v7v3w"},
  {half: #platform, kind: "account", writes: ["control(platform)"], from: "v7v3w"},
  {half: #platform, kind: "organization", writes: ["control(platform)"], from: "v7v3w"},
  {half: #platform, kind: "label", writes: ["control(platform)"], from: "v7v3w, vr5lw"},
  {half: #platform, kind: "username", writes: ["control(platform)"], from: "v7v3w"},
  {half: #platform, kind: "sign-in", writes: ["control(platform)"], from: "v7v3w"},
  {half: #platform, kind: "membership", writes: ["control(platform)"], from: "v7v3w"},
  {half: #platform, kind: "domain", writes: ["control(platform)"], from: "vr5lw"},
  {half: #platform, kind: "certificate", writes: ["control(platform)"], from: "v7v3w"},
  {half: #platform, kind: "allowance", writes: ["control(platform)"], from: "vuanj"},
  {half: #organization, kind: "file", writes: ["storage"], from: "13ixj"},
  {half: #organization, kind: "row", writes: ["database"], from: "zn3u5"},
  {half: #organization, kind: "log", writes: ["tablet"], from: "vuanj"},
  {half: #organization, kind: "extent", writes: ["blob"], from: "b8f35"},
  {half: #organization, kind: "call", writes: ["compute"], from: "49qyg"},
  {half: #organization, kind: "message", writes: ["compute"], from: "49qyg"},
  {half: #organization, kind: "repeat", writes: ["compute"], from: "49qyg, v7v3w"},
]

/** The kind of record of a half by its name. */
let find = (half: Components.half, kind) =>
  records->Array.find(r => r.half == half && r.kind == kind)
