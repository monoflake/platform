//! `primary`: the database at one address on every node, passed on to whichever member Patroni says
//! is primary. See spec/architecture/databases.md, "Where it runs, and which one writes".

pub mod api;
pub mod check;
pub mod config;
pub mod proxy;
pub mod state;
pub mod watch;
