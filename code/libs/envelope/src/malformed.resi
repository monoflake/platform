/***
 * Why a value was not read as its type, envelope*'s one type of its own, beside the `Contracts`
 * envelope-generator writes as `docs/envelope.md` lays out. The model's interface, `docs/code.md`.
 */

/**
 * A step from a value into what it holds, a field by its name, an item by its index or an entry by
 * its key.
 */
type step = Field(string) | Index(int) | Key(string)

/**
 * Why a value was not read as its type, answered as `malformed`, RFC fhg6w, by where it stands and
 * what was expected there.
 */
type t = {at: array<step>, expected: string}
