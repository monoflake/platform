---
name: 'How Stale a Footing Read May Be'
title: "What a reader caches of a bundle and how soon it sees a newer one, and how long a footing's read may be stale"
status: draft
supersedes: []
blocked-by: []
commits: []
references:
  - url: https://developers.cloudflare.com/d1/best-practices/read-replication/
    took: "that a read from D1's replicas needs a session's bookmark to see what was written"
---

## Question

Left open by RFC n8jq5.

What a reader caches of a bundle, and how soon it sees a newer one, stays C36's. How long a read
may be stale, given D1's read replicas need a session's bookmark, `docs/lessons/cloudflare.md`, is
for when the footing Worker is written.
