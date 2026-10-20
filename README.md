# blueprint

The paper model of the platform's next architecture: the design worked out from what an app needs
down to what the real world already provides, checked by a model, before any of it is compared with
the code that exists or built.

It is local only. It has no remote, is not in the workspace's `repos.toml`, and is never pushed until
the design lands, so nothing here triggers a deployment or touches another repository.

```
model/         the spec: the graph, the ground, the bootstrap path, the contracts, and the checks
  contracts.json   the product every language reads
code/          the code, cut where the model is: parts/<half>/<part>, libs/, tools/
docs/          what is read: rfcs/, the drafts; lessons/, facts with their sources; method.md;
               scope.md, what the model covers
vendor/        other projects' files, copied at one version and left as written
```

No directory holds more than 16 entries or lies more than 5 deep, counted from a top-level directory
or a package's root, `docs/method.md`; the check holds both.

The model is ReScript, and its tasks are mise's, its tools the workspace's. After `pnpm install`,
`mise run check` compiles it and runs `model/check.res`, and `mise run check --ready` asks whether
building may begin; `mise run fmt` formats, and `mise run verify` is what a commit passes.
