/***
 * What a deployed Worker reaches by the slots its build declares, each as `env.<slot name>`, RFC
 * rt6gi. The database speaks the `database` contract's execute, its input and answer as JSON.
 */
type database = {execute: JSON.t => promise<JSON.t>}

/**
 * The storage product's bucket the deploy filled, RFC ahcrp. An object is named by its content,
 * `write` takes the content's bytes and its extension and answers the `bucket-object` record as
 * JSON, and `read` answers the content as bytes.
 */
type objects = {
  write: (Uint8Array.t, string) => promise<JSON.t>,
  read: (string, option<JSON.t>) => promise<Uint8Array.t>,
  describe: string => promise<JSON.t>,
  list: (option<string>, option<int>) => promise<JSON.t>,
  delete: string => promise<JSON.t>,
}

/** The environment the runtime hands the Worker, a slot there only where the deploy filled it. */
type env = {database?: database, objects?: objects}

type t = Unreached(string)

let database = (env: env) =>
  switch env.database {
  | Some(database) => Ok(database)
  | None => Error(Unreached("database"))
  }

let objects = (env: env) =>
  switch env.objects {
  | Some(objects) => Ok(objects)
  | None => Error(Unreached("object"))
  }
