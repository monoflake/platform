# The HTTP surface

What a client of grok2api sees. How the answers are produced is [bridge.md](bridge.md).

## Three API shapes: Chat Completions, Responses and Messages

These are the shapes clients are written against. Chat Completions is what nearly every client
and SDK speaks; Responses is OpenAI's newer one, and the only one Codex speaks; Messages is what
Anthropic's SDKs and the tools built on them speak. All three are answered by the same sessions: a
conversation begun in one shape continues in another, because each parses to the same messages
and the session is keyed on those.

- `POST /v1/chat/completions`, `POST /v1/responses` and `POST /v1/messages`, each streamed and not.
- `GET /v1/models` and `GET /v1/models/{id}`, the models the resident agent offers. The list is
  read from the agent, not written down here, because the subscription decides it and it
  changes: the same account showed two models before signing in and four after. A request
  carrying `anthropic-version`, which Anthropic's SDKs send on every call, gets Anthropic's
  shape; any other gets OpenAI's.

The key is accepted as `Authorization: Bearer` or as `x-api-key`, the header each family of SDKs
sends. Errors take the shape of the API the request spoke.

## Responses: state by id, reasoning by request

Responses lets a client continue by naming the response it continues, `previous_response_id`,
instead of sending the conversation again. That is the session the reply came from, so it is
served the same way (sessions.md); an id no idle session holds -- expired, or never made -- is a
400 naming it, as OpenAI answers an unknown one. A client that sends the whole conversation, as
Codex does with `store: false`, is matched like any other.

Reasoning comes back as a `reasoning` item's summary only when the request set
`reasoning.summary`, as OpenAI returns it. `reasoning.effort` is passed on, with `none` and
`minimal`, below the CLI's lowest level, read as `low`. A response the agent stopped for length is
`incomplete` with `max_output_tokens`, not `completed`.

## Structured output is the CLI's own

A request may constrain the answer to a JSON Schema: `response_format` with `json_schema` (or
`json_object`, any object) in Chat Completions, `text.format` in Responses, `output_config.format`
or the older
`output_format` in Messages. The schema is passed to the agent as the prompt's
`_meta.outputSchema`, the ACP side of the CLI's `--json-schema`, and the answer is JSON matching
it. It is a constraint the CLI enforces, measured to hold, rather than an instruction in the
prompt that the model may or may not follow.

## Anthropic's thinking and effort

Messages returns reasoning as a `thinking` block only when the request turned thinking on
(`thinking.type` `enabled` or `adaptive`), as Anthropic does; its `signature` is empty, because
the CLI has none to give. The effort is `output_config.effort` where given, `max` read as the
CLI's `xhigh`; otherwise a thinking budget is read as a level -- under 4096 tokens low, under
16384 medium, above that high -- since the CLI takes levels, not budgets.

Anthropic counts `input_tokens` without the cached part and reports that part beside it; OpenAI
counts it within `prompt_tokens`. Each shape gets its own convention from the same numbers.

## Chat Completions returns reasoning as `reasoning_content`

The agent streams its reasoning as `agent_thought_chunk`. grok2api returns it rather than dropping
it, in the `reasoning_content` field beside `content` -- on the message when not streaming, on the
delta when streaming. The field is not in OpenAI's schema; it is the convention DeepSeek
established and that most clients which show reasoning already read. A client that does not know
it ignores it.

## Function calling is not supported

The agent executes its own tools; it has no way to hand a tool call back to the caller and wait
for the result. Emulating that through prompting and parsing was judged too fragile to start
with, so the `tools` and `tool_choice` parameters are not supported -- and, like every parameter
the next section covers, they are ignored rather than refused.

## What cannot be honored is ignored, except `n`

The agent exposes no temperature, `top_p`, output limit, stop sequences, penalties or seed, and
no tools of the caller's. A request carrying any of them is answered as if it did not: the
parameters are dropped without an error. Clients send most of these by default, and refusing
them would refuse most clients for settings that rarely change an answer's use.

`n` greater than 1 is the exception and is refused with a 400. It asks for a different response
shape -- several choices -- and answering with one would be a wrong answer rather than an
approximate one.

## Images arrive inline, and only so

An `image_url` content part whose URL is a `data:` URL, or a Messages `image` block whose source is
`base64`, is decoded and sent to the agent as an `image` block, which the model sees
([bridge.md](bridge.md), "Images reach the model"). An image by any other URL or source is
refused. grok2api does not fetch URLs on a caller's behalf: that
would make it an open fetcher sitting on a server, reaching whatever address a request names.

## What a request must be

A request is refused, rather than approximated, where its messages cannot be answered as sent:

- **The last message is the user's.** The last message is what the agent is prompted with; an
  assistant message last would be a prefill, which the agent has no way to take.
- **No `tool` messages.** They carry results of calls grok2api never made
  (see "Function calling is not supported").
- **A model the agent offers**, or none, which means the agent's default. An unknown model is a
  404 with the code `model_not_found`, as OpenAI answers it, because a client that named a model
  it cannot have should be told rather than served another one.

`system` and `developer` messages, wherever they sit, together form the system prompt a session
is created with; `developer` is the newer name for the same role.

## Every interface, one port, one key

The server listens on all addresses on one configured port, because it runs on a server and is
reached from elsewhere ([deployment.md](deployment.md)). Every request must carry one configured
API key as `Authorization: Bearer <key>`; a request without it, or with another, is refused. One
key, not a key store: this is one person's proxy.
