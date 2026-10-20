/**
 * A kind of record, the half its truth is kept in, and the components that write it. A record a control
 * writes is configuration: the platform's control for what spans organizations, an organization's
 * for its products'; data is what lives inside what was opened, v7v3w. `check.res` refuses
 * configuration any other component writes, since the data plane runs on while a control is lost,
 * `docs/scope.md`, and a record of the platform's half any component of an organization's writes.
 */
type held = {
  half: Components.half,
  writes: array<string>,
  from: string,
}

let records: dict<held> = dict{
  "bucket": {half: #organization, writes: ["control(organization)"], from: "13ixj, v7v3w"},
  "database": {half: #organization, writes: ["control(organization)"], from: "zn3u5, v7v3w"},
  "app": {half: #organization, writes: ["control(organization)"], from: "49qyg, v7v3w"},
  "name": {half: #organization, writes: ["control(organization)"], from: "vr5lw"},
  "member": {half: #organization, writes: ["control(organization)"], from: "v7v3w"},
  "invitation": {half: #organization, writes: ["control(organization)"], from: "v7v3w"},
  "organization": {half: #organization, writes: ["control(organization)"], from: "v7v3w"},
  "tree": {half: #organization, writes: ["control(organization)"], from: "v7v3w"},
  "scope": {half: #organization, writes: ["control(organization)"], from: "vr5lw"},
  "extension(platform)": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "extension(organization)": {
    half: #organization,
    writes: ["control(organization)"],
    from: "v7v3w",
  },
  /* A share of what an extension holds, an item of its driver's list, vr5lw. */
  "capacity": {half: #organization, writes: ["control(organization)"], from: "vr5lw"},
  "lease": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "account": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "organization(platform)": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "label": {half: #platform, writes: ["control(platform)"], from: "v7v3w, vr5lw"},
  "username": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "sign-in": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "membership": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "domain": {half: #platform, writes: ["control(platform)"], from: "vr5lw"},
  "certificate": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "allowance": {half: #platform, writes: ["control(platform)"], from: "vuanj"},
  "file": {half: #organization, writes: ["storage"], from: "13ixj"},
  "row": {half: #organization, writes: ["database"], from: "zn3u5"},
  "log": {half: #organization, writes: ["tablet"], from: "vuanj"},
  "extent": {half: #organization, writes: ["blob"], from: "b8f35"},
  "call": {half: #organization, writes: ["compute"], from: "49qyg"},
  "message": {half: #organization, writes: ["compute"], from: "49qyg"},
  "repeat": {half: #organization, writes: ["compute"], from: "49qyg, v7v3w"},
}
