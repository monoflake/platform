/** What every interface answers alike, an error with its failure and its reason, RFC vr5lw. */
open Subset

/** The reasons every operation may fail for, which no operation declares again, ge55b. */
let common: array<reason> = [
  {name: "denied", failure: #rejected},
  {name: "malformed", failure: #rejected},
  {name: "overloaded", failure: #unavailable},
  {name: "rate_limited", failure: #unavailable},
  {name: "fault", failure: #unknown},
]

/**
 * The reasons a call to what is deployed may fail for, the platform's own before the app's code is
 * reached, vr5lw.
 */
let calling: array<reason> = [{name: "stopped", failure: #unavailable}]

/** Each reason's default message by its name, one objective line of English, RFC ge55b. */
let messages: dict<string> = dict{
  "denied": "The call carries no credential, or one that does not allow it",
  "malformed": "The call is not as its interface writes it",
  "overloaded": "The implementation is busy for a moment; try again",
  "rate_limited": "The caller is calling faster than it is let; slow down",
  "fault": "The implementation failed while answering",
  "stopped": "What was called is stopped",
  "ahead": "The generation asked for is ahead of the one held",
  "behind": "No generation as new as the one asked for is held yet",
  "beyond_allowance": "The change asks for more than the allowance gives",
  "beyond_host": "The host cannot give what is asked",
  "beyond_limit": "The statement goes past a limit of the database",
  "beyond_range": "A value is beyond the range its column holds",
  "beyond_window": "The moment asked for is outside the window kept",
  "call_cycle": "The calls the change declares form a cycle",
  "calls_unmatched": "A call the change declares matches no export",
  "constraint": "The statement breaks a constraint of the database",
  "depended_on": "Something else depends on what the change removes",
  "expectation_failed": "What is held is not what the call expected",
  "extension_invalid": "The extension named is not valid here",
  "gap": "The frames asked for are no longer all held",
  "hash_mismatch": "What was fetched does not match its hash",
  "held": "The lease is held by another until it ends",
  "invalid": "The input is well formed but not valid",
  "no_export": "No export of that name is deployed",
  "no_kind": "No kind of that name exists",
  "no_sandbox": "No host offers the sandbox asked for",
  "not_a_bucket": "No bucket of that name exists",
  "not_dismissible": "The warning cannot be dismissed",
  "not_found": "Nothing of that name or id exists",
  "not_granted": "The grants do not give what is asked",
  "not_permitted": "The space does not permit what is asked",
  "not_retiring": "The key named is not being retired",
  "quota_exceeded": "The write would go past the quota",
  "read_only": "The database is read-only for now",
  "role_refused": "The role asked for is not one the caller may hold",
  "size_differs": "The size written differs from the size declared",
  "stale": "What the call was based on has changed since",
  "still_asked": "The binding still asks for capacity",
  "still_running": "The deployment is still running; stop it first",
  "storage_full": "No store has room for the write now",
  "suspended": "The organization is suspended",
  "too_large": "The input is larger than its bound",
  "unfetchable": "The artifact could not be fetched",
  "unplaceable": "No store meets the placement asked for",
  "unresolved": "A handle in the change resolves to nothing",
  "wrong_offset": "The write does not start where the upload ends",
  "wrong_type": "The bucket is not of the type the call needs",
}

let types: array<declared> = [
  {
    name: "failure",
    def: Enum({choices: codes(["rejected", "unavailable", "unknown"]), ordered: false}),
    from: "49qyg",
  },
  // A reason is one its operation declares; a message is for a person, and nothing acts on it,
  // always written, its reason's own in `messages` unless the moment says more, ge55b.
  {
    name: "error",
    def: Record([
      field("failure", 1, Type("failure")),
      field("reason", 2, Prim(#string)),
      field("message", 3, Prim(#string)),
    ]),
    from: "vr5lw",
  },
]
