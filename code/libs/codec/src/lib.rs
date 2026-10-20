//! `codec*`, `model/graph/libraries.res`: its interface is `src/interface.rs`, the model's.

mod cbor;
mod cwt;
mod interface;
mod sign1;

pub use interface::*;
