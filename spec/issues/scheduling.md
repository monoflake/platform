# Issues: scheduling and apps

What placing apps and their state leaves open. The rules over an entry are the index's; see
[issues.md](issues.md).

## How the platform deploys an app's Worker

The platform, not Cloudflare's connection to a repository, is to deploy each app's Worker. Either
it uploads the bundle CI built through Cloudflare's Workers Scripts API with a token of its own --
free, and the same shape as host taking an image a run built -- or it uses Workers for Platforms,
made for a platform deploying others' Workers into a namespace it dispatches to, which starts at a
monthly fee. Undecided.

## How a Worker at the edge reaches Postgres on the nodes

A stateless Worker in any of Cloudflare's locations asking one Postgres on a node pays the distance
on every query. Workers VPC carries TCP, so a Worker can connect directly; Hyperdrive pools and
caches connections in front of a private database reached the same way. Which, and what is cached
at the edge, is undecided until a query is measured.

## The order the site leaves D1

The site's API keeps everything in D1 today. Moving it to the platform's Postgres is the largest
step of the site becoming an app on the platform; what moves first, and how the two run side by
side while it does, is undecided.
