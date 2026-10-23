/**
 * Each written block's state by its package's name, `docs/code.md`. A block in work fails nothing,
 * and one written but not named here is refused.
 */
type state = InWork | Accepted

let blocks: dict<state> = dict{
  "codec": Accepted,
  "compat": Accepted,
  "conform": Accepted,
  "deploy": Accepted,
  "envelope": Accepted,
  "envelope-generator": Accepted,
  "extensions": Accepted,
  "host": Accepted,
  "capability": Accepted,
  "keys": Accepted,
  "layout": Accepted,
  "lose": Accepted,
  "placement": Accepted,
  "replace": Accepted,
  "scope": Accepted,
  "runner": Accepted,
  "serve": Accepted,
  "vocabulary": Accepted,
  "wit": Accepted,
}
