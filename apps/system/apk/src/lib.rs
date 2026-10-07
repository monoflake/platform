//! `apk`: the machine's own packages on Alpine, through a named pipe. See
//! spec/architecture/packages.md, "`apk` reaches the machine through a named pipe".

pub mod door;

/// The socket's name in this service's directory, which host mounts into `cron` for it. See
/// spec/architecture/cron.md, "host gives `cron` the table".
pub const SOCKET: &str = "apk.sock";
