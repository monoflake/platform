//! `store`: a node's own store, S3 over its disk by its `objects` sidecar, and the daily mirror of
//! the database's backups into it. See spec/architecture/databases.md, "Backups are the data,
//! kept off the cluster".

pub mod api;
pub mod config;
pub mod mirror;
pub mod rclone;
pub mod store;
