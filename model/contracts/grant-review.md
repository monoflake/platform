# Grant review

The contract is `roles/deployment_grants.res`; `grants/grant_policy.res` simulates both fixed policies.
This is model evidence only. No control implementation or credential was made.

| Operation | Allowed caller                                     | Refuses                                                                                                              |
| --------- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| mint      | Operator, by the control's present operator bearer | Deploy needs an existing initialized app; both policies need finite future expiry; every other caller                |
| revoke    | Operator, by that bearer                           | Unknown grant id, every other caller                                                                                 |
| upload    | Live deployment grant                              | Oversize, invalid archive, non-Modules form, policy overrides, digest mismatch, other grant's staging                |
| deploy    | Live deployment grant                              | Missing or expired staging, other grant's artifact, stale/concurrent version, policy change, uninitialized resources |
| health    | Live health grant bound to this control            | Wrong control or policy, invalid verifier, expired or revoked grant, every other caller                              |
| status    | Live deployment grant                              | Another app or policy, expired or revoked grant; output has no secrets                                               |

Every operator operation refuses both grant policies, including organizations.open, bindings.open,
and releases.put/deploy/describe/forget/retire. Organization and host credentials authorize none
of these six operations. A grant never enters account `credential`, certificates or capabilities.
The fixed caller gate decodes first, looks up callers, and checks only the presented proof kind;
failure never falls through. Public operations still pass without reading proofs under 6x8su.

Mint generates 32 random bytes and returns them once. The distinct wire bearer is
`dg1.<grant-id>.<base64url-secret>`; its identifier is opaque text. The stored verifier is SHA-256
of the entire bearer, with id, expiry, revoked state and the fixed policy, never the bearer.
Only the operator can change the revoked state. Revocation takes effect without a cache delay.
Expiry and revocation are checked before upload and again before storing bytes or committing deploy.
Rotation mints a new id and revokes the old one; it changes no operator or runtime key.
Decided by the author on 2026-11-02, both policies refuse expiry beyond 180 days from mint time.
Health uses this same mint, revoke, bearer format, verifier and expiry. Its stored policy binds
A's own control identity and health alone. Health grants fail upload/deploy/status and all operator
operations; deploy grants fail health. Health takes only a 32-byte nonce and echoes it with ready
or unavailable after initialization and a minimal read-only store check. No other data is returned.
Nonce replay is allowed for this read-only check; each call authenticates and checks readiness anew.
No response caching, redirects, driver access or underlying error details; requests are rate bounded.

Mint selects exactly deploy or health. Deploy resolves app, organization, binding, ingress and secrets.
Form is Modules and network is [http]. Upload/deploy/status accept no app, binding, organization,
ingress, network, secret, kind or URL selector. Unknown selectors fail decoding as malformed.
Archive metadata is validated against that same fixed policy, including ingress and kinds.
Staging is content-addressed and grant-owned, bounded to 32 MiB, and expires at the earlier of
grant expiry and one hour after upload. Bytes and digest are validated before storage and deploy.
Deploy retains existing server-held secrets; status returns only app, digest, version and candidate.
No storage is opened and no credentials are replaced. Missing resources require Mac bootstrap.
App updates serialize, compare and increment a monotonic version at commit, and refuse stale work.
Commit audits grant id, digest, previous/new version and all four candidate commits atomically.
Candidate commits are full lowercase 40-character SHAs. Deploy authority includes running code
with the app's retained runtime secrets and privileges.

A deploy writes a durable intent, digest, candidate and time, before its driver call. Only a definite
outcome clears it: the driver refused, or the commit recorded. Once a driver answers success the effect
is recorded, whatever became of the grant meanwhile. An intent past five minutes is reconciled against
what the driver runs; a grant caller finding no definite answer is answered unavailable, and an operator
clears it with a log line and goes on, so a dead machine never holds an app.
A staged artifact is read only with a fetch token made at upload and handed to the driver in its address,
and is refused once expired or revoked. A grant holds four live staged artifacts at most. Staged bytes go
at a recorded deploy, a revoke or a retire, and expired ones as uploads, mints and revokes sweep.

Decided by the author on 2026-11-02: verifier state lives in A's control's own database; staging is
32 MiB and one hour; the deployment version rises at every commit, a repeated digest included; status
may return the bound app's id. Mint and revoke take the control's present operator bearer from the
Mac and do not wait on the signed operator; item caller-gate moves them to the signature.

The shared runner cannot inject lifecycle observations or malformed inputs. Model-local samples
retain case/step/expect form and use Conforms plus policy simulation; live runner support waits.
