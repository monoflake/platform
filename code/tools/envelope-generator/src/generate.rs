//! [`Generate`] for [`Contracts`], read and held to what the Rust needs and then written, the same
//! for the same contracts byte for byte.

mod model;
mod names;
mod read;
mod rust;

use crate::{Contracts, Generate, Unread};

impl Generate for Contracts {
	fn read(text: &str) -> Result<Self, Unread> {
		let value: serde_json::Value = serde_json::from_str(text)
			.map_err(|e| Unread { at: String::new(), expected: format!("JSON: {e}") })?;
		read::contracts(&value)?;
		Ok(Self(value))
	}

	fn rust(&self) -> Result<String, Unread> {
		rust::module(&read::contracts(&self.0)?)
	}
}
