//! When a job falls due, in UTC. See spec/architecture/cron.md, "A job is declared by the service
//! that does it".

use croner::Cron;
use croner::parser::{CronParser, Seconds, Year};
use jiff::tz::TimeZone;
use jiff::{SignedDuration, Timestamp};

#[derive(Debug, Clone)]
pub struct Schedule {
	rule: Rule,
	/// Seconds every due time is moved later by. See spec/architecture/cron.md, "A weekly job is
	/// spread across the nodes, a day apart".
	offset: i64,
}

#[derive(Debug, Clone)]
enum Rule {
	/// The five-field form, read in UTC.
	Cron(Box<Cron>),
	/// Whole seconds, counted from the Unix epoch, so every multiple is a due time and the one
	/// before a moment is known without a history.
	Every(i64),
}

impl Schedule {
	pub fn cron(text: &str) -> Result<Self, String> {
		let parser = CronParser::builder().seconds(Seconds::Disallowed).year(Year::Disallowed).build();
		let cron = parser.parse(text).map_err(|error| error.to_string())?;
		Ok(Self { rule: Rule::Cron(Box::new(cron)), offset: 0 })
	}

	/// `30s`, `1m`, `6h`: a positive whole number and one unit.
	pub fn every(text: &str) -> Result<Self, String> {
		let refused = || format!("`{text}` is not a number of seconds, minutes or hours");
		let unit = text.chars().last().ok_or_else(refused)?;
		let scale = match unit {
			's' => 1,
			'm' => 60,
			'h' => 3600,
			_ => return Err(refused()),
		};
		let count: i64 = text.strip_suffix(unit).unwrap_or_default().parse().map_err(|_| refused())?;
		if count <= 0 {
			return Err(refused());
		}
		let seconds = count.checked_mul(scale).ok_or_else(refused)?;
		Ok(Self { rule: Rule::Every(seconds), offset: 0 })
	}

	/// The same schedule with every due time `seconds` later.
	pub fn offset(self, seconds: u64) -> Result<Self, String> {
		let offset = i64::try_from(seconds).map_err(|_| format!("an offset of {seconds} seconds"))?;
		Ok(Self { offset, ..self })
	}

	/// The first due time strictly after `after`.
	pub fn next_after(&self, after: Timestamp) -> Option<Timestamp> {
		let shift = SignedDuration::from_secs(self.offset);
		self.rule.next_after(after.checked_sub(shift).ok()?)?.checked_add(shift).ok()
	}

	/// The last due time at or before `at`.
	pub fn previous(&self, at: Timestamp) -> Option<Timestamp> {
		let shift = SignedDuration::from_secs(self.offset);
		self.rule.previous(at.checked_sub(shift).ok()?)?.checked_add(shift).ok()
	}
}

impl Rule {
	fn next_after(&self, after: Timestamp) -> Option<Timestamp> {
		match self {
			Self::Cron(cron) => cron
				.find_next_occurrence(&after.to_zoned(TimeZone::UTC), false)
				.ok()
				.map(|zoned| zoned.timestamp()),
			Self::Every(seconds) => {
				let now = after.as_second();
				Timestamp::from_second((now.div_euclid(*seconds) + 1) * seconds).ok()
			}
		}
	}

	fn previous(&self, at: Timestamp) -> Option<Timestamp> {
		match self {
			Self::Cron(cron) => cron
				.find_previous_occurrence(&at.to_zoned(TimeZone::UTC), true)
				.ok()
				.map(|zoned| zoned.timestamp()),
			Self::Every(seconds) => {
				Timestamp::from_second(at.as_second().div_euclid(*seconds) * seconds).ok()
			}
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn at(text: &str) -> Timestamp {
		text.parse().unwrap()
	}

	#[test]
	fn daily_at_four_is_four_utc() {
		let schedule = Schedule::cron("0 4 * * *").unwrap();
		assert_eq!(schedule.next_after(at("2026-09-28T03:59:59Z")), Some(at("2026-09-28T04:00:00Z")));
		assert_eq!(schedule.next_after(at("2026-09-28T04:00:00Z")), Some(at("2026-09-29T04:00:00Z")));
		assert_eq!(schedule.previous(at("2026-09-28T04:00:00Z")), Some(at("2026-09-28T04:00:00Z")));
		assert_eq!(schedule.previous(at("2026-09-28T03:00:00Z")), Some(at("2026-09-27T04:00:00Z")));
	}

	#[test]
	fn steps_and_weekdays() {
		let quarter = Schedule::cron("*/15 * * * *").unwrap();
		assert_eq!(quarter.next_after(at("2026-09-28T12:07:30Z")), Some(at("2026-09-28T12:15:00Z")));
		// 2026-09-28 is a Monday; the next Sunday at 02:30 is 2026-10-04.
		let sunday = Schedule::cron("30 2 * * 0").unwrap();
		assert_eq!(sunday.next_after(at("2026-09-28T12:00:00Z")), Some(at("2026-10-04T02:30:00Z")));
		let month = Schedule::cron("0 0 1 * *").unwrap();
		assert_eq!(month.next_after(at("2026-09-28T12:00:00Z")), Some(at("2026-10-01T00:00:00Z")));
	}

	#[test]
	fn five_fields_only() {
		assert!(Schedule::cron("0 0 4 * * *").is_err());
		assert!(Schedule::cron("0 4 * *").is_err());
		assert!(Schedule::cron("61 4 * * *").is_err());
	}

	#[test]
	fn every_counts_from_the_epoch() {
		let minute = Schedule::every("1m").unwrap();
		assert_eq!(minute.next_after(at("2026-09-28T12:00:30Z")), Some(at("2026-09-28T12:01:00Z")));
		assert_eq!(minute.next_after(at("2026-09-28T12:01:00Z")), Some(at("2026-09-28T12:02:00Z")));
		assert_eq!(minute.previous(at("2026-09-28T12:00:30Z")), Some(at("2026-09-28T12:00:00Z")));
		let six = Schedule::every("6h").unwrap();
		assert_eq!(six.next_after(at("2026-09-28T13:00:00Z")), Some(at("2026-09-28T18:00:00Z")));
		let half = Schedule::every("30s").unwrap();
		assert_eq!(half.next_after(at("2026-09-28T12:00:10Z")), Some(at("2026-09-28T12:00:30Z")));
	}

	#[test]
	fn every_refuses_what_is_not_a_duration() {
		for text in ["", "m", "0s", "-1m", "1d", "1.5h", "90"] {
			assert!(Schedule::every(text).is_err(), "{text}");
		}
	}

	const DAY: u64 = 86_400;

	/// Sundays at 08:00, the upgrade's expression; 2026-09-28 is a Monday.
	fn weekly(offset: u64) -> Schedule {
		Schedule::cron("0 8 * * 0").unwrap().offset(offset).unwrap()
	}

	#[test]
	fn no_offset_is_the_expression_itself() {
		let schedule = weekly(0);
		assert_eq!(schedule.next_after(at("2026-09-28T12:00:00Z")), Some(at("2026-10-04T08:00:00Z")));
		assert_eq!(schedule.previous(at("2026-09-28T12:00:00Z")), Some(at("2026-09-27T08:00:00Z")));
	}

	#[test]
	fn an_offset_of_a_day_is_monday() {
		let schedule = weekly(DAY);
		assert_eq!(schedule.next_after(at("2026-09-28T07:59:59Z")), Some(at("2026-09-28T08:00:00Z")));
		assert_eq!(schedule.next_after(at("2026-09-28T12:00:00Z")), Some(at("2026-10-05T08:00:00Z")));
		// What catch-up compares against moves with it: Monday's run, not Sunday's.
		assert_eq!(schedule.previous(at("2026-09-28T12:00:00Z")), Some(at("2026-09-28T08:00:00Z")));
		assert_eq!(schedule.previous(at("2026-09-28T07:00:00Z")), Some(at("2026-09-21T08:00:00Z")));
	}

	#[test]
	fn an_offset_of_six_days_and_two_hours_is_saturday_at_ten() {
		let schedule = weekly(6 * DAY + 2 * 3600);
		assert_eq!(schedule.next_after(at("2026-09-28T12:00:00Z")), Some(at("2026-10-03T10:00:00Z")));
		assert_eq!(schedule.next_after(at("2026-10-03T10:00:00Z")), Some(at("2026-10-10T10:00:00Z")));
		assert_eq!(schedule.previous(at("2026-09-28T12:00:00Z")), Some(at("2026-09-26T10:00:00Z")));
		assert_eq!(schedule.previous(at("2026-10-03T10:00:00Z")), Some(at("2026-10-03T10:00:00Z")));
	}

	#[test]
	fn an_offset_moves_every_too() {
		let schedule = Schedule::every("1h").unwrap().offset(15 * 60).unwrap();
		assert_eq!(schedule.next_after(at("2026-09-28T12:00:00Z")), Some(at("2026-09-28T12:15:00Z")));
		assert_eq!(schedule.previous(at("2026-09-28T12:00:00Z")), Some(at("2026-09-28T11:15:00Z")));
	}

	#[test]
	fn an_offset_past_what_a_timestamp_holds_is_refused() {
		assert!(Schedule::every("1m").unwrap().offset(u64::MAX).is_err());
	}
}
