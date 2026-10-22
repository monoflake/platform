/**
 * One block held to its brief, `mise run accept <package> [--from <revision>]`, its directory,
 * samples, todos, bindings and diff. Builds, lints and tests run after, `docs/code.md`.
 */
Tree.accept(Blocks.own(), Base.args->Array.slice(~start=2))
