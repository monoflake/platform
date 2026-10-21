/***
 * The pins tool, `model/graph/tools.res`: what an image pins by hand, workerd's version and its
 * download's hash for each architecture in `code/substrate/driver/machine/images/workerd/Dockerfile`,
 * moved to the newest release past the workspace's supply-chain delay, and the NixOS release newer
 * than the one the root's `flake.nix` follows named. `node src/main.res.mjs <Dockerfile>
 * <pnpm-workspace.yaml> <flake.nix> [--dry-run]`, as platform's `update` runs it, reads the
 * registry, hashes each download, reads the remote's heads and writes the file; what it decides is
 * here, and touches nothing. The model's interface, `docs/code.md`.
 */

/** A version the registry published, and when, in milliseconds since the epoch. */
type published = {version: string, at: float}

/** A package's document in the npm registry, read: its `latest` tag and every version published. */
type registry = {latest: string, published: array<published>}

/** The registry's document, as `https://registry.npmjs.org/<package>` serves it. */
let registry: string => result<registry, string>

/** The delay in minutes that `pnpm-workspace.yaml`'s `minimumReleaseAge` gives, in its text. */
let delay: string => result<int, string>

/**
 * What a move takes: the newest version, by when it was published, no newer than `latest` and
 * published at least the delay before now, if any is; and the newer ones held back, newest first.
 */
type chosen = {take: option<string>, held: array<string>}

let choose: (registry, ~delay: int, ~now: float) => chosen

/**
 * A pin as the Dockerfile writes it, each an `ARG` with its default: the version,
 * `WORKERD_VERSION`, and each architecture's download's SHA-256 in hex, as `ADD --checksum` takes
 * it, `WORKERD_SHA256_AMD64` and `WORKERD_SHA256_ARM64`, keyed by Docker's architecture, `amd64`
 * and `arm64`, whose packages npm names `workerd-linux-64` and `workerd-linux-arm64`.
 */
type pin = {version: string, hashes: dict<string>}

/** The pin in the Dockerfile's text: one version `ARG`, and one hash `ARG` per architecture. */
let read: string => result<pin, string>

/** The Dockerfile's text with its pin replaced, every other byte as it was; refused where the pin's
 * architectures are not the file's. */
let write: (string, pin) => result<string, string>

/** The NixOS release branch, `nixos-YY.MM`, that `flake.nix`'s `nixpkgs` input follows, in its text. */
let follows: string => result<string, string>

/**
 * The newest NixOS release branch, `nixos-YY.MM`, among the heads `git ls-remote --heads` lists of
 * nixpkgs in its text, if it is newer than the one the flake follows: what waits beyond the bounds.
 */
let release: (string, ~follows: string) => option<string>
