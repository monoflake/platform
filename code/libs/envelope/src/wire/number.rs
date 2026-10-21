//! The subset's numbers, a 64-bit float, 32-bit integers and [`Uint53`] and [`Int53`]. An integer
//! is read by its value, `5.0` and `1e2` among them in JSON.

use codec::Value as Cbor;
use serde_json::Value as Json;

use super::Read;
use crate::{Bounded, Int53, Malformed, Uint53};

/// 2^53 - 1, the most a JavaScript number holds exactly.
const MAX: u64 = (1 << 53) - 1;

/// [`MAX`], signed.
const MAX_SIGNED: i64 = (1 << 53) - 1;

impl Bounded<u64> for Uint53 {
	fn new(number: u64) -> Option<Self> {
		(number <= MAX).then_some(Self(number))
	}

	fn get(self) -> u64 {
		self.0
	}
}

impl Bounded<i64> for Int53 {
	fn new(number: i64) -> Option<Self> {
		(-MAX_SIGNED..=MAX_SIGNED).contains(&number).then_some(Self(number))
	}

	fn get(self) -> i64 {
		self.0
	}
}

const INT32: &str = "an integer of -2^31 to 2^31 - 1";
const UINT32: &str = "an integer of 0 to 2^32 - 1";
const INT53: &str = "an integer of -(2^53 - 1) to 2^53 - 1";
const UINT53: &str = "an integer of 0 to 2^53 - 1";
const FLOAT: &str = "a number";
const FINITE: &str = "a finite float";

/// The integer a JSON number is exactly within 2^53 either way, a float taken apart by its bits so
/// nothing is rounded.
fn exact(json: &Json) -> Option<i64> {
	if let Some(n) = json.as_i64() {
		return Some(n);
	}
	let x = json.as_f64().filter(|x| json.is_f64() && x.is_finite() && x.trunc() == *x)?;
	if x.abs() > 9_007_199_254_740_991.0 {
		return None;
	}
	let bits = x.to_bits();
	let exponent = (bits >> 52) & 0x7ff;
	if exponent == 0 {
		// A zero of either sign, as no other float this small is integral.
		return Some(0);
	}
	// The value is the significand times 2^(exponent - 1075) and integral, so the shift drops zeros.
	let significand = (bits & ((1 << 52) - 1)) | (1 << 52);
	let shift = u32::try_from(1075_u64.checked_sub(exponent)?).ok()?;
	let magnitude = i64::try_from(significand.checked_shr(shift)?).ok()?;
	Some(if bits >> 63 == 1 { -magnitude } else { magnitude })
}

/// The integer of a CBOR item, if it is one.
fn integer(cbor: &Cbor) -> Option<i128> {
	if let Cbor::Integer(n) = cbor { Some(*n) } else { None }
}

/// A float's JSON; a NaN or an infinity, which JSON has no number for, is written `null`, which
/// no reader takes.
pub(crate) fn float_to_json(value: &f64) -> Json {
	Json::from(*value)
}

/// A float, from any number.
pub(crate) fn float_from_json(json: &Json) -> Read<f64> {
	json.as_f64().ok_or_else(|| Malformed::expected(FLOAT))
}

/// A float's CBOR, which codec writes at its shortest width.
pub(crate) fn float_to_cbor(value: &f64) -> Cbor {
	Cbor::Float(*value)
}

/// A float, from a finite float of any width, as JSON can write it.
pub(crate) fn float_from_cbor(cbor: &Cbor) -> Read<f64> {
	let value = if let Cbor::Float(value) = cbor { Some(*value) } else { None };
	value.filter(|v| v.is_finite()).ok_or_else(|| Malformed::expected(FINITE))
}

/// A signed 32-bit integer's JSON.
#[allow(dead_code, reason = "the subset holds a signed 32-bit integer no contract has yet")]
pub(crate) fn int32_to_json(value: &i32) -> Json {
	Json::from(*value)
}

/// A signed 32-bit integer.
#[allow(dead_code, reason = "the subset holds a signed 32-bit integer no contract has yet")]
pub(crate) fn int32_from_json(json: &Json) -> Read<i32> {
	exact(json).and_then(|n| i32::try_from(n).ok()).ok_or_else(|| Malformed::expected(INT32))
}

/// A signed 32-bit integer's CBOR.
#[allow(dead_code, reason = "the subset holds a signed 32-bit integer no contract has yet")]
pub(crate) fn int32_to_cbor(value: &i32) -> Cbor {
	Cbor::Integer(i128::from(*value))
}

/// A signed 32-bit integer.
pub(crate) fn int32_from_cbor(cbor: &Cbor) -> Read<i32> {
	integer(cbor).and_then(|n| i32::try_from(n).ok()).ok_or_else(|| Malformed::expected(INT32))
}

/// An unsigned 32-bit integer's JSON, an id's among them.
pub(crate) fn uint32_to_json(value: &u32) -> Json {
	Json::from(*value)
}

/// An unsigned 32-bit integer.
pub(crate) fn uint32_from_json(json: &Json) -> Read<u32> {
	exact(json).and_then(|n| u32::try_from(n).ok()).ok_or_else(|| Malformed::expected(UINT32))
}

/// An unsigned 32-bit integer's CBOR.
pub(crate) fn uint32_to_cbor(value: &u32) -> Cbor {
	Cbor::Integer(i128::from(*value))
}

/// An unsigned 32-bit integer.
pub(crate) fn uint32_from_cbor(cbor: &Cbor) -> Read<u32> {
	integer(cbor).and_then(|n| u32::try_from(n).ok()).ok_or_else(|| Malformed::expected(UINT32))
}

/// An integer within 2^53's JSON.
pub(crate) fn int53_to_json(value: &Int53) -> Json {
	Json::from(value.get())
}

/// An integer within 2^53.
pub(crate) fn int53_from_json(json: &Json) -> Read<Int53> {
	exact(json).and_then(Int53::new).ok_or_else(|| Malformed::expected(INT53))
}

/// An integer within 2^53's CBOR.
pub(crate) fn int53_to_cbor(value: &Int53) -> Cbor {
	Cbor::Integer(i128::from(value.get()))
}

/// An integer within 2^53.
pub(crate) fn int53_from_cbor(cbor: &Cbor) -> Read<Int53> {
	integer(cbor)
		.and_then(|n| i64::try_from(n).ok())
		.and_then(Int53::new)
		.ok_or_else(|| Malformed::expected(INT53))
}

/// An integer under 2^53's JSON.
pub(crate) fn uint53_to_json(value: &Uint53) -> Json {
	Json::from(value.get())
}

/// An integer under 2^53.
pub(crate) fn uint53_from_json(json: &Json) -> Read<Uint53> {
	exact(json)
		.and_then(|n| u64::try_from(n).ok())
		.and_then(Uint53::new)
		.ok_or_else(|| Malformed::expected(UINT53))
}

/// An integer under 2^53's CBOR.
pub(crate) fn uint53_to_cbor(value: &Uint53) -> Cbor {
	Cbor::Integer(i128::from(value.get()))
}

/// An integer under 2^53.
pub(crate) fn uint53_from_cbor(cbor: &Cbor) -> Read<Uint53> {
	integer(cbor)
		.and_then(|n| u64::try_from(n).ok())
		.and_then(Uint53::new)
		.ok_or_else(|| Malformed::expected(UINT53))
}
