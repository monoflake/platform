//! A float at the narrowest of CBOR's three widths that keeps its value, RFC 8949's 4.2.1, written
//! by minicbor's encoder, whose half is the `half` crate's.

use minicbor::Decoder;

use super::encode::{Writer, put};

/// Writes `x` at the narrowest width that holds it exactly, every NaN as f97e00.
pub(super) fn write(x: f64, e: &mut Writer) {
	if x.is_nan() {
		// A single's quiet NaN, 7fc00000, is the half 7e00.
		put(e.f16(f32::NAN));
	} else if let Some(single) = single(x) {
		if half(single) {
			put(e.f16(single));
		} else {
			put(e.f32(single));
		}
	} else {
		put(e.f64(x));
	}
}

/// Whether a half holds `x` exactly, read back bit for bit.
fn half(x: f32) -> bool {
	let mut e = Writer::new(Vec::new());
	put(e.f16(x));
	Decoder::new(e.writer()).f16().is_ok_and(|y| y.to_bits() == x.to_bits())
}

/// `x` as a single, where a single holds it exactly; never a NaN.
fn single(x: f64) -> Option<f32> {
	let bits = x.to_bits();
	let sign = u32::try_from(bits >> 63).ok()? << 31;
	let exponent = i32::try_from((bits >> 52) & 0x7ff).ok()? - 1023;
	let fraction = bits & ((1 << 52) - 1);
	let magnitude = match exponent {
		// Infinity and zero, a double's subnormal being no single's.
		1024 => 0x7f80_0000,
		-1023 => 0,
		-126..=127 => {
			(u32::try_from(exponent + 127).ok()? << 23) | u32::try_from(fraction >> 29).ok()?
		}
		// A single's subnormal, the significand with its leading one shifted to its scale.
		-149..=-127 => u32::try_from((fraction | (1 << 52)) >> (-97 - exponent)).ok()?,
		_ => return None,
	};
	let single = f32::from_bits(sign | magnitude);
	// What was cut off in narrowing shows as a double no longer the same.
	(f64::from(single).to_bits() == bits).then_some(single)
}
