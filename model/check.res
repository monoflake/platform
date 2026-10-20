/**
 * Runs s0's dimensions over the model, `docs/scope.md`: D0 serve, D1 bootstrap, D2 restart, D3 upgrade
 * and D5 contract, each printing its question, every violation, and every assumption -- an edge to
 * a boundary whose contract is written -- and then the bootstrap path, RFC 94y0d, and the
 * checklist. D4 recovery models a failure, so it is s1's, and runs only with `--s1`. With
 * `--ready`, or `--ready=N`, the checklist fails while a row that blocks step 0, or step N, is
 * open, or an open question names no row. Exits 1 when any dimension finds a violation.
 */
Rules.run()
Dimensions.run()
Path.run()
Load.run()
Wire.run()
Names.run()
Words.run()
Tree.run()
Code.run()
Kept.run()
Filed.run()
Recovery.run()
Base.process->Base.setExitCode(Base.failed.contents ? 1 : 0)
