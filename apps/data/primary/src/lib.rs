//! `primary`: the database at one address on every node, passed on to whichever member Patroni says
//! is primary. See spec/todo/todo.md, "The database".

pub mod api;
pub mod check;
pub mod config;
pub mod proxy;
pub mod state;
pub mod watch;
