# reserved-usernames

- **Upstream**: https://github.com/shouldbee/reserved-usernames, MIT, `LICENSE` here.
- **Version**: commit `0302214e8c1363fc5877ce3343ef6262e8852e96`, of 2021-07-14; the upstream has no
  tags.
- **Taken**: `reserved-usernames.json` and `LICENSE`, byte for byte. Not taken: the same list in
  CSV, PHP, SQL and text, `build.go` and the `Makefile` that write them, and `README.md`.
- **Consumed**: one of three sources the platform's reserved names are merged from, beside RFC
  2142's mailboxes and the platform's own words, RFC v7v3w. A name of it the platform's syntax
  refuses anyway, as one of two letters or with an underscore, is reserved by that syntax already.
- **Checked**: by nothing here; the list is data.
- **Upgraded**: cloned at a newer commit and the file copied again. The platform's reserved names
  only grow, so a name the upstream drops stays reserved.
