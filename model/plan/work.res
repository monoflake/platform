/**
 * Each written block's state by its package's name, `docs/code.md`. A block in work fails nothing,
 * and one written but not named here is refused.
 */
type state = InWork | Accepted

let blocks: dict<state> = dict{
  "codec": Accepted,
  "compat": Accepted,
  "conform": InWork,
  "control-organization": InWork,
  "deploy": InWork,
  "envelope": Accepted,
  "envelope-generator": Accepted,
  "extensions": Accepted,
  "host": Accepted,
  "capability": Accepted,
  "ids": InWork,
  "keys": Accepted,
  "layout": Accepted,
  "lose": InWork,
  "placement": Accepted,
  "replace": InWork,
  "scope": Accepted,
  "runner": Accepted,
  "serve": Accepted,
  "vocabulary": Accepted,
  "wit": Accepted,
}
