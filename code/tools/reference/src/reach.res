/***
 * What a deployed Worker reaches by the slots its build declares, each as `env.<slot name>`, RFC
 * rt6gi. The database speaks the `database` contract's execute, its input and answer as JSON.
 */
type database = {execute: JSON.t => promise<JSON.t>}

/** The environment the runtime hands the Worker, a slot there only where the deploy filled it. */
type env = {database?: database}

type t = Unreached(string)

let database = (env: env) =>
  switch env.database {
  | Some(database) => Ok(database)
  | None => Error(Unreached("database"))
  }

let object = () => Unreached("object")
