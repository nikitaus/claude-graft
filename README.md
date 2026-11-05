<div align="center">

<img src="docs/assets/icon.png" width="120" alt="Claude Graft">

<h1>Claude Graft, personal fork</h1>

</div>

This is a personal fork of [Claude Graft](https://github.com/aaditya-v-more/claude-graft),
the macOS app that runs several Claude Desktop logins side by side. It is built
on the original's 1.1.8 release, and what the app does and how it works is
described there. This page covers only what is different here.

## What is different

**Usage for plans without a five-hour window.** Ultra is spent against the week
alone, with Fable allowed a share of it. The original requires a five-hour
figure in Anthropic's usage answer and refuses any answer that lacks one, so an
Ultra account reads "the usage service sent something unexpected" and falls back
to figures its profile recorded days or weeks earlier. Here either window is
enough: such an account shows its week and its Fable share live from Anthropic,
with no five-hour bar, and the number in the menu bar is the week. The profile's
own record is read the same way, a figure written with a fraction is no longer
skipped as missing, and should the weekly window stop being sent the same figure
is taken from the newer list of limits in the answer.

**It says why a figure is not live.** The original shows "Anthropic's usage
service did not answer" for every failure but a locked keychain, including a
saved login that has run out, when no request was made at all. Here the line
under each account names what happened: a login that has expired, one Anthropic
refused, a rate limit, an answer that could not be read, or no answer. A login
that failed before anything was sent is checked again on the next pass rather
than minutes later, and each failure is written once to `diagnostics.log` in
`~/Library/Application Support/ClaudeGraft/`, with the status code or, for a
login, each saved entry's expiry and permissions but never the token itself.

**Updates come from this fork.** Builds here check this repository's own update
feed and accept only releases signed with this fork's key, so a release of the
original project never replaces them. Version numbers have four parts, starting
at 1.1.8.1, so that none can be confused with an original release; that matters
because a shortcut refreshes its launcher only when the number changes. The
feed is the appcast file on `main`, read straight from the repository, so the
fork keeps no website.

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
