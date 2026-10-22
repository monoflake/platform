/**
 * One block's brief, `mise run brief <package> [--path]`, read from the model so none drifts from
 * what is checked, `docs/code.md`. `--path` prints its directory alone.
 */
Tree.brief(Blocks.own(), Base.args->Array.slice(~start=2))
