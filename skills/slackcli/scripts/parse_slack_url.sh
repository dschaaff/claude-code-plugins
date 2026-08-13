#!/usr/bin/env bash
# Parse a Slack message/thread link into the pieces slackcli needs.
#
# Usage:
#   parse_slack_url.sh 'https://cordial.slack.com/archives/C594B5BQS/p1786382955095779'
#   parse_slack_url.sh 'https://cordial.slack.com/archives/C594B5BQS/p1786407715575619?thread_ts=1786382955.095779&cid=C594B5BQS'
#
# Prints shell-eval-able assignments:
#   CHANNEL_ID=C594B5BQS
#   MESSAGE_TS=1786407715.575619
#   THREAD_TS=1786382955.095779   (empty if the link has no thread_ts param)
#
# Notes on the format:
#   - The path segment right after the channel id is `p<17 digits>` with no
#     decimal point. The real Slack `ts` is that string with a decimal point
#     inserted 6 digits from the end (p1786382955095779 -> 1786382955.095779).
#   - If the link has a `thread_ts` query param, the link points at a REPLY
#     inside a thread. MESSAGE_TS is the specific reply; THREAD_TS is the
#     parent message that anchors the whole thread. To pull the WHOLE thread,
#     use THREAD_TS (falling back to MESSAGE_TS if there's no thread_ts) with
#     `slackcli conversations read <channel> --thread-ts=<ts>`.
#   - If there's no `thread_ts` param, the link is just a permalink to a
#     single top-level message — MESSAGE_TS may itself be a thread parent
#     (has replies) or a standalone message. Read it directly first with
#     `slackcli conversations read <channel> --thread-ts=<MESSAGE_TS>`; if it
#     comes back with only one message, it wasn't a thread parent.

set -euo pipefail

url="${1:-}"
if [[ -z "$url" ]]; then
  echo "usage: $0 <slack-message-url>" >&2
  exit 1
fi

# Extract channel id: the path segment matching C/G/D followed by alnum, right before /p<digits>
channel_id=$(echo "$url" | grep -oE '/archives/[A-Z0-9]+/p[0-9]+' | grep -oE '[A-Z0-9]+/p[0-9]+' | cut -d/ -f1)

# Extract the raw p<digits> segment and strip the leading 'p'
raw_ts=$(echo "$url" | grep -oE '/p[0-9]+' | head -1 | tr -d '/p')

if [[ -z "$channel_id" || -z "$raw_ts" ]]; then
  echo "error: could not parse a channel id / message ts out of: $url" >&2
  exit 1
fi

# Insert decimal point 6 digits from the end
message_ts="${raw_ts:0:${#raw_ts}-6}.${raw_ts: -6}"

# Extract thread_ts query param if present (already has its own decimal point, just needs URL decoding of nothing special here)
thread_ts=$(echo "$url" | grep -oE 'thread_ts=[0-9]+\.[0-9]+' | cut -d= -f2 || true)

echo "CHANNEL_ID=$channel_id"
echo "MESSAGE_TS=$message_ts"
echo "THREAD_TS=${thread_ts:-}"
