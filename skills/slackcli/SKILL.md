---
name: slackcli
description: Read Slack messages, threads, channels, and search results using the slackcli CLI (github.com/shaharia-lab/slackcli), already authenticated on this machine. Use this whenever the user pastes a Slack link (e.g. https://cordial.slack.com/archives/C.../p...), asks to read/summarize a thread or channel, asks to find/search Slack messages, mentions a channel by name (e.g. #some-channel) or a person's Slack DMs, or otherwise wants Slack content pulled into the conversation. Covers resolving channel/user names to IDs, parsing Slack permalinks into channel+ts+thread_ts, reading channels/threads, and searching messages/channels/users. Do not use for sending messages, reacting, or posting to Slack — this skill is read-only by design even though slackcli itself supports writes.
---

# slackcli — reading Slack from the command line

`slackcli` is already installed and authenticated on this machine. This skill is
scoped to **reading** Slack content — resolving
links, channels, users, and searches, then pulling messages/threads — not to
sending messages or reactions. Never run `slackcli messages send`, `slackcli
messages draft`, or `slackcli messages react` under this skill even if asked
indirectly; if the person wants to post something, say so explicitly and let
them confirm before you touch a write command.

`$SKILL_BASE` refers to this skill's base directory (shown as "Base directory
for this skill:" when the skill loads). Use it to reference bundled scripts.

Always add `--json` and pipe through `jq` — the human-readable table output is
lossy (truncates text, drops `ts`/`thread_ts`) and wastes context.

**`slackcli` writes progress/status text to stderr even in `--json` mode.**
Always redirect stderr away (`2>/dev/null`) before piping to `jq`, or `jq` will
choke on/mix in that noise. Every example below already does this — keep the
`2>/dev/null` when adapting them.

## Quick reference

| Need | Command |
|---|---|
| Resolve `#channel-name` -> ID | `slackcli search messages 'in:#name' --limit 1 --json 2>/dev/null \| jq -r '.matches[0].channel.id'` |
| Resolve a person's name -> user ID | `slackcli search users 'name' --json 2>/dev/null \| jq -r '.users[0].id'` |
| Parse a Slack message URL | `$SKILL_BASE/scripts/parse_slack_url.sh '<url>'` |
| Read recent channel messages | `slackcli conversations read <CHANNEL_ID> --limit=<N> --json 2>/dev/null` |
| Read a full thread | `slackcli conversations read <CHANNEL_ID> --thread-ts=<TS> --json 2>/dev/null` |
| Free-text / operator search | `slackcli search messages '<query>' --json 2>/dev/null` |
| List channels | `slackcli conversations list --types=public_channel --json 2>/dev/null` |
| Read a canvas | `slackcli canvas read <CANVAS_ID_or --channel=ID> --json 2>/dev/null` |

## 1. Given a Slack link

Slack permalinks look like:

```
https://cordial.slack.com/archives/C594B5BQS/p1786382955095779
https://cordial.slack.com/archives/C594B5BQS/p1786407715575619?thread_ts=1786382955.095779&cid=C594B5BQS
```

Don't try to eyeball the timestamp math — run the bundled parser:

```bash
bash $SKILL_BASE/scripts/parse_slack_url.sh 'https://cordial.slack.com/archives/C594B5BQS/p1786407715575619?thread_ts=1786382955.095779&cid=C594B5BQS'
# CHANNEL_ID=C594B5BQS
# MESSAGE_TS=1786407715.575619
# THREAD_TS=1786382955.095779
```

Then:
- **If `THREAD_TS` is set** (the link has a `thread_ts` query param — it points
  at a reply inside a thread): read the whole thread with
  `slackcli conversations read $CHANNEL_ID --thread-ts=$THREAD_TS --json 2>/dev/null`.
  The specific reply the person linked to is `MESSAGE_TS` — call that out in
  your summary if it's not the first message.
- **If `THREAD_TS` is empty** (plain permalink, no query param): first try
  `slackcli conversations read $CHANNEL_ID --thread-ts=$MESSAGE_TS --json 2>/dev/null`.
  If Slack returns more than one message, `MESSAGE_TS` was itself a thread
  parent and you now have the full thread. If it returns just the one
  message, it's a standalone message — if useful, also pull surrounding
  context with `slackcli conversations read $CHANNEL_ID --latest=$MESSAGE_TS --limit=10 --json 2>/dev/null` (or just report the single message).

If multiple links are pasted at once, parse and fetch each independently —
don't assume they share a channel or thread.

## 2. Given a channel name, user name, or vague description

Resolve names to IDs before reading — `conversations read` needs an ID, not a
name.

**Channel by name** — use message search with `in:#channel` for precise resolution:
```bash
slackcli search messages 'in:#ce-support' --limit 1 --json 2>/dev/null | jq -r '.matches[0].channel | .id'
```
The `in:#name` operator in message search requires an exact channel name match
and reliably gives the correct ID. Prefer this method.

**Fallback — fuzzy channel search** (if the message search returns no results,
e.g. for a brand-new or empty channel):
```bash
slackcli search channels 'ce-support' --json 2>/dev/null | jq '[.channels[] | select(.is_archived == false)] | sort_by(.is_member | not) | .[] | {id, name, is_member}'
```
This returns fuzzy/partial matches, so you MUST verify the result:
1. Filter out archived channels (`is_archived == false`)
2. Prioritize channels the user has joined (`is_member == true`)
3. Check for an exact `.name` match before using the ID
4. If no exact match, show the candidates and ask

**User by name** (for DMs or filtering "messages from X"):
```bash
slackcli search users 'firstname lastname' --json 2>/dev/null | jq '.users[0]'
```

**Vague/semantic requests** ("find that thread about the OAuth redirect
allowlist," "what's been said about Bedrock rate limits recently") — use
message search rather than guessing a channel:
```bash
slackcli search messages 'oauth redirect allowlist' --json 2>/dev/null
```
Slack search operators work inside the query string, e.g.:
```bash
slackcli search messages 'in:#dev-local-env from:@someone bedrock rate limit' --json 2>/dev/null
slackcli search messages 'is:unread to:@me' --json 2>/dev/null
```
Narrow with `in:`, `from:`, `to:`, `before:`, `after:`, `has:link`, etc. as
needed. If the first search is too broad or too narrow, don't just dump
results — refine the query and re-search.

Once you've identified the right message from search results, pull its `ts`
(and `thread_ts` if present in the JSON) and read the full thread with
`conversations read` as in section 1 — search results are often snippets,
not the complete thread.

## 3. Reading

```bash
# last N messages in a channel (no thread expansion)
slackcli conversations read $CHANNEL_ID --limit=50 --json 2>/dev/null

# a specific thread, fully expanded
slackcli conversations read $CHANNEL_ID --thread-ts=$TS --json 2>/dev/null
```

The JSON includes `ts` and `thread_ts` per message — when summarizing a
channel dump, note which messages are thread parents (has replies) if the
person might want to drill into one.

## 4. Presenting results

- Summarize/synthesize by default; don't paste raw JSON unless asked.
- When quoting a message verbatim, keep it short and attribute the speaker
  (`user` field — resolve to a display name via `slackcli search users
  ... --json 2>/dev/null` or the `users` array in the response if available).
- If a thread is long, prioritize: the original ask, the resolution/decision,
  and any open action items — not a full transcript.
- If `slackcli` returns an auth error, tell the user directly rather than
  retrying blindly — token refresh (`slackcli auth login-auto`) requires
  manual intervention.

## 5. JSON response schemas

### `slackcli conversations read` (channel or thread)

```json
{
  "channel_id": "C0493RT4P",
  "message_count": 20,
  "messages": [
    {
      "type": "message",
      "user": "U06EZTLUV32",
      "text": "message body...",
      "ts": "1786393613.537019",
      "thread_ts": "1786393613.537019",
      "reply_count": 5,
      "blocks": [...]
    }
  ],
  "users": [
    {"id": "U06EZTLUV32", "name": "celders", "real_name": "Cameron Elders", "email": "celders@cordial.com"}
  ]
}
```

Access messages via `.messages[]` (NOT the top level). The `users` array maps
user IDs to display names for messages in the response.

### `slackcli search messages`

```json
{
  "query": "in:#ce-support",
  "total": 142,
  "page": 1,
  "pages": 15,
  "matches": [
    {
      "type": "message",
      "user": "U06EZTLUV32",
      "username": "celders",
      "text": "message body...",
      "ts": "1786393613.537019",
      "permalink": "https://cordial.slack.com/archives/...",
      "channel": {
        "id": "C0493RT4P",
        "name": "ce-support",
        "is_archived": false,
        "is_private": false
      },
      "blocks": [...]
    }
  ]
}
```

Access results via `.matches[]`. Each match includes a `.channel` object with
the channel ID and name.

### `slackcli search channels`

```json
{
  "query": "ce-support",
  "total": 5,
  "channels": [
    {
      "id": "C0493RT4P",
      "name": "ce-support",
      "is_archived": false,
      "is_member": true,
      "is_private": false,
      "member_count": 18,
      "purpose": {"value": "...", "creator": "U02G7GXPE", "last_set": 1493964236}
    }
  ]
}
```

## Reference

Full command surface: `$SKILL_BASE/scripts/parse_slack_url.sh --help` isn't a thing, but
`slackcli --help`, `slackcli conversations --help`, and `slackcli search
--help` are — run those if a command in this file doesn't behave as expected
(the CLI is under active development and flags occasionally shift between
releases).
