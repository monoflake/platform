/**
 * What conform writes for each target it ran, RFC s42ex, one JSON file each under `directory`,
 * named for the target as conform was given it, and read by no part of the check that refuses.
 */
let directory = "~/.local/state/workspace/snapshots/"

/** One contract's cases as the runner counted them, each case once in each form. */
type counted = {passed: int, failed: int, waiting: int, skipped: int}

/**
 * One target's snapshot, the commit of the checkout conform ran from, which binds nothing the
 * target reports, the time it ran, and each contract's counts by its interface's name.
 */
type snapshot = {target: string, checkout: string, at: string, contracts: dict<counted>}
