/***
 * What one path answered while the driver was stopped, counted and its longest silence measured,
 * RFC rmll5.
 */

/** One ask of hello, when it began and ended in milliseconds, and how it was answered. */
type asked = {began: float, ended: float, answer: result<unit, string>}

/** What a path was asked through the window, and how it answered. */
type tally = {
  path: string,
  asked: int,
  answered: int,
  failed: int,
  /** The longest time no answer was seen, in milliseconds, from the window's start to its end. */
  longest: float,
  /** Each reason it failed for and how many times, the most first. */
  reasons: array<(string, int)>,
}

/** The asks of a path over the window from `from` to `until`, counted. */
let tally: (~path: string, ~from: float, ~until: float, array<asked>) => tally

/** Whether the path was asked and answered every time. */
let held: tally => bool

/** The tally as the report writes it, on one line. */
let line: tally => string
