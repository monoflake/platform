/** The SQL literals in state all belong to the measured inventory. */
open Base

let normalize = text => text->String.replaceRegExp(/\s+/g, " ")->String.trim

let inventory = source => {
  let tokens = /("(?:\\.|[^"\\])*"|`[^`]*`)/g
  let found = []
  let rec next = () =>
    switch tokens->RegExp.exec(source) {
    | None => ()
    | Some(m) =>
      m
      ->RegExp.Result.matches
      ->Array.get(0)
      ->Option.flatMap(x => x)
      ->Option.forEach(token => {
        let text = token->String.slice(~start=1, ~end=token->String.length - 1)->normalize
        if (
          /^(SELECT|WITH|UPDATE|INSERT|DELETE|REPLACE|PRAGMA|EXPLAIN|CREATE|ALTER|DROP|\$\{|\(SELECT|\(EXISTS)/i->RegExp.test(
            text,
          )
        ) {
          found->Array.push(text)
        }
      })
      next()
    }
  next()
  found
}

let missing = source => {
  let known = Array.concat(Control_sql.fragments, Control_sql.budgets->Array.map(b => b.template))
  inventory(source)->Array.filter(sql => !(known->Array.includes(sql)))
}

let run = () => {
  let source = readFileSync(urlIn("code/products/control/src/parts/state.res", root))
  let names = Control_sql.budgets->Array.map(b => b.name)
  let found = missing(source)->Array.map(sql => `state SQL has no rows read budget: ${sql}`)
  let rule = Control_sql.rule
  [rule["doc"]->String.split("#")->Array.getUnsafe(0), rule["heldBy"]]->Array.forEach(path =>
    if !existsSync(urlIn(path, root)) {
      found->Array.push(`${rule["name"]} names a missing file ${path}`)
    }
  )
  Control_sql.budgets->Array.forEach(b => {
    if names->Array.filter(n => n == b.name)->Array.length != 1 {
      found->Array.push(`duplicate SQL budget ${b.name}`)
    }
    if b.fixed < 0 || b.perRow < 0 {
      found->Array.push(`negative SQL budget ${b.name}`)
    }
  })
  dimension(
    "SQL cost",
    rule["says"],
    found,
    ~notes=[`${rule["name"]}, held by ${rule["heldBy"]}`],
    (),
  )
}
