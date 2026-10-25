/***
 * Whether a run reaches the network, which a case marked `network` needs, told by `--network` and
 * never probed, so a case needing it is skipped and never passed unless told yes, RFC 8j7b0.
 */

/** Whether the run reaches the network, `yes` or `no` as given, and `no` where nothing is. */
let reaches = (given: option<string>) =>
  switch given {
  | Some("yes") => Ok(true)
  | Some("no") | None => Ok(false)
  | Some(other) => Error(`--network ${other}, neither yes nor no`)
  }

/**
 * Whether a control's base is on this machine's loopback, `localhost`, `127.0.0.0/8` or `::1`, the
 * one sign of a control in local mode the runner can read before it runs anything.
 */
let loopback = base =>
  switch Web.hostOf(base) {
  | Some(host) =>
    host == "localhost" ||
    host->String.endsWith(".localhost") ||
    host == "[::1]" ||
    /^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/->RegExp.test(host)
  | None => false
  }

/**
 * Whether a case binding by a tunnel is run, `yes` against a control on the loopback alone, as a
 * tunnel bind elsewhere may make a real tunnel, and `no` where nothing is given, RFC 8j7b0.
 */
let tunnels = (given: option<string>, ~base) =>
  switch given {
  | Some("yes") if loopback(base) => Ok(true)
  | Some("yes") =>
    Error(
      `--tunnel yes against ${base}, which the runner cannot tell is a control in local mode, as only one on this machine's loopback is taken for one`,
    )
  | Some("no") | None => Ok(false)
  | Some(other) => Error(`--tunnel ${other}, neither yes nor no`)
  }
