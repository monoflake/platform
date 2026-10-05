# Issues: the services

What the services' own files leave open. The rules over an entry are the index's; see
[issues.md](issues.md).

## Where the telemetry view goes

The platform's own page has nowhere settled to show what telemetry gathers -- see
[../architecture/platform.md](../architecture/platform.md).

## A second place shares `checks` with the first

A check's row is keyed by its id alone, so a probe on the VPS declaring the same checks would
overwrite the node's; the key gains `place` when the second probe is written -- see
[../architecture/probe.md](../architecture/probe.md).

## A picture is served at its id, to whoever holds it, for as long as it is kept

What it lacks is a place that issues a temporary file -- an address signed for a while and then
refused -- which `pictures/<id>.png` would give way to. Until one exists the route stays as it is;
see [../architecture/shot.md](../architecture/shot.md).
