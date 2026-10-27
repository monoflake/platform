/** Local D1 exposes workerd's row counter for each statement the state runs. */
type session

let open_: unit => promise<session> = %raw(`async () => {
  const {createRequire} = await import('node:module')
  const {readFileSync, readdirSync} = await import('node:fs')
  const require = createRequire(import.meta.url)
  const wrangler = createRequire(require.resolve('wrangler'))
  const {Miniflare, convertV4MiniflareOptions} = await import(wrangler.resolve('miniflare'))
  const model = await import('../../../../../model/rules/control_sql.res.mjs')
  const addresses = await import('../../src/parts/addresses.res.mjs')
  const source = readFileSync(new URL('../../src/parts/state.res', import.meta.url), 'utf8')
  const normalize = sql => sql.replace(/\s+/g, ' ').trim()
  const literal = name => source.match(new RegExp('let ' + name + ' = "([^"]+)"'))[1]
  const substitutions = {
    bindingColumns: literal('bindingColumns'), ranRow: literal('ranRow'),
    followingBound: model.fragments[3], unaddressed: model.fragments[1],
    'Int.toString(Addresses.count)': String(addresses.count),
    'following("organization")': model.fragments[0].replace('$' + '{table}', 'organization'),
    'appHeld("?1")': model.fragments[2].replaceAll('$' + '{app}', '?1'),
  }
  const expand = (text, kind) => text.replace(/\$\{([^}]*)\}/g, (_, expression) => {
    const value = expression === 'kind' ? kind : substitutions[expression]
    if (value === undefined) throw new Error('Unknown SQL interpolation ' + expression)
    return expand(value, kind)
  })
  const patterns = model.budgets.map(b => ({
    ...b,
    statements: ['binding', 'organization'].map(kind => normalize(expand(b.template, kind))),
  }))
  const runtime = new Miniflare(convertV4MiniflareOptions({
    cf: false,
    modules: true,
    script: 'export default {fetch() {return new Response("local")}}',
    compatibilityDate: '2026-10-19',
    d1Databases: ['STATE'],
  }))
  try {
    const db = await runtime.getD1Database('STATE')
    const migrations = new URL('../../migrations/', import.meta.url)
    for (const name of readdirSync(migrations).sort()) {
      const sql = readFileSync(new URL(name, migrations), 'utf8').replace(/--[^\n]*/g, '')
      for (const part of sql.split(';').filter(s => s.trim())) await db.prepare(part).run()
    }
    const seen = new Set()
    const measured = []
    const quantity = async name => {
      const tables = model.tables
      let count = 0
      for (const table of tables[name]) {
        count += (await db.prepare('SELECT COUNT(*) AS n FROM ' + table).first()).n
      }
      return count
    }
    const database = {prepare: sql => ({bind: (...values) => {
      const execute = async () => {
        const matches = patterns.filter(b => b.statements.includes(normalize(sql)))
        if (matches.length !== 1) throw new Error('SQL has no unique rows read budget ' + sql)
        const budget = matches[0]
        const n = await quantity(budget.quantity)
        const result = await db.prepare(sql).bind(...values).all()
        const limit = budget.fixed + budget.perRow * n
        const rows = result.meta.rows_read
        seen.add(budget.name + normalize(sql))
        measured.push({name: budget.name, quantity: n, rows, limit})
        if (!Number.isSafeInteger(rows) || rows < 0 || rows > limit) {
          throw new Error(budget.name + ' read ' + rows + ' rows with budget ' + limit +
            ' for ' + n + ' ' + budget.quantity)
        }
        return result.results
      }
      return {first: async () => (await execute())[0] ?? null,
        run: async () => {await execute()}}
    }})}
    return {database, db, runtime, seen, measured, patterns, sizes: model.fixtureSizes}
  } catch (error) {
    await runtime.dispose()
    throw error
  }
}`)

@get external database: session => Stores.database = "database"
@get external sizes: session => array<int> = "sizes"

let exec: (session, string) => promise<unit> = %raw(`async (session, sql) => {
  await session.db.prepare(sql).run()
}`)

let complete: session => unit = %raw(`session => {
  const missing = session.patterns.filter(b => b.statements.some(sql =>
    !session.seen.has(b.name + sql))).map(b => b.name)
  if (missing.length) throw new Error('SQL budgets without a measured fixture ' + missing.join(', '))
  console.log('SQL rows read ' + JSON.stringify(session.measured))
  session.seen.clear()
  session.measured.length = 0
}`)

let close: session => promise<unit> = %raw(`session => session.runtime.dispose()`)
