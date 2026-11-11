# Usage figures and borrowed credentials

Where the usage figures come from, how the token is read out of Claude's safe storage, when the keychain may ask, and how often the endpoint is polled. Read this before changing `ClaudeCredentials`, `UsageMonitor`, `SessionStarter` or anything with a timer.

## Credentials and the keychain

**Credentials are borrowed, never taken.** Only the access token is decrypted,
never the refresh token: Anthropic rotates those and using one signs Claude
Desktop out. Nothing is written back to Claude's config, cookies or keychain.
The token goes to `api.anthropic.com` and nowhere else.

**A borrowed token is never written down on the way out.** Up to 1.1.8.4 the
usage request and Start Session went through `URLSession.shared`, whose
`URLCache` stores the request it answered beside the answer, `Authorization`
header included, in `~/Library/Caches/graft.claude-graft/Cache.db`. A review in
the original project found one `api.anthropic.com` exchange there with a bearer
token in it, readable by any process running as the person without the keychain
being asked. Both now go through `UsageAPI.session`, ephemeral and with no cache
at all, the way `ClaudeDesktopUpdater` already did; every launch empties
`URLCache.shared` so what an older version left there goes, and the suite fails
if anything under `Sources/` names `URLSession.shared` again.

**The keychain is asked once, and only when asking is the way through.** Every
read tries silently first, so a build already on the item's ACL never sees a
dialog no matter who asked. When that read comes back shut the app asks rather
than falling back without saying why — once for the life of the process, never
again after a decline, and not while it is coming up hidden into the menu bar,
since a dialog thrown over a login is answered by nobody. The rule is
`ClaudeCredentials.mayRaiseDialog`, kept pure so the suite can drive it;
`UsageMonitor.mayPromptUnasked` carries the login case.

`SecKeychainSetUserInteractionAllowed` is what actually makes a read silent. The
`LAContext` the compiler suggests in its place governs items backed by an access
control, not an ACL of trusted applications, and was measured sailing straight
past the suppression and putting a dialog on screen from a background poll —
which is what the old "background polls never prompt" rule believed it had.

**Only a person starts a session.** `SessionStarter.start` runs because a
button was pressed and for no other reason: it defaults to non-interactive, so
a call from anywhere unaudited fails quietly instead of raising a keychain
prompt, and it claims the profile for the length of the call so the window and
the dropdown cannot both start the same account. The suite reads
`Sources/App/*.swift` and fails if a fourth caller appears or if `startSession`
turns up on a line with `onAppear`, `onReceive` or a timer — a view refreshes
every thirty seconds, and a session wired into one would open a five-hour
window on every account, over and over.

`config.json` holds `oauth:tokenCacheV2` in Chromium safe storage: keychain item
service `Claude Safe Storage`, account `Claude Key`, PBKDF2-HMAC-SHA1 with salt
`saltysalt` over 1003 iterations, AES-128-CBC, IV of sixteen spaces, `v10`
prefix.

That item's decrypt ACL names each trusted build by code hash, so an ad-hoc
signature earns a fresh entry every time the app is rebuilt — nine entries for
the same `build.noindex/Claude Graft.app` path were counted on the development machine,
alongside ten `cdhash:` entries in the item's partition list. A Developer ID
would be one `teamid:` entry that survives every version. Both a suppressed read
and a declined dialog answer `errSecAuthFailed`, so the two are told apart by
which call was made, never by the status.

## The usage figures

**One account, one figure.** The window read `plan-usage-history.json` for
itself while the menu bar showed what the endpoint had just answered, so one
account was reported from two sources that do not agree. That file is only
written while that Claude runs, so a profile closed for days had the window
showing figures from before a weekly reset — 92% of a week the bar correctly
had at 30%, side by side on one screen. Both detail views take
`UsageMonitor.entry(for:)` now, which is live where live is available and falls
back to the same file underneath; the suite fails if `Graft.usage(` reappears
in either of them. Their Start Session buttons `invalidate` too — that rule was
written for the dropdown alone, and the moment a window showed the monitor's
figure it needed it for the same reason.

Live usage is `GET https://api.anthropic.com/api/oauth/usage` with a bearer
token and `anthropic-beta: oauth-2025-04-20`. It answers with `five_hour` and
`seven_day` objects carrying `utilization` and `resets_at`, plus
`subscription_type`, a `limits` array of `weekly_scoped` per-model windows, and
`extra_usage` credits. The last two are parsed but not shown anywhere yet.

**A plan need not have a five-hour window at all.** Ultra is spent against the
week alone, with Fable allowed a share of it, and Claude's own usage page shows
those two rows and nothing else. The parser required `five_hour` and refused
every answer that lacked it, so on the machine this was reported from both
accounts read "the usage service sent something unexpected" and showed figures a
month old as though they were the account's. The answer, asked for with the
command line's login on that machine, sends `"five_hour":null` and a `seven_day`
carrying `utilization` and a `resets_at` written to the microsecond, beside
`limit_dollars`, `used_dollars`, `remaining_dollars` and `locked_reason`, all
null. Two dozen other top-level keys came back null too, most of them under code
names. `limits` holds the same week again as
`{"kind":"weekly_all","group":"weekly","percent":…,"severity":…,"scope":null,"is_active":true}`,
ahead of the scoped entries. So either window is enough, `fiveHour` is nil
rather than zero, no five-hour bar is drawn, and the menu bar leads with the
week; a `seven_day` that stops being sent falls back to `weekly_all`. An answer
that still cannot be read is written to `diagnostics.log` as `usage-unreadable`,
by its keys and the kind of value under each, so the next change to the shape
names itself.

`plan-usage-history.json` is the fallback: samples of `{t, org, u:{fh, sd}}`
where `fh` is the five-hour percentage used and `sd` the seven-day one, written
only while that instance runs. It is ~180KB and grows, so it is parsed once per
change and cached against modification time and size.

A sample needs `sd` and nothing else, for the same reason. On that same machine
a Claude that was open, green dot and all, reported a sample four days old,
which is what requiring both figures does to a profile whose samples stopped
carrying `fh` when the plan changed — whether that is what it writes now was not
seen, and nothing else about the history needs it to be. A sample that leaves
`fh` out keeps the figure from the one before it, but only from within five
hours, or a plan that lost the window would go on showing its last figure for
ever. Either figure may carry a fraction; `Graft.percentage` reads both shapes
for both sources.

Claude Code's command line keeps **one** login for the whole machine in the
keychain, so `CLAUDE_CONFIG_DIR` does not isolate accounts. That is why Start
Session goes through each profile's own borrowed token rather than the CLI.

## Polling budget

The thirty-second timer reads local files and checks what is running. The API
has three rungs, and `mayUseCache` is the rule: five minutes for a tick nobody
asked for, a minute for somebody looking — that is opening the dropdown — and
two seconds for somebody who pressed something. The last rung was missing, and
its absence is why Refresh Usage felt broken: opening the dropdown starts a pass
of its own, so the figure was always a few seconds old, always inside the
minute, and the button handed it straight back without asking anyone anything.
Two seconds is only wide enough to swallow a double-click.

A press that lands while a pass is running is queued, not dropped. `arrival` is
the rule. `inFlight` used to refuse everything, and the pass it most often
refused was the one the dropdown had just started itself — so the obvious move,
open the dropdown and press Refresh because the number looks stale, was the one
guaranteed to do nothing.

An account in use moves while nobody looks, so the tick's five minutes is
two for a profile whose Claude is open, and bringing a Claude to the front asks
for its account at the strength opening the dropdown does — matched to the
profile through its command line, the main one by having no `--user-data-dir`.
A press on one account's refresh button is `focus`ed: that profile gets the
press and the rest are read as a tick reads them, keychain prompt included.

Every figure carries when it was really taken. A reused reading used to be
stamped with the moment the pass ran, and a failed request returned the last
live reading of any age marked the same way, so a bar an hour behind read as
current. `refreshed` is the service's answer time or the profile's own sample
time, the row says which of the two it is, and `note` says why when it is not a
fresh live answer. Opening the dropdown mid-pass used to be dropped like a tick;
`arrival` queues anything stronger than a tick, and a queued request keeps its
own strength rather than being replayed as a press. A sample the profile wrote
after the last live answer is the better figure and wins.

Anything on screen that is worked out from the clock runs on a `TimelineView`
of its own. SwiftUI redraws a view only when its inputs change, and a figure
that has not moved is the same input every pass, so a reset countdown drawn in
a plain body stood still for ten minutes while the weekly one beside it counted
down.

Starting a session is the one thing here that changes the number itself, so it
calls `invalidate` for that profile before refreshing rather than trusting any
cache window. That is ordered against the refresh by the serial queue both go
through. Without it, a five-hour window would open and the bar would go on
showing the figure from before it.

Opening the dropdown asks for a current figure but does not skip the backoff,
because a failing endpoint would then be asked again on every open. Failures
back off 60/120/300/900/1800 seconds and a success clears the count; a
`Retry-After` from the service wins and is the one wait a person pressing
refresh cannot skip. It holds only as long as the service is the one asking: a
later failure that carries none starts a wait of Graft's own, and the service's
mark comes off with it, or a press would sit out an ordinary backoff as though
the service had asked for it.

A login that fails before anything is sent is the exception, and it is also the
one the row has to name. Every failure but a shut keychain used to read
"Anthropic's usage service did not answer", including a cached token that had
run out or never covered `user:profile` — no request made at all — and both
accounts on the machine this was reported from showed that line with nothing in
`usage-status.json` to say more. `failureNote` says what happened in the words
`ClaudeCredentials.Failure` and `UsageAPI.Failure` already had for it,
`backsOff` lets a login that failed locally be read again on the next pass
rather than minutes later, since there was nothing to be patient with, and
`usage-failed` and `usage-login-unusable` in `diagnostics.log` carry the status
code, or each cached entry's expiry and scopes without its token, once each time
they change.

`backsOff` first let only an expired login and one that could not be read skip
the wait. Everything `ClaudeCredentials` throws happens before a request, so all
of it now does: a shut keychain, which the next pass reads silently and so
retries without a dialog, and a config caught mid-write. That one is Claude
renaming a new config over the old, not a profile with no login, so `token`
reads through `readableConfigJSON` and throws `configUnreadable` instead of
telling the row there is no login to ask with.

**A pass that has been told no asks nobody after it.** The key is one item for
every profile, so once a read in a pass comes back shut, every profile after it
in that pass is read silently (`UsageMonitor.prompting`). Before, each profile
was asked whatever had just happened, and Start Session's follow-up refresh
went out allowed to ask and with no focus, so a Deny on a Mac with three
Claudes was answered with three more dialogs. That refresh now asks nobody and
only about the account the session was started on: the press already asked the
keychain once, in starting the session. The profiles after a Deny fail the same
way, and their "choose Always Allow" no longer replaces the answer the person
just gave in the dropdown's problem line.


**The last answer outlives the process.** `liveCache` was memory alone, so every
restart began with nothing: an update installing itself, a login, a relaunch.
The first pass then asked every account at once, and an answer refused by the
rate limit left the row on the profile's own record. On the machine this was
reported from, an Ultra account went in ten minutes from a live 15% of its week
to a nine-hour-old 0%, across what by its timing was Graft restarting into
1.1.8.2, which had been published minutes before with the hold switched off.
Each answer is now written to `ClaudeGraft/live-usage.json` with the moment it
was taken, and read back once, on the serial queue, before anything reads or
changes the cache, so a restart shows the last live figure at its real age and
has no reason to ask straight away for what it knew a minute before.
`invalidate` loads before it drops, or the file would bring back the very
reading it had just thrown out, and a reading older than a week stays behind,
every window it describes having reset.