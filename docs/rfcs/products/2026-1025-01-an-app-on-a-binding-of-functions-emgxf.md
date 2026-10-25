---
name: 'An App on a Binding of Functions'
title: 'What an app is on a binding whose driver offers functions and objects and no container'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

The control's `releases.deploy` deploys an app into a container item it asks of the binding's
driver, made where the binding holds none, `code/products/control/src/api/deploying.res`. A binding
whose driver offers the function and object kinds alone, as driver(cloudflare) does on a Cloudflare
account, has no container to give, so no app can be deployed onto it. What is an app there, and
what does `releases.deploy` ask of such a binding.

## Options

- Whether an app on such a binding is a deployment of the function kind directly, with no
  container item, its Worker named by the app's id.
- Whether `releases.deploy` chooses the kind by what the binding's driver offers, or by what the
  release's form asks, and what it answers where neither fits.
- What the gateway hands a function's Worker, which an entry does not front.

## Evidence

- On 2026-10-25 hello was deployed through a control onto a binding of driver(cloudflare) offering
  `function,object`, right after that driver's install. The control drew the app's id and the
  driver refused the list: `beyond_host: app 23f191e8, item 1: a Worker's account holds no
  container or volume`. Nothing was made on the account, and the app's row stays with no container
  until releases can forget it.
- The previous control asked the same container item, so this is not the bare ids' doing.
- driver(cloudflare) deploys a function as a Worker of its own, monoflake/driver's RFC nrs5v; the
  control's app path never asks that kind.
