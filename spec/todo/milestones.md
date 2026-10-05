# Milestones: the gateway

The agreed shape of the platform's work: what is being changed, in what order, and what each step
cannot start before. It moved here from the site's repository with the split; the site's own
milestones, A to D and F, are web's `spec/todo/milestones.md`, and E11 and E12 are carried out in
infra.

## E. The gateway

Every API moves behind one gateway Worker, reached by the hostnames in
platform's `spec/architecture/gateway.md`; what stands between here and there is
[gateway.md](gateway.md). Each step ships on its own, and none takes an address that answers today
away before its replacement answers.

| id  | milestone                              | what it is                                                                                                                                                                                                                                                                                                                                                                                                                                                 | after | horizon  |
| --- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- | -------- |
| E1  | The declaration                        | `[api.defaults]` and `[[api.routes]]` in `service.toml`, a schema `mise run scopes` holds them to, the richer table, service codes resolved in `libs/urls`                                                                                                                                                                                                                                                                                                 | --    | **done** |
| E2  | Hostnames read as profiles             | The profile table, a hostname read from the right, the provider and region registries, every request read into its tuple                                                                                                                                                                                                                                                                                                                                   | E1    | **done** |
| E3  | The gateway enforces the declaration   | CORS, the four lifetimes and crawling per route, and each host's `robots.txt`, `security.txt`, `favicon.ico` and path rule, derived; `policy.ts` retires                                                                                                                                                                                                                                                                                                   | E1 E2 | **done** |
| E4  | Services speak `/v{n}/`                | Every service routes on its version -- the CDN on `/v3/`, the rest on `/v1/` -- and `/v1/` is born in the shape the workspace's `addresses.md` gives, the unversioned path answering as it did until E8                                                                                                                                                                                                                                                    | E3    | **done** |
| E5  | The CDN and the alias layer move in    | Both become services behind the gateway by binding, their own CORS, stamps, host files and custom domains gone; `ill.li` and the old hosts become profiles                                                                                                                                                                                                                                                                                                 | E3 E4 | **done** |
| E6  | The new domains answer                 | `monoflake.com`, its twin `monoflake.net`, `ixc.one` and `symlink.si` bound to the gateway: DNS, routes, certificates                                                                                                                                                                                                                                                                                                                                      | E5    | **done** |
| E7  | The firewall is generated              | Each service-layer zone's whitelist written from the table, inside the expression and rule-count limits, and synced by `mise run rules sync`                                                                                                                                                                                                                                                                                                               | E2 E6 | near     |
| E8  | Callers move                           | `libs/urls` names the new hosts, every caller here follows, GitHub's webhook moves, the unversioned paths of E4 go                                                                                                                                                                                                                                                                                                                                         | E6    | **done** |
| E9  | `ffoni.com` leaves                     | Its profiles, its route and its rules folder deleted once nothing called it -- rdm's installed builds the last -- and nothing here naming the domain; the zone and the registration are the owner's to drop                                                                                                                                                                                                                                                | E8    | **done** |
| E10 | Limits are buckets, counted by `quota` | The bucket's arithmetic in `@monoflake/sdk/limits` and `burst` in every row; `quota` on Workers with its Durable Object and inside door; the gateway's own counter and the site's rate limiting bindings retire in favor of it. See platform's `spec/architecture/quota.md`                                                                                                                                                                                | E8    | **done** |
| E11 | The house has a gateway                | The gateway and `quota` deployed again on the node under Node, reached through Caddy's `inside` side; Caddy answering the gateway's hostnames on the LAN; services on Workers reached through the public gateway with `INTERNAL_TOKEN`; checked by address against the public one                                                                                                                                                                          | E10   | **done** |
| E12 | The house answers its own names        | infra's `apps/network/resolver`, CoreDNS rendered by host, answers the gateway's hostnames with the node and passes the rest down a chain that skips what fails; DHCP and the tailnet's split DNS point at it; the private suffix moves from `canmi.icu` to `internal.ixc.one`, whose certificate the zones' token can renew                                                                                                                               | E11   | **done** |
| E13 | Cleanup                                | A pass over what the move left behind, and what was found and held while it ran: host, which has no way to forget an app removed from the repository -- umami was forgotten by hand, its row deleted from host's store and host restarted so Caddy was rendered without it, its containers, network, image, data and snapshots removed over SSH; and the service domains' placeholder pages -- see [gateway.md](gateway.md), "An apex answers nothing yet" | E9    | mid      |

**E1 changes nothing a caller sees.** The declarations grow and the table with them, while the
gateway still answers as it does today; it is the step that makes the rest a matter of reading the
table rather than of writing rules.

**E4 answers both spellings for as long as anything sends the old one.** A node's service and the
gateway deploy apart, so a service that took the unversioned path away before the gateway put the
version in would break every call in between. The old path goes in E8, with the last caller.

**E4 is where the routes take their shape, because `/v1/` is new anyway.** A route that puts a
thing's identity in its query is reshaped as its first version is written, rather than as a second
version later; each one is studied again when it is taken, and its service and every caller of it
move together. The list found so far is [gateway.md](gateway.md)'s.

**E6 is work in Cloudflare's dashboard as much as in the repository**, and is the one step whose
order is forced from outside: a zone has to exist before a route or a rule can name it.

**Our own callers move in E8 like everyone else's.** They call the public hostnames from then on,
through the Tunnel and back, which costs a round trip and nothing else; E12 takes the round trip
away without any caller changing again.
