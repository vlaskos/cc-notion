# cc-notion

Add Claude Code to Notion. Comment `/cc ...` on any page and Claude replies in the same thread, with access to your Notion through MCP.

This is a small self-hosted bot you run on a Mac. A Notion `comment.created` webhook reaches a listener through ngrok, the listener runs `claude -p` (headless), and the answer is posted back to the thread. A follow-up `/cc` in the same thread continues the same Claude session.

No dependencies, Node 18+. Runs while the Mac is awake.

## How it works

1. You comment `/cc summarize this page` on a Notion page.
2. Notion sends a `comment.created` webhook to ngrok, which forwards it to the listener on your Mac.
3. The listener checks the signature, confirms you are the author, and confirms the text starts with `/cc`. Then it runs `claude -p` with the Notion MCP tools.
4. Claude's answer is posted as a reply in the same thread. A later `/cc` in that thread resumes the session (`--resume`).

```
cc-notion/
  server.mjs                   listener + worker
  workspace/CLAUDE.example.md  rules for the headless session (copied to CLAUDE.md on first install)
  launchd/*.plist              LaunchAgent templates (listener + ngrok)
  install.sh / uninstall.sh
  data/state.json              verification token, processed comment IDs, per-thread session IDs (created automatically)
  logs/                        daily log plus launchd and ngrok output
```

## Setup (once)

**1. Notion integration.** notion.so/profile/integrations → New integration (Internal). Capabilities: Read/Update/Insert content, Read/Insert comments. Copy the Internal Integration Secret.

**2. Page access.** On each page you want to use: `•••` → Connections → add the integration. The webhook only delivers events for pages the integration can access.

**3. Notion MCP for the headless session.** The `claude -p` session needs a Notion MCP server, and `ALLOWED_TOOLS` must match that server's tool prefix.
- Add your own at user scope, so any working directory sees it:
  ```bash
  claude mcp add --scope user --transport http notion https://mcp.notion.com/mcp
  claude   # then: /mcp → notion → authenticate, and exit
  ```
  That server's tools are prefixed `mcp__notion`, so set `ALLOWED_TOOLS=mcp__notion`.
- Or reuse Claude's managed Notion connector if `claude mcp list` already shows it connected. Its tools are prefixed `mcp__claude_ai_Notion`, so set `ALLOWED_TOOLS=mcp__claude_ai_Notion`.

**4. Integration token in the Keychain:**
```bash
security add-generic-password -a "$USER" -s cc-notion-token -w 'ntn_...'
```

**5. Your Notion user ID:**
```bash
curl -s https://api.notion.com/v1/users \
  -H "Authorization: Bearer $(security find-generic-password -s cc-notion-token -w)" \
  -H "Notion-Version: 2022-06-28" | jq '.results[] | select(.type=="person") | {id, name}'
```
Optional: leave `NOTION_USER_ID` empty and the listener logs the author ID of the first comment it sees.

**6. ngrok:** `brew install ngrok`, `ngrok config add-authtoken ...`, then reserve a free static domain in the ngrok dashboard. If `brew` fails on a directory-permissions error, download the official binary into a directory on your PATH instead.

**7. Install:**
```bash
NGROK_DOMAIN=xxx.ngrok-free.app NOTION_USER_ID=<id> ALLOWED_TOOLS=mcp__notion ./install.sh
```
Use `ALLOWED_TOOLS=mcp__claude_ai_Notion` instead if you reuse Claude's managed connector. First install copies `workspace/CLAUDE.example.md` to `workspace/CLAUDE.md`; edit that local copy to set the rules for your workspace. Check: `curl https://xxx.ngrok-free.app/health` returns `ok`.

**8. Webhook.** Integration settings → Webhooks → Create subscription. URL `https://xxx.ngrok-free.app/notion`, event `comment.created`. Notion sends a verification token and the listener saves it. Copy it into the Verify field:
```bash
jq -r .verificationToken data/state.json | pbcopy
```

## Test
Comment `/cc what's on this page?` on a page the integration can access. Within a few seconds the thread shows a short acknowledgement (⏳), then the reply. A follow-up `/cc ...` in the same thread continues the session (`--resume`).

```bash
tail -f logs/$(date +%F).log
```

## Filtering
- Events without a valid `X-Notion-Signature` are dropped.
- Bot and other-author comments are filtered from the event's `authors` field before any API call.
- Only comments starting with `/cc` are processed.
- Each comment ID runs once; jobs run one at a time.

## Catch-up (comments made while the Mac was asleep or off)
The webhook only reaches the listener while the Mac is awake. To pick up `/cc` comments made during downtime, the listener runs a catch-up sweep, not on a timer but only:
- at startup (boot or service restart);
- on wake from sleep (a local heartbeat notices the time gap and runs one sweep; Notion is not polled).

A sweep takes the top-N recently edited pages (`/v1/search`), reads the comments on each, and queues any `/cc` not already in `state.seen`. Dedup is shared with the webhook path, so nothing runs twice. Settings (env/plist): `SWEEP_TOP_N` (40), `SWEEP_MAX_AGE_H` (48), `SWEEP_ON_STARTUP` (1), `WAKE_GAP_SEC` (180).

This is best-effort. Notion has no global comment feed, so a comment attached to a specific block on a page outside the top-N won't be found by the sweep; the webhook still catches those. Notion itself retries an undelivered event about 8 times over ~24 hours, then disables the subscription after sustained failures, so check the Webhooks tab and re-enable it after a long outage.

## Claude's permissions
The session runs with `--allowedTools` (the Notion MCP prefix) and `--permission-mode acceptEdits`; `Bash`, `Edit`, `Write`, `NotebookEdit`, and `WebFetch` are denied. The rest of the rules live in `workspace/CLAUDE.md`.

Setting `--permission-mode` is deliberate: with a global `defaultMode: plan` in Claude Code settings, a headless `claude -p` inherits plan mode and only drafts a plan instead of doing the work.

Config (plist/env): `TRIGGER`, `ALLOWED_TOOLS`, `PERMISSION_MODE`, `CLAUDE_MODEL`, `MAX_TURNS`, `TIMEOUT_MIN`, `SWEEP_TOP_N`, `SWEEP_MAX_AGE_H`, `SWEEP_ON_STARTUP`, `WAKE_GAP_SEC`.

## Manage
```bash
launchctl kickstart -k gui/$(id -u)/com.cc-notion.listener   # restart after edits
./uninstall.sh                                               # remove the agents
```

## License
MIT. See [LICENSE](LICENSE).
