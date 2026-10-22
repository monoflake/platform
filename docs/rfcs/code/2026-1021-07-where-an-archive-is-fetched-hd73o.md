---
name: 'Where an Archive Is Fetched'
title: "Whether a registry replaces an image's archive, and who serves the URL an archive is fetched from and how a fetch is authenticated"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC ge55b.

Whether a registry replaces the archive later, and then whether `hash` becomes a manifest's digest,
is C11's with the image's format. Who serves the URL an archive is fetched from, and how a fetch is
authenticated, is not decided; the author raised on 2026-10-21 a repository of the organization's
own for releases, the images and the machine's NixOS among them.
