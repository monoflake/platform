//! `apk`'s driver: a job is a word written into the machine's named pipe, and its state is a file
//! the machine's door writes back. Both live in one directory host mounts read-only. See
//! spec/architecture/packages.md, "`apk` reaches the machine through a named pipe".

use async_trait::async_trait;
use packages::{Driver, Job, JobState, Outcome};
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::time::{Duration, Instant};

/// How long a start waits for the door to take its word up, so the `202` shows the run under way.
/// A door busy with the other job takes it up later, and the run is followed all the same.
const PICKUP: Duration = Duration::from_secs(2);
const PICKUP_POLL: Duration = Duration::from_millis(100);

/// The machine's door, as the directory it is mounted at.
pub struct Door {
	directory: PathBuf,
}

impl Door {
	pub fn at(directory: PathBuf) -> Self {
		Self { directory }
	}

	fn pipe(&self) -> PathBuf {
		self.directory.join("door")
	}

	fn state_file(&self, job: Job) -> PathBuf {
		self.directory.join(format!("{}.state", job.name()))
	}

	/// The pipe, opened to write without waiting: a door that is not reading refuses it with
	/// `ENXIO`, which is answered as unavailable rather than waited on.
	fn open(&self) -> anyhow::Result<File> {
		let opened = OpenOptions::new().write(true).custom_flags(libc::O_NONBLOCK).open(self.pipe());
		opened.map_err(|error| match error.raw_os_error() {
			Some(libc::ENXIO) => anyhow::anyhow!("the door has no reader"),
			_ => error.into(),
		})
	}
}

#[async_trait]
impl Driver for Door {
	type State = Reading;
	const SERVICE: &'static str = "apk";
	const READS: &'static str = "the job's state file";

	/// Success while the directory reads and the pipe has a reader.
	async fn health(&self) -> anyhow::Result<()> {
		std::fs::read_dir(&self.directory)?;
		self.open().map(drop)
	}

	/// A job that has never run has no file yet, and reads as idle.
	async fn state(&self, job: Job) -> anyhow::Result<Reading> {
		match std::fs::read_to_string(self.state_file(job)) {
			Ok(text) => Reading::parse(&text),
			Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Reading::default()),
			Err(error) => Err(error.into()),
		}
	}

	async fn start(&self, job: Job, before: &Reading) -> anyhow::Result<()> {
		let mut pipe = self.open()?;
		pipe.write_all(format!("{}\n", job.name()).as_bytes())?;
		drop(pipe);

		let deadline = Instant::now() + PICKUP;
		while Instant::now() < deadline {
			if self.state(job).await.is_ok_and(|now| now.seq != before.seq) {
				break;
			}
			tokio::time::sleep(PICKUP_POLL).await;
		}
		Ok(())
	}

	fn target(&self, job: Job) -> &'static str {
		job.name()
	}
}

/// One state file, as `door/apk-door.sh` writes it: a `key=value` line each, times in seconds
/// since the epoch, and an empty value for what a run has not had.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Reading {
	/// Moves with every run the door starts, so a run is told apart from the one before it.
	pub seq: u64,
	pub running: bool,
	pub started_at: Option<i64>,
	pub finished_at: Option<i64>,
	pub exit_status: Option<i32>,
	/// "success", "failed" or "interrupted"; empty before the first run has ended.
	pub result: String,
	pub reboot_required: bool,
}

impl Reading {
	pub fn parse(text: &str) -> anyhow::Result<Self> {
		let mut reading = Reading::default();
		for line in text.lines() {
			let Some((key, value)) = line.split_once('=') else { continue };
			match key {
				"seq" => reading.seq = value.parse()?,
				"running" => reading.running = flag(value)?,
				"started_at" => reading.started_at = number(value)?,
				"finished_at" => reading.finished_at = number(value)?,
				"exit_status" => reading.exit_status = number(value)?,
				"result" => reading.result = value.to_owned(),
				"reboot_required" => reading.reboot_required = flag(value)?,
				_ => {}
			}
		}
		Ok(reading)
	}
}

fn flag(value: &str) -> anyhow::Result<bool> {
	match value {
		"0" => Ok(false),
		"1" => Ok(true),
		_ => anyhow::bail!("not a flag: {value}"),
	}
}

fn number<T: std::str::FromStr>(value: &str) -> anyhow::Result<Option<T>>
where
	T::Err: std::error::Error + Send + Sync + 'static,
{
	if value.is_empty() { Ok(None) } else { Ok(Some(value.parse()?)) }
}

/// Seconds since the epoch, read as RFC 3339.
fn seconds(value: i64) -> Option<String> {
	jiff::Timestamp::from_second(value).ok().map(|at| at.to_string())
}

impl JobState for Reading {
	fn running(&self) -> bool {
		self.running
	}

	/// The door moves `seq` as it takes a word up, so a run is over once it has moved and the
	/// door no longer reads as running.
	fn finished_since(&self, before: &Self) -> bool {
		self.seq != before.seq && !self.running
	}

	/// Whether it is running, its last run when it has had one, and whether a reboot waits.
	fn view(&self, _job: Job) -> serde_json::Value {
		let last_run = self.started_at.map(|started_at| {
			serde_json::json!({
				"started_at": seconds(started_at),
				"finished_at": self.finished_at.and_then(seconds),
				"result": (!self.result.is_empty()).then_some(&self.result),
				"exit_status": self.exit_status,
			})
		});
		serde_json::json!({
			"running": self.running,
			"last_run": last_run,
			"reboot_required": self.reboot_required,
		})
	}

	fn outcome(&self) -> Outcome {
		Outcome {
			success: self.result == "success",
			result: self.result.clone(),
			exit_status: self.exit_status,
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use axum::Router;
	use axum::body::Body;
	use axum::http::{Request, StatusCode};
	use http_body_util::BodyExt;
	use packages::{AppState, routes};
	use std::ffi::CString;
	use std::io::Read;
	use std::os::unix::ffi::OsStrExt;
	use std::path::Path;
	use std::sync::Arc;
	use tower::ServiceExt;

	const IDLE: &str = "seq=4\nrunning=0\nstarted_at=1791360000\nfinished_at=1791360060\n\
		exit_status=0\nresult=success\nreboot_required=1\n";

	fn fifo(directory: &Path) {
		let path = CString::new(directory.join("door").as_os_str().as_bytes()).unwrap();
		assert_eq!(unsafe { libc::mkfifo(path.as_ptr(), 0o600) }, 0);
	}

	/// The reading end of the pipe, held as the door holds it, without waiting for a writer.
	fn reader(directory: &Path) -> File {
		let path = directory.join("door");
		OpenOptions::new().read(true).custom_flags(libc::O_NONBLOCK).open(path).unwrap()
	}

	fn router(directory: &Path) -> Router {
		let driver = Arc::new(Door::at(directory.to_owned()));
		routes(AppState { driver, ledger: None })
	}

	async fn ask(router: Router, method: &str, path: &str) -> (StatusCode, serde_json::Value) {
		let request = Request::builder().method(method).uri(path).body(Body::empty()).unwrap();
		let answer = router.oneshot(request).await.unwrap();
		let status = answer.status();
		let body = answer.into_body().collect().await.unwrap().to_bytes();
		(status, serde_json::from_slice(&body).unwrap())
	}

	#[test]
	fn a_state_file_reads_field_by_field() {
		let reading = Reading::parse(IDLE).unwrap();
		assert_eq!(reading.seq, 4);
		assert!(!reading.running);
		assert_eq!(reading.started_at, Some(1_791_360_000));
		assert_eq!(reading.exit_status, Some(0));
		assert!(reading.reboot_required);

		let interrupted = Reading::parse("seq=5\nrunning=0\nexit_status=\nresult=interrupted\n");
		let interrupted = interrupted.unwrap();
		assert_eq!(interrupted.exit_status, None);
		assert!(!interrupted.outcome().success);
		assert!(Reading::parse("running=yes\n").is_err());
	}

	#[test]
	fn a_run_is_over_once_seq_moved_and_it_stopped() {
		let before = Reading { seq: 4, ..Default::default() };
		assert!(!Reading { seq: 4, ..Default::default() }.finished_since(&before));
		assert!(!Reading { seq: 5, running: true, ..Default::default() }.finished_since(&before));
		assert!(Reading { seq: 5, ..Default::default() }.finished_since(&before));
	}

	#[tokio::test]
	async fn status_reads_both_files_and_a_missing_one_is_idle() {
		let directory = tempfile::tempdir().unwrap();
		std::fs::write(directory.path().join("upgrade.state"), IDLE).unwrap();
		let (status, body) = ask(router(directory.path()), "GET", "/status").await;
		assert_eq!(status, StatusCode::OK);
		assert_eq!(body["data"]["update"]["last_run"], serde_json::Value::Null);
		assert_eq!(body["data"]["upgrade"]["running"], false);
		assert_eq!(body["data"]["upgrade"]["reboot_required"], true);
		assert_eq!(body["data"]["upgrade"]["last_run"]["started_at"], "2026-10-07T08:00:00Z");
		assert_eq!(body["data"]["upgrade"]["last_run"]["result"], "success");
	}

	#[tokio::test]
	async fn a_door_nobody_reads_is_unavailable() {
		let directory = tempfile::tempdir().unwrap();
		fifo(directory.path());
		let (status, _) = ask(router(directory.path()), "GET", "/health").await;
		assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
		let (status, body) = ask(router(directory.path()), "POST", "/jobs/update").await;
		assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
		assert_eq!(body["code"], "service_unavailable");
	}

	#[tokio::test]
	async fn a_running_job_refuses_a_second_start() {
		let directory = tempfile::tempdir().unwrap();
		fifo(directory.path());
		let mut door = reader(directory.path());
		std::fs::write(directory.path().join("upgrade.state"), "seq=2\nrunning=1\n").unwrap();
		let (status, body) = ask(router(directory.path()), "POST", "/jobs/upgrade").await;
		assert_eq!(status, StatusCode::CONFLICT);
		assert_eq!(body["code"], "job_running");
		let mut word = String::new();
		assert!(door.read_to_string(&mut word).is_err() || word.is_empty());
	}

	#[tokio::test]
	async fn a_start_writes_its_word_and_answers_with_the_run_under_way() {
		let directory = tempfile::tempdir().unwrap();
		fifo(directory.path());
		let mut door = reader(directory.path());
		assert_eq!(ask(router(directory.path()), "GET", "/health").await.0, StatusCode::OK);
		std::fs::write(directory.path().join("update.state"), IDLE).unwrap();

		// The door's half: take the word up and write the run as started.
		let state = directory.path().join("update.state");
		let taken = std::thread::spawn(move || {
			let mut word = [0; 16];
			let deadline = Instant::now() + Duration::from_secs(5);
			loop {
				match door.read(&mut word) {
					Ok(read) if read > 0 => {
						std::fs::write(&state, "seq=5\nrunning=1\nstarted_at=1791363600\n").unwrap();
						return String::from_utf8_lossy(&word[..read]).into_owned();
					}
					_ if Instant::now() > deadline => return String::new(),
					_ => std::thread::sleep(Duration::from_millis(10)),
				}
			}
		});

		let (status, body) = ask(router(directory.path()), "POST", "/jobs/update").await;
		assert_eq!(taken.join().unwrap(), "update\n");
		assert_eq!(status, StatusCode::ACCEPTED);
		assert_eq!(body["data"]["running"], true);
		assert_eq!(body["data"]["last_run"]["finished_at"], serde_json::Value::Null);
		assert_eq!(body["data"]["last_run"]["result"], serde_json::Value::Null);
	}
}
