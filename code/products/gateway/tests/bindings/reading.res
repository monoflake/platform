module Stores = ControlOrganization.Stores
module State = ControlOrganization.State
module Web = ControlOrganization.Web

let offered: 'a => array<string> = %raw(`value => Object.keys(value).sort()`)

let guarded: (Stores.database, array<string>) => Stores.database = %raw(`(database, seen) => ({
  prepare: sql => {
    if (!sql.startsWith('SELECT ')) throw new Error('gateway attempted a write ' + sql)
    seen.push(sql)
    const statement = database.prepare(sql)
    return {bind: (...values) => ({
      first: () => statement.bind(...values).first(),
      run: () => {throw new Error('gateway offered a write')},
    })}
  },
})`)

let fetcher: Web.fetch => Web.fetcher = %raw(`fetch => ({fetch})`)
