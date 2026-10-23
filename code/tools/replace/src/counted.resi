/***
 * What one path answered while one action was taken, counted and its longest silence measured,
 * RFC ehm48.
 */

/** What a path was asked from one action until the next, and how it answered. */
type counted = {
  path: string,
  made: int,
  answered: int,
  refused: int,
  /** Asked and neither answered 200 nor refused. */
  failed: int,
  /** The longest time no answer was seen, in milliseconds, from the window's start to its end. */
  longest: float,
  /** Each reason it was refused or failed for and how many times, the most first. */
  reasons: array<(string, int)>,
}

/** The asks of a path that began in the window from `from` to `until`, counted. */
let count: (~path: string, ~from: float, ~until: float, array<Load.asked>) => counted

/** Whether the path was asked and answered 200 every time. */
let held: counted => bool

/** The count as the report writes it, on one line. */
let line: counted => string
