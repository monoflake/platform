# Conversations and sessions

An OpenAI client is stateless: every request carries the whole conversation. A Grok session is
stateful: it holds the conversation, and a prompt is only the next message. This file is how the
two meet.

## A request continues the session whose conversation it extends

grok2api keeps the conversation each live session has seen. When a request arrives, its messages
up to the last one are compared with those conversations; if they are exactly one session's
conversation, the last message is sent to that session as its next prompt, and the request's
reply is the session's reply. Otherwise a new session is made.

The other way was a new session per request with the history flattened into one prompt. It is the
fallback, not the rule, because reuse is what it costs to lose:

- **The prompt cache.** A continued session sends its history as the prefix the model saw last
  time, and it is read from cache: a second turn measured 14,336 of 14,460 input tokens cached.
  The cache is what makes a long conversation cheap on the subscription.
- **The roles.** The session holds the model's own earlier turns as its turns. Flattened, they
  are text inside a user message, which the model reads as a transcript someone pasted.

A conversation the client edited -- a changed earlier message, a regenerated reply, a different
system prompt -- no longer extends any session, and so starts a new one. That is correct rather
than a miss: the session's history is no longer the client's.

## Or it names the reply it continues

A Responses request may continue by id instead (`previous_response_id`, api.md). Each session
remembers the id its latest answer went out under, and a request naming that id continues it,
whatever else it carries; anything it sends ahead of its last message is new to the session and is
seeded the way a new session's history is, below. The id is the answer's, not the session's, so
only the latest answer can be continued from -- an older one would fork a conversation the session
has already moved past.

## A session lives for a day of idleness

A session is kept for 24 hours after it last answered, then closed and forgotten; the period is a
setting. A day covers a conversation left overnight and picked up the next morning, which is the
usual way a chat is resumed. A request that would have continued a closed session starts a new
one seeded from its history, below, so expiry costs cache and never correctness.

## A new session is seeded from the history

A request that matches no session and carries earlier turns has a history the new session never
saw. It is sent as one prompt that renders the earlier turns ahead of the last message, which is
the flattening above, used only where there is nothing to continue.

The rendering says what the block is -- the conversation so far, not to be answered again -- marks
each turn with whose it was, and ends by pointing at the message that follows. Turns are wrapped
in tags rather than prefixed `User:` and `Assistant:`, because a turn's own text can contain a line
that starts that way, and a prefix could not tell it from a boundary. An image in an earlier turn
cannot be sent again this way, so it is named where it stood.
