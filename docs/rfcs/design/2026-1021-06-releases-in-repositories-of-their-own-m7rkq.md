---
name: 'Releases in Repositories of Their Own'
title: "Where what the platform releases is built and published: a machine's NixOS in `monoflake/machine`, the runtimes' images in `monoflake/runtime`"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

The platform now has things to release that a machine fetches rather than builds: the runtimes'
images, workerd's and wasmtime's, one OCI archive for each architecture, RFC ge55b, and the
machine's own NixOS, today built on each machine it is installed on. Each follows a version of its
own, an upstream release or a NixOS release, so their tags in this repository would mix three
schemes, and ge55b leaves open who serves the URL an archive is fetched from.

## Decided

Decided by the author on 2026-10-21.

- **Two repositories of the organization's own, by what they release, named in lower case**:
  `monoflake/machine` and `monoflake/runtime`. Their code is kept off GitHub as far as it can be:
  they are there for what GitHub gives around a repository, its releases and its scheduled CI.
- **`monoflake/machine` is where a machine's NixOS configuration lives**, the configuration that
  makes a machine a host of the platform, since that is what the repository is named for; it
  follows this repository's changes and releases what changed.
- **`monoflake/runtime` holds no code of its own, only the images' build configuration**, and is
  glue: a scheduled run wakes, checks whether an upstream released, and, if one did, builds and
  publishes the images.
- **Both were prepared and checked locally first**, their CI written and run where it could be,
  and this repository's code keeps its copies until the author has reviewed the move. The author
  opened both on GitHub on 2026-10-21: `monoflake/machine` with its CI running, `monoflake/runtime`
  with its Actions turned off until its release is settled.
- **A runtime's image is published twice**, decided by the author on 2026-10-21: as a release
  asset of `monoflake/runtime`, the archive a driver fetches, RFC ge55b, and on Docker Hub as
  `canmi/workerd` and `canmi/wasmtime`, for whoever pulls it by hand. Docker Hub takes no new
  organization without a paid plan, so the images stand under the author's own account.
- **One build makes both**, decided by the author on 2026-10-22: each architecture is built once,
  its OCI archive written and its image pushed to Docker Hub by digest from the same build, so the
  two hold one manifest; the image is then tagged as its version and `latest` over both digests.
  The release is drafted with its archives and manifest and published last, so its tag, which a
  later run reads as released, stands only for a release whose assets are all up. An asset is
  named `<runtime>-<version>-linux-x86_64.tar`, the workspace's `docs/naming.md`.
- **A release is a UTC day**, decided by the author on 2026-10-22: it is named and titled by the
  day alone, `2026.10.22`, each part padded so the names sort by their text as by date, and holds
  only the versions new that day. Its notes are a table, a row a version: upstream's release of it,
  upstream's commit short, and its image linked to its tag on Docker Hub. It carries one
  `manifest.json`, each version listed with the commit here that built it, upstream's tag and
  commit, and each archive's size, SHA-256 and image digest. A later run the same day adds its
  versions' archives and rows, then merges its entries into the manifest and uploads it last, so a
  version counts as released once a published release's manifest lists it.
- **Docker Hub's readme and description follow GitHub's**, decided by the author on 2026-10-22:
  each run writes this repository's README and description over both images' on Docker Hub, with
  the one token the push takes, since a second token in the same repository leaks with the first.
- **Docker Hub is reached by an access token in a repository secret**, `DOCKERHUB_TOKEN`, decided
  by the author on 2026-10-22: Docker Hub's OIDC connections for GitHub Actions serve paid
  organizations alone, so a personal account takes a token.

## Open

Proposed by the agent on 2026-10-21, not yet confirmed:

- An upstream release is taken once it is past the workspace's release delay, as `pins` takes
  workerd's today, so the scheduled run in `monoflake/runtime` keeps the same rule.
- Whether anything changed is judged by what would be built, a system's output path or an image's
  pinned versions and base digests, never by a diff of source, so a comment changed releases
  nothing.
- GitHub disables a scheduled workflow after 60 days without a commit, so a run started by
  `repository_dispatch` from this repository's CI may be the main trigger and the schedule a
  fallback.
- A binary cache of the machine's NixOS, so a machine downloads its system rather than building it,
  cannot be a release asset; where it is kept, an object store with Nix's signing key, is open.
- When the machine's configuration moves, `model/` must know a block written in another
  repository, as cloud fills a role, and cloud's machines take their module from
  `monoflake/machine`.
