//! `database`: the platform's Postgres, run by a keeper that answers for it. See
//! spec/architecture/databases.md.

// render.rs's `shared` is one `json!` of every parameter the members agree on.
#![recursion_limit = "256"]

pub mod amcheck;
pub mod api;
pub mod backup;
pub mod config;
pub mod health;
pub mod keeper;
pub mod patroni;
pub mod postgres;
pub mod render;
pub mod watch;
