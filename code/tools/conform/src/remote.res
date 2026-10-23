type target = {host: string, options: array<string>}

/** One connection kept open between the phases, so each costs no handshake. */
let kept = [
  "-o",
  "BatchMode=yes",
  "-o",
  "ControlMaster=auto",
  "-o",
  // Under the home, as the system's own temporary directory is too long a path for a socket.
  "ControlPath=~/.ssh/monoflake-conform-%C",
  "-o",
  "ControlPersist=120",
]

let target = name =>
  name == "local"
    ? {
        host: "root@localhost",
        options: [
          ...kept,
          "-p",
          "2222",
          "-o",
          "StrictHostKeyChecking=no",
          "-o",
          "UserKnownHostsFile=/dev/null",
          "-o",
          "LogLevel=ERROR",
        ],
      }
    : {host: name, options: kept}

// Its own connection, so stopping it closes the forward alone; ssh takes an option's first value.
let forward = (target, ~local, ~remote) =>
  [
    "-o",
    "ControlMaster=no",
    "-o",
    "ControlPath=none",
    ...target.options,
    "-o",
    "ExitOnForwardFailure=yes",
    "-N",
    "-L",
    `${Int.toString(local)}:127.0.0.1:${Int.toString(remote)}`,
    target.host,
  ]
