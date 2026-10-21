/***
 * The pins tool, `model/graph/tools.res`, moving workerd's pin past the supply-chain delay and
 * naming a newer NixOS release. The model's interface, `docs/code.md`.
 */

/** A version the registry published, and when, in milliseconds since the epoch. */
type published = {version: string, at: float}

/** A package's document in the npm registry, its `latest` tag and every version published. */
type registry = {latest: string, published: array<published>}

/** The registry's document, as `https://registry.npmjs.org/<package>` serves it. */
let registry: string => result<registry, string>

/** The delay in minutes that `pnpm-workspace.yaml`'s `minimumReleaseAge` gives, in its text. */
let delay: string => result<int, string>

/**
 * What a move takes, the newest version no newer than `latest` and past the delay, and the newer
 * ones held back.
 */
type chosen = {take: option<string>, held: array<string>}

let choose: (registry, ~delay: int, ~now: float) => chosen

/**
 * A pin as the Dockerfile writes it, `WORKERD_VERSION` and each architecture's SHA-256 as `ADD
 * --checksum` takes it.
 */
type pin = {version: string, hashes: dict<string>}

/** The pin in the Dockerfile's text, one version `ARG` and one hash `ARG` per architecture. */
let read: string => result<pin, string>

/** The Dockerfile's text with its pin replaced, every other byte as it was; refused where the pin's
 * architectures are not the file's. */
let write: (string, pin) => result<string, string>

/** The NixOS release branch, `nixos-YY.MM`, that `flake.nix`'s `nixpkgs` input follows. */
let follows: string => result<string, string>

/**
 * The newest NixOS release branch in `git ls-remote --heads`'s text, if it is newer than the one
 * followed.
 */
let release: (string, ~follows: string) => option<string>
