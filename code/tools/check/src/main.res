/**
 * Runs s0's dimensions over the model, then the bootstrap path and the checklist, `docs/scope.md`.
 * `--s1` adds D4, `--ready[=N]` fails on an open row blocking that step, and a violation exits 1.
 */
Rules.run()
Roles.run()
Dimensions.run()
Load.run()
Copies.run()
Crossing.run()
Wire.run()
Cases.run()
Names.run()
Silence.run()
Code.run()
Workspace.run()
Kept.run()
Filed.run()
Sql_cost.run()
Recovery.run()
Derivations.run()
Base.shownInWork()
Base.process->Base.setExitCode(Base.failed.contents ? 1 : 0)
