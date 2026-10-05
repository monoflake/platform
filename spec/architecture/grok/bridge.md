# The bridge to Grok

grok2api serves an OpenAI-shaped HTTP API whose answers come from the Grok Build CLI, so the
requests draw on the CLI's subscription rather than on a metered API key. This file is how the
CLI is driven. What the HTTP side looks like is [api.md](api.md); how a conversation maps onto the
CLI's sessions is [sessions.md](sessions.md).

Everything measured here was measured against grok 1.0.41, on 2026-09-27.

## Grok does the authentication, never this program

The CLI signs in, stores its credentials, refreshes them and attaches them to every request.
grok2api starts the CLI and talks to it; it never reads a token, never calls an OAuth endpoint
and never writes a credential. The point is that the CLI's own sign-in is a supported path whose
maintenance belongs to xAI -- a proxy that did the OAuth itself would own a reverse-engineered
flow that breaks on their schedule.

Under the CLI, requests go to `https://cli-chat-proxy.grok.com/v1/responses`, the Responses API,
with the signed-in session as a bearer token. That endpoint is an observation, not an interface:
nothing here calls it.

## One resident agent, spoken to over ACP

The CLI runs as `grok agent stdio`: one long-lived child process speaking the Agent Client
Protocol, JSON-RPC 2.0 with one message per line, on stdin and stdout. Every HTTP request becomes
work on a session inside that one process.

The alternative was a `grok -p` process per request, which the CLI's own documentation shows
wrapped as an OpenAI API. It was rejected on what the resident agent measured:

- `initialize` answers in 0.1 s, so the cost of a request is the model's, not a process start.
- Several sessions run concurrently in one process: three parallel prompts took 2.6 s of wall
  time against 1.5 to 2.6 s each.
- A session keeps its conversation, which is what makes the session reuse in
  [sessions.md](sessions.md) possible, and with it the prompt cache.
- Replies stream as they are produced -- `agent_message_chunk` for text, `agent_thought_chunk`
  for reasoning -- and the first chunk arrived 1.2 to 1.8 s after the prompt.

`grok -p` is not a different engine: it is an ACP client of the same agent, run in-process. So
nothing is lost by speaking ACP directly, and the headless flags have ACP equivalents or none.

Model and reasoning effort are per session, set with `session/set_config_option`; the options
and their values come from the `session/new` response rather than from a list kept here.

## The agent is a coding agent, and most of the work is taking that away

The CLI assembles a coding agent's context around every prompt. Measured on a machine with a
Claude Code setup, a prompt of "Reply with exactly: pong" cost 24k input tokens, almost none of
them the prompt:

- the agent's own system prompt and its full tool set;
- every skill it can find, 102 of them, including `~/.claude/skills`;
- the instruction files it finds, including `~/.claude/CLAUDE.md`;
- Claude Code's installed plugins, **with their hooks**, which would then run on every request;
- the user's MCP servers;
- a second model call per session to write a session title.

grok2api therefore owns a **clean environment** for the agent, and that environment is the core of
the program rather than a detail of how it starts the child:

- **Its own `HOME` and `GROK_HOME`.** Discovery of `~/.claude`, `~/.cursor` and their plugins
  keys off `HOME`, and plugin discovery has no switch of its own -- the CLI merges Claude Code's
  enabled plugins directly -- so an empty `HOME` is the one control that removes all of it.
  The per-vendor switches (`GROK_CLAUDE_*_ENABLED` and the like) exist and are not enough.
- **`GROK_WORKFLOWS=0`, `GROK_SUBAGENTS=0`, `GROK_MEMORY=0`.** Each removes a tool family and
  the context that describes it.
- **`systemPromptOverride` on `session/new`**, which replaces the agent's system prompt outright:
  the snapshot below reports it at the size of the override.
- **An agent profile that names the tools.** An agent definition under `$GROK_HOME/agents/`,
  selected by `agentProfile` on `session/new`, with `tools: search_tool` and `agents_md: false`.
  This is ACP's equivalent of the headless `--tools` flag, which has none of its own.

With all of it the same prompt costs about 4.2k input tokens, and on a repeat most of that is a
cache hit. What remains cannot be removed with any switch found: 19 skills the CLI ships with
(about 2k tokens; `skills: []` in the profile, `[skills] ignore` in the config and the bundled
skill environment variables all left them in place) and the MCP meta-tools (about 0.7k), which
are always on.

**The model reaches for tools whenever it has one.** Even a lone `search_tool` was called twice
while answering about an image. The system prompt grok2api sends says plainly that no tool is to
be used; a tool call that still arrives is denied, and a permission request from the agent is
answered with a refusal, never an approval.

## When the agent goes, so does the server

A server whose agent has exited cannot answer anything, and restarting the agent in place would
lose every session anyway. So grok2api exits with it, and the restart belongs to whatever runs the
process -- the container's restart policy ([deployment.md](deployment.md)). That keeps one way to
recover rather than two.

## A clean environment is checked, not assumed

Two failures are silent, and both undo the section above:

- **A profile that fails to parse is replaced by the default agent**, with a warning in the log
  and nothing in the protocol. `skills: none` did it: the session came back with 8.8k tokens of
  tool definitions, shell included.
- **A `tools` list naming a tool that does not exist yields the full tool set**, not an empty one.

So the environment is verified at startup, and a failed check is a failed start. The CLI logs a
`session_context_snapshot` line per session that breaks the context down by source:

```
skills_tokens=1988 system_prompt_tokens=6 tool_definitions_tokens=698 mcp_tokens=0
agents_md_tokens=0 workflows_tokens=0 skills_count=19
```

That line is the check. `mcp_tokens`, `agents_md_tokens` and `workflows_tokens` above zero mean the
isolation leaked; tool definitions above the profile's size mean the profile did not apply.

## Images reach the model, whatever the capability says

`initialize` advertises `promptCapabilities.image: false`. An `image` content block in
`session/prompt` is nonetheless delivered to the model: a solid red PNG sent inline, with no file
on disk and no tool able to read one, was answered "Red". The capability flag is therefore not
consulted, and the behavior is what is relied on -- which makes it one of the things a new CLI
version has to be checked for.
