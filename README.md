<div align="center">

<img src="docs/assets/icon.png" width="120" alt="Claude Graft">

<h1>Claude Graft, personal fork</h1>

</div>

This is a personal fork of [Claude Graft](https://github.com/aaditya-v-more/claude-graft),
the macOS app that runs several Claude Desktop logins side by side. It is built
on the original's 2.0.1 release, with everything that release brought: shared
usage across accounts for Claude Code, the Artifacts, Projects and Search Chats
panes, the redesigned window and the conversation on screen in the menu bar.
What the app does and how it works is described there. This page covers only
what is different here.

## What is different

**Updates come from this fork.** Builds here check this repository's own update
feed and accept only releases signed with this fork's key, so a release of the
original project never replaces them. A version number is the original release
it is built on with a fourth part added, so 2.0.1.1 is the original's 2.0.1
with this fork's changes, and none can be confused with an original release;
that matters because a shortcut refreshes its launcher only when the number
changes. The feed is the appcast file on `main`, read straight from the
repository, so the fork keeps no website. In the app, What's New and Report a
Problem open this repository's releases and issues, while the rest of the Help
menu still credits the original project and its author.

**A figure that is not live says why, in more cases.** The original names a
login that could not be read, but shows "Anthropic didn't answer" for anything
the service sent back. Here a refused login says to open that Claude, a rate
limit and an answer that could not be read each say what they are, and the
service not answering is kept for when it did not. Each failure is written once
to `diagnostics.log` in `~/Library/Application Support/ClaudeGraft/`, with the
status code, the shape of an answer that could not be read without its values,
or, for a login, each saved entry's expiry and permissions but never the token.

**Usage reads a little more of what Anthropic sends.** Should the weekly window
stop being sent, the same figure is taken from the newer list of limits in the
answer; a reset written to the microsecond is read rather than dropped; and a
figure written with a fraction is no longer skipped as missing, in the answer or
in a profile's own record.

**The last live figure survives a restart.** The original keeps Anthropic's
last answer for each account only while it runs, so after an update, a login or
a relaunch an account could fall back to the figure its profile recorded itself,
hours old, if Anthropic was rate-limiting just then. Here it is kept on disk and
shown with the time it was really taken until a new one arrives.

## Install

Take the disk image from [Releases](https://github.com/nikitaus/claude-graft/releases),
quit any Claude Graft that is running, and drag the app into Applications. The
app is signed without an Apple developer account, so macOS refuses a downloaded
copy until its quarantine flag is cleared:

```sh
xattr -dr com.apple.quarantine "/Applications/Claude Graft.app"
```

On first launch macOS asks for access to the "Claude Safe Storage" keychain
item; choose **Always Allow**. Every release after this one arrives by itself.

Coming from the original installed with Homebrew, remove it without `--zap`,
which would also delete Graft's shortcuts list and settings. Your shortcuts,
profiles and chats live outside the app and carry over:

```sh
brew uninstall --cask claude-graft
```

## Building and releasing

```sh
./test.sh                   # Regression checks in a throwaway directory
./build.sh                  # App in build.noindex/
```

With only the Command Line Tools and no Xcode, the macOS 27 SDK cannot compile
the app's views, although the tests pass. Build against the older SDK the tools
ship beside it:

```sh
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ./build.sh
```

A release is made by bumping `VERSION`, optionally adding a note in
`docs/release-notes/<version>.html`, pushing to `main` and running the
**Release** workflow from the Actions tab. It tests, builds for Apple silicon
and Intel, signs with the `SPARKLE_PRIVATE_KEY` repository secret, publishes the
disk image and the zip, and only then adds the entry to the feed. When GitHub is
short of Apple silicon machines, choose `macos-15-intel`; the release is
universal either way.

## Licence

MIT, as the original: see [LICENSE](LICENSE), which keeps the original
copyright notice. The changes in this fork are released under the same terms.
