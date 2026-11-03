/***
 * What the runs' replay takes of node, the run file read beside this module and a timer to wait on.
 */
type url

@new external url: (string, string) => url = "URL"
@val external moduleUrl: string = "import.meta.url"
@module("node:fs") external readText: (url, @as("utf8") _) => string = "readFileSync"

/** Resolves after `milliseconds`, the replay's poll for an actor's next call. */
let sleep = milliseconds =>
  Promise.make((resolve, _) => setTimeout(() => resolve(), milliseconds)->ignore)
