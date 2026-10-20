# Signing

Facts on signed records and the shares a master is kept in, each with its source; see `README.md`.

## COSE, read 2026-10-19

**COSE names Ed25519 by -19, and the polymorphic `EdDSA`, -8, is deprecated.** RFC 9864, October
2025, registers fully specified algorithms: `Ed25519` -19 and `Ed448` -53, both recommended, and
marks `EdDSA` -8 "Deprecated", since an identifier covering two curves cannot be negotiated; WebAuthn
had worked around it by reading -8 as Ed25519 alone. Asked by checklist A11. Source:
https://www.rfc-editor.org/rfc/rfc9864.html

**D1 names no PRAGMA that makes a connection read only, and no authorizer.** Its compatible PRAGMA
statements are `table_list`, `table_info`, `table_xinfo`, `index_list`, `index_info`,
`index_xinfo`, `quick_check`, `foreign_key_check`, `foreign_key_list`, `case_sensitive_like`,
`ignore_check_constraints`, `legacy_alter_table`, `recursive_triggers`,
`reverse_unordered_selects`, `foreign_keys`, `defer_foreign_keys` and `optimize`; `query_only` is
not among them, and `EXPLAIN` is not named. Asked by checklist B21. Source:
https://developers.cloudflare.com/d1/sql-api/sql-statements/

**CWT keeps claim keys below -65536 for private use**, and has registered `scope` as 9, from OAuth,
and `sub` as 2, a text string; -256 to 255 take Standards Action, -65536 to -257 and 256 to 65535
Specification Required, and above 65535 Expert Review. Asked by checklist A11. Source:
https://www.iana.org/assignments/cwt/cwt.xhtml

## SLIP-39, read 2026-10-19

**SLIP-39 writes a Shamir share as words.** Its list holds exactly 1024 words, each with a unique
four-letter prefix, so a word carries 10 bits; a share of a 128-bit secret is 20 words and of a
256-bit one 33. The last three words are a Reed-Solomon checksum that detects any error in up to
three words, and misses a larger one with less than a one-in-a-billion chance; the spec advises
against correcting automatically. Thresholds are two-level, up to 16 groups of up to 16 members. The
master secret may be encrypted under a passphrase of printable ASCII, empty if none is given, and
nothing tells a wrong passphrase from a right one. Asked by checklist B12. Source:
https://github.com/satoshilabs/slips/blob/master/slip-0039.md
