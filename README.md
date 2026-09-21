<h1 align="center">HandsFreeNotch</h1>

<p align="center">
  Hold a key, say “open Spotify”, let go. The notch shows what it heard and what it did, in milliseconds.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.10-orange" alt="Swift">
  <img src="https://img.shields.io/badge/speech-on--device-green" alt="On-device speech">
  <img src="https://img.shields.io/github/license/ishan-crd/HandsFreeNotch" alt="License">
</p>

---

HandsFreeNotch is a voice command bar that lives in the MacBook notch. It is built to be fast
and light: speech recognition runs on the Mac, the everyday commands are matched with no model at
all, and a small model is only asked when a sentence is genuinely unusual.

```
hold ⌥ (right)   →   "open chrome"          →   Chrome is frontmost before you let go
                     "youtube lofi beats"   →   a YouTube search in your browser
                     "type on my way, five minutes" → typed into whatever has focus
                     "set volume to 30"     →   done
                     "find the cheapest flight to tokyo next friday"  →  handed to the screen agent
```

## How it stays fast

Every command goes through three tiers, and stops at the first one that can answer.

| tier | what | latency | cost |
|---|---|---|---|
| **0 · fast** | pattern matching over the transcript against the installed apps and a site list | < 1 ms | free |
| **1 · model** | Claude Haiku 4.5 (or a local Ollama model) returns one JSON action; no screenshot, no page text | ~300–600 ms | ≈ $0.0003 |
| **2 · agent** | [typesafe-computer-use](https://github.com/awlevin/typesafe-computer-use) reads the screen and clicks through it | seconds per step | ≈ $0.0002 / step |

Tier 0 runs on every partial transcript while you are still talking. The transcript is cut at
“and”, “then”, “and then”, “after that”, and each finished piece runs the moment its words settle
(300 ms), so

```
"open safari and search youtube and on youtube search faze rug"
```

opens Safari while you are still saying “search”, opens YouTube as you say “on youtube”, and
runs the search when you stop. App, site and key commands fire as soon as they are certain;
search and dictation wait until the sentence moves on, so “rock and roll” is one query.

Speech recognition is Apple's `SFSpeechRecognizer` with on-device recognition. The audio engine is
prepared at launch, so a key press starts capture in a few milliseconds and nothing leaves the Mac.

Idle cost is nothing: no timers, no hover tracking, no polling. The app sits at 0% CPU and about
25 MB until you hold the key.

## Install

macOS 14 or newer, Xcode 16 command line tools.

```bash
git clone https://github.com/ishan-crd/HandsFreeNotch.git
cd HandsFreeNotch
make install        # builds build/HandsFreeNotch.app, copies it to /Applications, launches it
```

Or `make run` to launch from the build folder, or `open Package.swift` to work in Xcode.

On first launch macOS asks for **Microphone** and **Speech Recognition**. Also allow the app under
**System Settings › Privacy & Security › Accessibility**: that is what lets it hear the push-to-talk
key system-wide and send keystrokes, scrolls and shortcuts to other apps. The notch opens on its
own to the Settings tab if anything is missing.

> macOS ties the Accessibility grant to the code signature, so an ad-hoc build has to be re-allowed
> after every rebuild. Run `scripts/make-cert.sh` once: it creates a local signing identity
> (“HandsFreeNotch Dev”) that `make` picks up automatically, and the grant then survives rebuilds.
> A real `CODESIGN_IDENTITY="Apple Development: …"` works too.

## Use

Hold **right ⌥ Option** (changeable to right ⌘, right ⌃, left ⌃ or fn in Settings), speak, release.
Or **tap** it once: the microphone stays open for chained commands until you tap again, say
“stop”, or go quiet for 30 seconds.
Click the notch to open the panel: recent commands with their timings, the command list, and
settings. The panel also has a text field to try commands by typing.

Commands can also come from a script, Raycast or Shortcuts:

```bash
/Applications/HandsFreeNotch.app/Contents/MacOS/HandsFreeNotch --say "open safari"
```

Each command's state changes go to the unified log:
`/usr/bin/log stream --level info --predicate 'subsystem == "com.ishan.HandsFreeNotch"'`.

Things the fast tier understands, with room for variation in wording:

| say | does |
|---|---|
| open spotify · launch chrome · switch to slack · open the settings | opens or activates the app; nicknames like “chrome”, “vs code”, “settings” work |
| open youtube · go to github.com · open github dot com slash ishan-crd · open slack in the browser | opens the site in your default browser |
| open this link · open copied link | opens the URL on the clipboard |
| (while on youtube.com) on youtube search faze rug | same site → navigates the front tab instead of opening another (Safari, Chrome, Arc, Brave, Edge) |
| search for best ramen near me · youtube lofi beats · look up everest on wikipedia · what is the capital of peru | web search (Google, YouTube, Wikipedia, GitHub, Amazon, Maps) |
| type hello team · press enter · press command shift t · select all · delete word | typing and keys into the focused app |
| new tab · close tab · reopen tab · next tab · go back · reload · zoom in · address bar · find | browser and window shortcuts |
| volume up · mute · set volume to 30 · max volume · brightness down | system controls |
| play · pause · next song · previous | media keys |
| scroll down · scroll up a lot · page down · top · bottom | scrolling under the cursor |
| quit spotify · hide chrome · minimize · close window · lock screen · sleep · screenshot · show desktop · mission control · spotlight · empty trash | apps and the Mac |
| open spotify then play · open chrome and then new tab and search for cats | chains; each step runs as soon as it is settled |
| cancel · never mind | does nothing |

Anything else goes to the model, which either picks one of the same actions or, when the request
needs clicking around inside an app (“reply to the last message”, “find the cheapest flight”),
hands it to the agent with the full goal.

## Free-form model: which one

Tier 0 handles the everyday commands for free. The model only sees sentences it cannot place.

| option | cost | setup |
|---|---|---|
| **Ollama, local** | $0, offline | `brew install ollama && ollama pull qwen2.5:1.5b`, then `HandsFreeNotch --use ollama` |
| **OpenRouter free models** | $0 (rate-limited: ~50 requests/day, 1000/day once the account has $10 of credit) | key from openrouter.ai/keys, then `HandsFreeNotch --set-key openrouter sk-or-…` |
| **Claude Haiku 4.5** | ≈ $0.001 per free-form command ($1 / $5 per million tokens) | `HandsFreeNotch --set-key sk-ant-…` |
| Off | $0 | `HandsFreeNotch --use off` — tier 0 only |

`HandsFreeNotch` here is `/Applications/HandsFreeNotch.app/Contents/MacOS/HandsFreeNotch`. Keys go in the
login keychain; the Settings tab in the notch does the same thing with a text field. Clicking a
red “not a command” pill opens Settings. `--model <name>` changes the model for the matching
provider, e.g. `--model qwen/qwen3.8-27b:free`; the OpenRouter default is
`nex-agi/nex-n2.5-mini:free`, and the request lists several other free models as fallbacks so a
model that is rate-limited upstream (common on the free tier) is skipped automatically.

## Settings

| setting | default | notes |
|---|---|---|
| Push to talk | right ⌥ | a modifier key, so holding it never types anything |
| Free-form model | Claude Haiku 4.5 | or **OpenRouter** (free models), **Ollama** (`qwen2.5:1.5b`, free and offline), or **Off** for tier 0 only |
| API keys | — | stored in the login keychain; `ANTHROPIC_API_KEY` / `OPENROUTER_API_KEY` in the environment or in `~/.config/handsfreenotch/.env` also work |
| Screen agent path | auto-detected | a checkout of typesafe-computer-use with `uv sync` done and its own `.env` |
| Launch at login | off | |

## Architecture

```
Sources/HandsFreeNotchCore          no UI; tested with `swift test`
  Speech/SpeechListener.swift       AVAudioEngine → SFSpeechRecognizer, partials + mic level
  Speech/HotkeyMonitor.swift        the push-to-talk modifier key
  Intent/Intent.swift               the action vocabulary
  Intent/Normalizer.swift           transcript → plain words; sequence splitting; number words
  Intent/Fuzzy.swift                "spot if i" ≈ "Spotify"
  Intent/AppIndex.swift             installed + running apps, nicknames
  Intent/SiteIndex.swift            site names → URLs, domain heuristics
  Intent/FastRouter.swift           tier 0
  Intent/LLMRouter.swift            tier 1: Anthropic and Ollama, one strict JSON schema
  Intent/AgentFallback.swift        tier 2: runs `clicker` and streams its output
  Actions/ActionRunner.swift        carries out an Intent
  Actions/Keys.swift                CGEvent keys, typing, scrolling, media keys
  Actions/SystemControl.swift       volume, sleep, trash, clipboard URL
  CommandPipeline.swift             hold → listen → route → act, with early firing and timings

Sources/HandsFreeNotch              the app
  Notch/                            notch window and shape (from NotchOS), panel, level bars
  App/                              delegate, settings, keychain
```

The notch window is a non-activating panel, so the app you are working in keeps keyboard focus
and synthesised keystrokes land there.

## Acknowledgements

The notch window, shape and event handling come from [NotchOS](https://github.com/ishan-crd/NotchOS),
itself built on [NotchDrop](https://github.com/Lakr233/NotchDrop). The three-tier idea and the
agent tier come from [typesafe-computer-use](https://github.com/awlevin/typesafe-computer-use).

## License

[MIT](./LICENSE)
