//! The two date shapes the X endpoints meet: ISO 8601 UTC timestamps the model writes, and
//! `YYYY-MM-DD` days a client passes. Enough of each to decide what a response may be cached for.

use std::time::{SystemTime, UNIX_EPOCH};

pub fn now() -> i64 {
	SystemTime::now().duration_since(UNIX_EPOCH).map(|elapsed| elapsed.as_secs() as i64).unwrap_or(0)
}

/// `2026-09-27T08:55:36Z` as seconds since the epoch. Fractions and offsets other than `Z` are
/// not what the model is asked for, and are refused rather than guessed at.
pub fn parse_timestamp(text: &str) -> Option<i64> {
	let text = text.strip_suffix('Z')?;
	let (date, time) = text.split_once('T')?;
	let day = parse_day(date)?;
	let mut parts = time.split(':').map(|part| part.parse::<i64>().ok());
	let (hours, minutes, seconds) = (parts.next()??, parts.next()??, parts.next()??);
	if parts.next().is_some() || hours > 23 || minutes > 59 || seconds > 60 {
		return None;
	}
	Some(day + hours * 3600 + minutes * 60 + seconds)
}

/// `2026-09-27` as the second it begins, UTC.
pub fn parse_day(text: &str) -> Option<i64> {
	let mut parts = text.split('-');
	let (year, month, day) = (parts.next()?, parts.next()?, parts.next()?);
	if parts.next().is_some() || year.len() != 4 || month.len() != 2 || day.len() != 2 {
		return None;
	}
	let (year, month, day): (i64, i64, i64) =
		(year.parse().ok()?, month.parse().ok()?, day.parse().ok()?);
	if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
		return None;
	}
	Some(days_from_civil(year, month, day) * 86400)
}

/// Seconds since the epoch as `2026-09-27T08:55:36Z`.
pub fn format_timestamp(seconds: i64) -> String {
	let (days, rest) = (seconds.div_euclid(86400), seconds.rem_euclid(86400));
	let (year, month, day) = civil_from_days(days);
	format!(
		"{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
		rest / 3600,
		rest % 3600 / 60,
		rest % 60
	)
}

/// Howard Hinnant's `days_from_civil`: days since 1970-01-01 in the proleptic Gregorian calendar.
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
	let year = if month <= 2 { year - 1 } else { year };
	let era = year.div_euclid(400);
	let year_of_era = year - era * 400;
	let day_of_year = (153 * (if month > 2 { month - 3 } else { month + 9 }) + 2) / 5 + day - 1;
	let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
	era * 146097 + day_of_era - 719468
}

fn civil_from_days(days: i64) -> (i64, i64, i64) {
	let days = days + 719468;
	let era = days.div_euclid(146097);
	let day_of_era = days - era * 146097;
	let year_of_era =
		(day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
	let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
	let month_index = (5 * day_of_year + 2) / 153;
	let day = day_of_year - (153 * month_index + 2) / 5 + 1;
	let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
	let year = year_of_era + era * 400 + i64::from(month <= 2);
	(year, month, day)
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn timestamps_round_trip() {
		let seconds = parse_timestamp("2026-09-27T08:55:36Z").unwrap();
		assert_eq!(seconds, 1_790_499_336);
		assert_eq!(format_timestamp(seconds), "2026-09-27T08:55:36Z");
		assert_eq!(parse_timestamp("1970-01-01T00:00:00Z"), Some(0));
	}

	#[test]
	fn days_begin_at_midnight() {
		assert_eq!(parse_day("2026-09-27"), Some(1_790_467_200));
		assert_eq!(parse_day("2024-02-29"), Some(1_709_164_800));
	}

	#[test]
	fn refuses_other_shapes() {
		for text in
			["2026-09-27T08:55:36", "2026-09-27 08:55:36Z", "Sun, 27 Sep 2026", "2026-13-01T00:00:00Z"]
		{
			assert_eq!(parse_timestamp(text), None, "{text}");
		}
		assert_eq!(parse_day("2026-9-27"), None);
	}
}
