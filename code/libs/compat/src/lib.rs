//! `compat*`, `model/graph/libraries.res`, and this file its interface, the model's, `docs/code.md`:
//! the same contract as `src/version.resi` and `src/features.resi` hold in ReScript, a private
//! module beside each. Whoever implements it implements each trait for the type it names there,
//! and never edits this file.
//!
//! RFC wnqvu: a version is the frozen core, one integer raised only by a breaking change, compared
//! by its value; a reader reads a range; a writer writes the version every reader running reads;
//! and what a version cannot say, features do. Where a version is carried is each format's own.

mod features;
mod version;

/// The largest version, 2^53 - 1, JavaScript's largest safe integer, so both languages hold every
/// version exactly, decided by the author on 2026-10-20.
pub const MAX: u64 = 9_007_199_254_740_991;

/// A version: an integer of 0 to [`MAX`], made by [`Versioned::new`] alone.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Version(u64);

/// The versions a reader reads, its lowest to its highest, both read; its highest is the most it
/// could write. Made by [`Ranged::new`] alone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Range {
	lowest: Version,
	highest: Version,
}

/// Why a reader refuses a version.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refused {
	/// Below its lowest: written in what it reads no longer.
	Older {
		/// The version refused.
		version: Version,
		/// The range that refused it.
		range: Range,
	},
	/// Above its highest: written in what it does not yet read.
	Newer {
		/// The version refused.
		version: Version,
		/// The range that refused it.
		range: Range,
	},
}

/// Why no version can be written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Unchosen {
	/// No range was given.
	Empty,
	/// The lowest of every range's highest is below the lowest of each of these ranges: no version
	/// is read by all.
	Apart {
		/// The lowest of every range's highest.
		highest: Version,
		/// The ranges whose lowest is above it, by their positions as given, ascending.
		above: Vec<usize>,
	},
}

/// The frozen core; implemented for [`Version`].
pub trait Versioned: Sized {
	/// The number as a version, or none above [`MAX`].
	fn new(number: u64) -> Option<Self>;
	/// Its value.
	fn get(self) -> u64;
}

/// A reader's range, and the version written among several; implemented for [`Range`].
pub trait Ranged: Sized {
	/// The range of the two, or none where the lowest is above the highest.
	fn new(lowest: Version, highest: Version) -> Option<Self>;
	/// Its lowest.
	fn lowest(&self) -> Version;
	/// Its highest.
	fn highest(&self) -> Version;
	/// Whether it reads the version.
	fn reads(&self, version: Version) -> Result<(), Refused>;
	/// What is written among the ranges of every reader running, the writer's own among them: the
	/// lowest of their highest, which each reads, the same whatever their order.
	fn written(ranges: &[Self]) -> Result<Version, Unchosen>;
}

/// A side's features: those it has, and those of them it needs; each list sorted, each name once.
/// Made by [`Featured::new`] alone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Features {
	has: Vec<String>,
	needs: Vec<String>,
}

/// Why a side's features were not made.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Malformed {
	/// A name empty, or holding anything but lowercase ASCII letters, digits and hyphens.
	Name(String),
	/// A name needed, yet not had.
	Unheld(String),
}

/// Why two sides do not agree: what the first needs and the second has not, and the reverse, each
/// sorted.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Missing {
	/// What the first needs and the second has not.
	pub first: Vec<String>,
	/// What the second needs and the first has not.
	pub second: Vec<String>,
}

/// What both sides have; implemented for [`Features`].
pub trait Featured: Sized {
	/// The features, each list sorted and its repeats dropped, or the first name refused: every name
	/// of `has` in its order, then every one of `needs`.
	fn new(has: &[&str], needs: &[&str]) -> Result<Self, Malformed>;
	/// Those it has.
	fn has(&self) -> &[String];
	/// Those of them it needs.
	fn needs(&self) -> &[String];
	/// What both have, sorted, or what either needs and the other has not.
	fn agreed(&self, other: &Self) -> Result<Vec<String>, Missing>;
}
