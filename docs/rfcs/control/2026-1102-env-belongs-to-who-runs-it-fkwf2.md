---
name: 'Env Belongs to Who Runs It'
title: "A deployment's env is held by the vendor or machine driver that runs it, never a control"
status: decided
supersedes: []
references: []
---

## Question

A deploy lists the secrets it hands its driver, and a control keeps none, RFC emgxf. A deploy made
under a grant is asked to replace an app's build without its caller holding the app's secrets. Who
holds a deployment's env, and what does a deploy that lists no secret mean?

## Options

- The runner holds it, a vendor or the machine driver, and a deploy names only what it changes.
- A control keeps the secrets and sends them with each deploy, so a grant can deploy with none in
  hand. A control then holds what it was built never to hold.
- Every deploy lists every secret, as the Cloudflare driver uploads today. A grant then has to carry
  the app's secrets, or cannot deploy an app that has any.

## Decision

Decided by the author on 2026-11-02. A deployment's env belongs to whoever runs it, a vendor or the
machine driver, and never a control. Cloudflare Workers and Vercel both hold env apart from a
deployment, so the machine driver comes to hold it the same way.

`secrets` in `deployment-deploy`, what a control sends a driver, becomes optional, as it already is
in `release-deploy`, what a caller sends a control. Absent, the runner keeps what it holds; a name given sets that
name alone, and the rest stay. Removing a name is a later operation. A control sends no secretless
deploy to a driver too old to keep them, since that driver would drop what the app holds. Config
apart from secrets waits until a contract needs it.

Plan item env-kept-by-runner holds the work.
