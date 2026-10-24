/***
 * The samples' fixtures, each `tests/fixtures/<name>/fixture.json` built from its source in this
 * block's `fixtures/<name>/`, and the manifest a run serves them by, RFC p8e8k.
 */

/** A fixture built, the file it is served as, its form, its hash and an image's architecture. */
type built = {form: string, file: string, hash: string, architecture: option<string>}

/** A file made where the fixtures are served, another's bytes followed by zeros to a size. */
type padded = {file: string, from: string, size: float}

/**
 * What a build made, each fixture by its name, every file it wrote, each file to pad where they are
 * served, and why any fixture was not built.
 */
type manifest = {
  built: dict<built>,
  files: array<string>,
  padded: array<padded>,
  unbuilt: dict<string>,
}

/** The file a manifest is written as, in the directory beside what it names. */
let manifestFile: string

/**
 * JavaScript modules as the function kind takes them, a tar of `metadata.json` naming the main
 * module and then each module by its name.
 */
let bundle: (~main: string, array<(string, Uint8Array.t)>) => Uint8Array.t

/**
 * An OCI image layout archive of one program, run as its command at `/` and listening on a port,
 * for an architecture as OCI names it.
 */
let image: (~program: Uint8Array.t, ~architecture: string, ~port: int) => Uint8Array.t

/**
 * Every fixture built into a directory, its manifest written beside them, a padded one past a bound
 * by its value and an image for the architecture given.
 */
let build: (~into: string, ~bounds: dict<float>, ~architecture: option<string>) => manifest

let toJson: manifest => JSON.t

/** The manifest a text holds, or why it holds none. */
let read: string => result<manifest, string>

/**
 * A fixture by its name as served at an address, a file's name joined to it, or why the run
 * offers none.
 */
let served: (manifest, ~at: string) => string => result<Run.fixture, string>
