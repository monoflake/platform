/**
 * Each written block's state, by its package's name, decided by the author on 2026-10-20,
 * `docs/code.md`. A block is in work while a worker writes or reworks it: the conversation marks it
 * so when it dispatches one, or when it changes the block's interface, and what the block fails is
 * then listed in red and refuses no commit. It is accepted once its acceptance passed and its diff
 * was read, and from then on whatever it fails fails the check. A block written and named here by
 * neither is refused, so none is either by silence.
 */
type state = InWork | Accepted

let blocks: dict<state> = dict{
  "codec": Accepted,
  "compat": Accepted,
  "envelope": Accepted,
  "envelope-generator": Accepted,
  "capability": Accepted,
  "driver-machine-system": Accepted,
  "keys": Accepted,
  "layout": Accepted,
  "placement": Accepted,
  "pins": InWork,
  "driver-machine-images": InWork,
  "driver-machine-container": InWork,
  "driver-machine-management": Accepted,
  "runner": InWork,
  "serve": InWork,
}
