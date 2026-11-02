type file = {name: string, bytes: Uint8Array.t}

let tar: array<file> => Uint8Array.t = %raw(`files => {
  const result = new Uint8Array(files.reduce((n, f) => n + 512 + Math.ceil(f.bytes.length / 512) * 512, 1024))
  const encoder = new TextEncoder()
  let at = 0
  for (const f of files) {
    const header = result.subarray(at, at + 512)
    const put = (at, text) => header.set(encoder.encode(text), at)
    const octal = (n, width) => n.toString(8).padStart(width - 1, '0') + String.fromCharCode(0)
    put(0, f.name)
    put(100, octal(420, 8))
    put(108, octal(0, 8))
    put(116, octal(0, 8))
    put(124, octal(f.bytes.length, 12))
    put(136, octal(0, 12))
    put(148, '        ')
    put(156, '0')
    put(257, 'ustar' + String.fromCharCode(0) + '00')
    put(148, header.reduce((sum, b) => sum + b, 0).toString(8).padStart(6, '0') + String.fromCharCode(0) + ' ')
    result.set(f.bytes, at + 512)
    at += 512 + Math.ceil(f.bytes.length / 512) * 512
  }
  return result
}`)

type measured

let measuring: Cost.session => measured = %raw(`session => {
  const seen = new Map()
  const record = (sql, result) => {
    if (!/deployment_grant|grant_staging|grant_head/.test(sql)) return
    const rows = result.meta?.rows_read
    if (!Number.isSafeInteger(rows) || rows < 0) throw new Error('missing D1 rows_read')
    seen.set(sql, Math.max(rows, seen.get(sql) ?? 0))
  }
  return {seen, database: {
    prepare: sql => ({bind: (...values) => {
      const prepared = session.db.prepare(sql).bind(...values)
      const all = async () => {
        const result = await prepared.all()
        record(sql, result)
        return result.results
      }
      return {prepared, sql, all: async () => ({results: await all()}), first: async () => (await all())[0] ?? null,
        run: async () => {await all()}}
    }}),
    batch: async statements => {
      const results = await session.db.batch(statements.map(s => s.prepared))
      statements.forEach((s, i) => record(s.sql, results[i]))
    },
  }}
}`)

@get external database: measured => Stores.database = "database"
let maxima: measured => array<(string, int)> = %raw(`measurement => [...measurement.seen]`)

type overlapRow = {
  control: int,
  lowest: int,
  @as("driver_lowest") driverLowest: int,
  @as("driver_highest") driverHighest: int,
  overlaps: bool,
}
external overlapRows: JSON.t => array<overlapRow> = "%identity"

/** What `console.error` is given while the work runs, and the work's own value. */
let logged = (work: unit => promise<'a>): promise<('a, array<string>)> =>
  %raw(`async work => {
  const lines = []
  const kept = console.error
  console.error = line => {lines.push(String(line))}
  try {
    return [await work(), lines]
  } finally {
    console.error = kept
  }
}`)(work)

/** The deadlines asked while the work runs, and the work's own value. */
let deadlines = (work: unit => promise<'a>): promise<('a, array<int>)> =>
  %raw(`async work => {
  const asked = []
  const kept = AbortSignal.timeout
  AbortSignal.timeout = ms => {
    asked.push(ms)
    return kept.call(AbortSignal, ms)
  }
  try {
    return [await work(), asked]
  } finally {
    AbortSignal.timeout = kept
  }
}`)(work)
