//! [`Generate`] for [`Contracts`]: the text read as JSON and held to what the Rust needs, `read`,
//! then written, `rust`. What is read is kept as the JSON it is, so the Rust is written from it
//! again, the same for the same contracts byte for byte: every part is written in the order it is
//! read, and `serde_json` keeps an object's keys in one order.

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
