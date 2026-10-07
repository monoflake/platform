//! `apt`: the machine's own packages, through a narrow door. See spec/architecture/apt.md.

pub mod bus;
pub mod units;

/// The socket's name in this service's directory, which host mounts into `cron` for it. See
/// spec/architecture/cron.md, "host gives `cron` the table".
pub const SOCKET: &str = "apt.sock";
