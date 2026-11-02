---
name: 'What WIT Leaves Open'
title: "What wit* chose where RFC kd7f9 is silent: a world's imports, a call's name, a parameter held exactly, a record's fields by name, what else of WIT is refused, an option within an option, and how a file is read"
status: draft
supersedes: []
blocked-by: []
commits: []
references:
  - url: https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md
    took: 'the grammar the subset is read by, its tokens, keywords, labels and name resolution'
---

## Question

Left open by RFC kd7f9. Each is built as proposed here, in `code/libs/wit`, held to `tests/wit/`;
a decision either way changes the library and its samples, never the shape of `read`, `exports`
and `matches`.

Open, for the discussion that follows:

- **A world's imports are the calls it makes.** The subset names a world exporting; a caller's call
  is matched by its types, so a world also takes `import` of an interface of its file or of a
  function, `import name: func(...)`, and a call names one of them. A `use` is taken in a world as
  in an interface, so a world's own function can name a type. [C41]
- **A call's name.** A world's own function is `{function}`, as a manifest's `exports` and `calls`
  name one today; an interface's is `{interface}.{function}`, which no label holds and which stands
  in `POST {address}/{export}` unescaped, where the component model's `#` would not. [C41]
- **A parameter's type is held exactly.** RFC kd7f9 matches a parameter by its type and a result
  by every case the export names being one the caller holds. So a parameter's variant, enum or
  flags must have the same cases on both sides, though a caller holding fewer is as safe. [C41]
- **What no match compares.** A type's name, a parameter's name and a record's order of fields,
  since a value is written by its fields' and its cases' names, RFC vr5lw. Both payloads of a
  shared case are compared, and a result's `success` and `failure` are its two cases. [C41]
- **What else of WIT is refused, by a word for it.** Beside the constructs kd7f9 names, the reader
  refuses `map`, `future`, `stream`, `async`, a gate and `@external-id`, a nested package or a
  package's nested name, a fixed-length list, a type defined in a world, an inline interface, an
  interface imported or exported under a name of its own, and a top-level `use`. A world is asked
  exactly once: none is refused where the file ends, a second where it is named. [C41]
- **An option within an option is refused as the WIT is read**, at the outer `option`, aliases
  followed. RFC vr5lw refuses it as a deployment is made, and reading is where that is. [C41]
- **How a file is read.** Every refused construct is read through, so all are named; a token out of
  place ends the reading, since what follows it cannot be read reliably. A name is checked unique
  as written, where the component model holds an export's names unique regardless of case. A
  column counts code points. A file with no `package` line is read, as WIT.md allows, though
  wit-parser asks for one of a file resolved alone. [C41]
- **What a manifest's `exports` adds.** `exports` answers what the world exports; whether each of a
  manifest's `exports` must be one, and which of them a dependency's caller may call, is the
  control's, which hands `matches` the exports it allows. [C41]
