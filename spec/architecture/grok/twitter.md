# Twitter, through the agent

grok2api serves X data -- posts, users, searches -- under `/twitter/`, read by the agent with the
tools xAI runs for it. Not an X API client: the agent reads X, and grok2api tells it what shape to
answer in. The point is the division of labor: however X's own interfaces or xAI's tools change,
grok2api asks for the same shape and the model maps what it sees onto it.

Measured against grok 1.0.41, on 2026-09-27.

## The tools are xAI's, run on its side

The CLI's default agent sends the model two server-side tools beside its own functions,
`{"type": "web_search"}` and `{"type": "x_search"}`. `x_search` gives the model four tools:

- `x_thread_fetch(post_id)` -- a post with its context: author, timestamp, engagement, media URLs
  on `pbs.twimg.com`, a quoted post nested in full, the conversation id.
- `x_keyword_search(query, limit <= 10, mode Top|Latest)` -- X's advanced search, operators and all:
  `from:`, `since:`/`until:`, `conversation_id:`, `quoted_tweet_id:`, `filter:images`,
  `min_faves:` and the rest.
- `x_semantic_search(query, limit <= 10, from_date, to_date, usernames, exclude_usernames,
min_score_threshold)`.
- `x_user_search(query, count)` -- users: id, name, handle, avatar, bio, followers, verification.

The model was asked for their definitions verbatim and for one raw result from each; the answers
are the source of the list above. A post fetched this way matched the post on X exactly, down to
its two image URLs and its quoted post.

**The web is not the way in.** Before `x_search` was found, the model reached X through
`web_search` and `web_fetch`: a search index days behind, fetches of x.com that a third-party
reader had already been blocked from, and one question that took 28 searches and 608k input
tokens. `x_search` answered four questions in one turn for 7k.

## Turning it on is a denylist

An agent profile's `tools` allowlist cannot name `x_search`: the name is not recognized, and an
unrecognized name makes the CLI keep its full tool set (bridge.md). Naming `web_search` alone
drops `x_search` with everything else. What works is the other direction: the full set, less
everything but `x_search`, with the profile's `disallowedTools` -- camel case; `disallowed_tools`
is silently ignored. The shell tool has to be named as `run_terminal_cmd` for the denial to hold.
What reaches the model is then `search_tool` and `x_search`, about 4.9k tokens of context.

`toolOverrides` in `session/new`'s `_meta`, which `initialize` advertises, did not turn it on.

## The results reach the model and nothing else

`x_search` runs on xAI's side. Its results go into the model's context and appear in no stream:
the agent reports the call's arguments and never its output, and the upstream Responses stream
carries none of it either. So the data leaves only as the model's own answer, and every field
grok2api returns is one the model wrote down.

That settles the format: the answer is constrained with an output schema (api.md, "Structured
output"), which the CLI enforces. JSON is the right shape because it is the one the constraint
holds the model to, not because the tool speaks it -- it does not; its raw output is a fixed text
layout.

## Everything the tools can do is an endpoint

The first version exports every capability the four tools have, each parameter of theirs a query
parameter of ours, under `/twitter/`:

| Endpoint                                 | Read with                                                      |
| ---------------------------------------- | -------------------------------------------------------------- |
| `GET /twitter/posts/{id}`                | `x_thread_fetch`: the post, a quoted post nested               |
| `GET /twitter/posts/{id}/thread`         | `x_thread_fetch`: parents and replies around it                |
| `GET /twitter/posts/{id}/replies`        | `x_keyword_search` `conversation_id:`                          |
| `GET /twitter/posts/{id}/quotes`         | `x_keyword_search` `quoted_tweet_id:`                          |
| `GET /twitter/posts/{id}/reposts`        | `x_keyword_search` `retweets_of_tweet_id:`                     |
| `GET /twitter/users/search`              | `x_user_search`                                                |
| `GET /twitter/users/{username}`          | `x_user_search`, the exact handle                              |
| `GET /twitter/users/{username}/posts`    | `x_keyword_search` `from:`, latest first                       |
| `GET /twitter/users/{username}/media`    | the same, `filter:media`                                       |
| `GET /twitter/users/{username}/mentions` | `x_keyword_search` `@username -from:username`                  |
| `GET /twitter/search`                    | `x_keyword_search`, the query and its operators passed through |
| `GET /twitter/search/semantic`           | `x_semantic_search`, every filter it takes                     |

The shapes are grok2api's own, with X API v2's field names where one exists (`id`, `text`,
`created_at`, `conversation_id`, `author`), not a copy of v2: v2's pagination tokens, exact
metrics contract and rate limits are things this cannot honor, and imitating them would be lying.

**The model is the standard one, at low effort.** The fast variant costs twice as much for speed
that does not show: the time goes to the tool and to writing the answer out, not to thinking. For
the same reason the reasoning effort is low by default -- the model copies what a tool returned,
which is not a problem to reason about -- and it is a setting, `GROK2API_TWITTER_EFFORT`, beside the
budget (`GROK2API_TWITTER_TIMEOUT_SECS`, 60 by default) and fast response
(`GROK2API_TWITTER_FAST_RESPONSE`).

**A post's URL is built, not read.** `https://x.com/<username>/status/<id>` follows from two fields
the model already copied, so it is not a third thing it could copy wrong. What the model does copy
is checked before it is returned: ids are digits, a fetched post is the one asked for, and media
URLs are on X's media hosts. The schema has a way to say nothing was found, so an empty result is
never an invented one.

## Pages are grok2api's, ten at a time

A search tool returns at most ten posts. A list endpoint asks for more by paging itself: each page
is one more prompt in the same session, the next query bounded with `max_id:` below the oldest post
so far, and `next_cursor` is that bound, so a client continues where a response stopped. Only a
latest-first search has an order to page along; a top or semantic search is one page.

## Time is the one limit

A request has a time budget, a setting, and no limit on tool calls. When it runs out the turn is
cancelled and what was already obtained is returned, marked incomplete: the pages finished, and
from a page still being written, every item whose JSON was complete. A request that obtained
nothing in its time is an error.

## Fast response: answer now, refresh behind

With fast response on, the default, a request is answered at once from the latest result grok2api
holds for the same request, and a refresh starts behind it; a request with no result yet is
answered `202 Accepted` with `Retry-After`, and the fetch starts. Every request refreshes, and one
refresh per request key runs at a time, so a client polling does not multiply the cost. With it
off, a request waits for its own fetch, tens of seconds, and is always current.

The latest results are held in memory for this. They are not a cache: nothing is served from them
without a refresh following -- except a settled answer, below.

## Settled answers are kept, and never fetched again

An answer marked `immutable` (below) cannot change, so fetching it again would spend the
subscription to learn nothing. grok2api keeps it and answers every later request for it from what
it kept, fast response or not, with no refresh behind. Only a successful answer settles: a `404`
may be a post not yet indexed, and is fetched again like anything else.

Settled answers are kept on the volume, under `twitter/`, one file per request, not in memory:
memory is lost with every restart, and would grow without bound with every old post anyone asks
for, while a file is about two kilobytes and outlives the process. Deleting the directory is how
they are cleared. The other answers stay in memory alone and are forgotten after a day unasked.

## Freshness is Cache-Control, and the cache is the CDN's

grok2api keeps no cache of X data. Every request asks the agent again, and the response says how
long it may be kept, so a CDN in front does the caching:

- **A post over an hour old is `immutable`.** An X post can be edited only in the hour after it is
  posted, so past that its content does not change.
- **A list bounded by an `until` over an hour ago is `immutable` too**: no post can enter it or
  change in it any more.
- **Anything else is kept 15 minutes**: a younger post, a list still open to new posts, a thread
  still gathering replies, a user.
- **A `202` is `no-store`.**

Engagement counts keep moving after the hour; a response marked immutable carries them as they
were when it was fetched, which is the price of the CDN being allowed to keep it.
