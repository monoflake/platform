//! What `apt` and `apk` have in common: the routes, the envelope, and a run followed and told to
//! the ledger, behind a driver each implements. See spec/architecture/packages.md, "The interface
//! is the layer".

pub mod api;
pub mod driver;
pub mod run;

pub use api::{AppState, routes, serve};
pub use driver::{Driver, Job, JobState, Outcome};
