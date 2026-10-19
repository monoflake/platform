# blueprint

The paper model of the platform's next architecture: the design worked out from what an app needs
down to what the real world already provides, checked by a model, before any of it is compared with
the code that exists or built.

It is local only. It has no remote, is not in the workspace's `repos.toml`, and is never pushed until
the design lands, so nothing here triggers a deployment or touches another repository.

```
rfcs/        the design, one draft per question, numbered by layer
model/       the parts and their edges, the contracts, and the checks run on them, in ReScript
scope.md     what the model covers in its current version, and what it leaves out
lessons.md   facts taken from the old system, each with its source
spec/        how work here is done
vendor/      other projects' files, copied at one version and left as written
```

The model is ReScript, and its tasks are mise's, its tools the workspace's. After `pnpm install`,
`mise run check` compiles it and runs `model/check.res`, and `mise run check --ready` asks whether
building may begin; `mise run fmt` formats, and `mise run verify` is what a commit passes.
