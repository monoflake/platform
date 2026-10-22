/**
 * Each written block's state by its package's name, `docs/code.md`. A block in work fails nothing,
 * and one written but not named here is refused.
 */
type state = InWork | Accepted

let blocks: dict<state> = dict{
  "codec": Accepted,
  "compat": Accepted,
  "envelope": Accepted,
  "envelope-generator": Accepted,
  "capability": Accepted,
  "keys": Accepted,
  "layout": Accepted,
  "placement": Accepted,
  "runner": Accepted,
  "serve": Accepted,
  "vocabulary": InWork,
  "wit": InWork,
}
