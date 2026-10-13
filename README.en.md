# Play Tabletop Simulator with an agent — you make the decisions

[![gates](https://github.com/ElementaryEunectes/play-tabletop-simulator-with-agent/actions/workflows/gates.yml/badge.svg)](https://github.com/ElementaryEunectes/play-tabletop-simulator-with-agent/actions/workflows/gates.yml)

> 🤖 **The code and docs here were written mostly by an AI agent (DSH)** — the human made the decisions,
> reviewed and signed off, and every commit carries the *why*. That is not a disclaimer, it is the thing
> this project set out to test: **can an agent leave behind work that is hand-over-able, gate-able and
> reproducible?** Discipline ⇒ `CONTRIBUTING.md` §5.4 (**new files say who wrote them, in a header comment**).

A work area for having an AI play a board game **inside Tabletop Simulator**. The human only
makes **decisions** and clicks **End Turn**; every other piece movement is done by the agent
through a message bridge into the running game.

This repository is the **game-agnostic toolkit** (bridge, scripts, workflow, discipline) - that is
what is open source. Anything true of only one game (state, rules, card text, card library, hands)
is **not** shipped; which game is being played right now is local information, see
`local\games\_current.md`.

> ⚠️ This repository holds **what you need to run it** — no credentials, sessions, logs, caches
> or archives (all of that is in `.gitignore`).
> 📖 The run-time documents are written in Chinese (the game's own terms are Chinese); **every
> code comment and the whole test suite are English**.

## How to start (double-click `start.cmd`)

Double-click **`start.cmd`** in the repository root — do **not** double-click the `.ps1` (Windows
opens those in Notepad). The launcher moves the session into this folder and then starts DSH; by
default it leaves `$DSH_HOME` **untouched** and sets no environment variable, so the harness home
`AGENTS.md` (if present) **is still injected** — the launcher prints whether it was. To empty that
slot for THIS project only, fill in `$ProjectDshProfile` in `start-agent.ps1` (or pass
`-DshProfile <name>`; mechanism ⇒ `tts\docs\INJECTION.md`, section 4 plan A'). If `dsh` is missing it
stops and tells you how to install it.

**First time, in this order**: Windows → **Node.js** → `npm i -g @deepseek-ai/dsh` → **Tabletop
Simulator** (Steam, paid) + subscribe to the target mod → **bake the bridge into a save**
(`tts\docs\BOOTSTRAP.md`) → double-click `start.cmd` → load that save in TTS.
⚠️ No game rules or card text ship with this repository (that is one game's content, kept under
`local\games\`).

### What a first run costs (know this before you start)

**Money**: Tabletop Simulator (Steam, paid) + the target mod (Workshop, usually free) + **nothing else** —
the bridge, the sentinel and every script run **locally**; no service fees beyond DSH's own model calls.

| Step | Estimate | Note |
|---|---|---|
| Node.js + `npm i -g @deepseek-ai/dsh` | ~5 min | once |
| TTS + subscribe to the target mod | ~15 min | mostly download time |
| **Bake the bridge into a save** (`BOOTSTRAP.md` section 2) + have the player reload | ~10 min | same path for every new match |
| **Teaching one mod the first time**: object index + map · card library (optional) · **turn calibration** | **~30–60 min** | ⭐ the real work of a "generic toolkit" |
| Every later session | **~5 min** | re-bake, reload, re-arm the watcher (`PLAY.md`) |
| **Total to a first completed round** | **≈1–1.5 h** | that is the bar: can a stranger finish a round within an hour |

⚠️ **Four honest prerequisites**:
1. **DSH is required** (this agent harness) — it provides the sentinel and the tool calls; without it
   these scripts are just scripts and the turn hand-over degrades to manual polling.
2. **Game-specific verbs need a "control layer"** (`local\games\<game>\control\play.ps1`, see
   `BOOTSTRAP.md` section 2). Without one, `play.ps1 status` still works (bridge version, object count,
   seated players, whose turn), but `play.ps1 <game verb>` replies `NO PART` and points at that section.
3. **Changing mods means redoing the turn calibration** (seating coordinates differ per mod):
   `tts\tools\turn_calib.ps1 -Discover` + `-Answer`, about 5 minutes.
4. **One of the 7 offline gates needs an extra dependency**: `bridge primitives (Lua)` runs the bridge
   under `fengari`, a Lua VM in JavaScript (kept locally in `local\scratch\luatest`). Without it that
   gate prints **`NOT RUN` — which is not a failure** — and the other 6 still run. To run all 7:
   `npm i fengari` into that directory, or point `FENGARI_DIR` at it.

## How to read this repo (never read it all — read by role)

| What you want | Read |
|---|---|
| Platform discipline (cross-project, auto-injected) | `AGENTS.md` |
| **Doing TTS work**: the End Turn ruling, capability limits, card identity, TTS-specific traps, the one-line conventions | `tts\docs\TTS_RULES.md` |
| Starting a round | `tts\docs\PLAY.md` (generic per-turn card) + `local\games\<game>\STATE.md` (that match's state, not shipped); `tts\docs\BOOTSTRAP.md` only when changing mods |
| This game's rules, skills and dice faces | `local\games\<game>\FLOW.md` (not shipped) · card text in `cache\` |
| Script inventory (core / dormant / rename-time reference graph) · editing the in-game Lua · pre-write checks | `tts\docs\MAINTENANCE.md` sections 5-7 |
| New game, cold start | `tts\docs\BOOTSTRAP.md` |
| **How a human uses it** (hand this to the player) | `tts\docs\USER_GUIDE.md` (Chinese) |
| Doc and directory index | `tts\docs\README.md` |
| **How to verify an edit** | `tts\check_ps1.ps1` (recursive BOM + real parser) → `tts\tests\test_*.ps1` (**no TTS needed**) |

## What it needs

1. **Windows + PowerShell 5.1** — the scripts use `System.Drawing`, WinRT and GDI screen grabs.
2. **DSH**, the agent harness that provides the tool calls and the sentinel wake-up mechanism.
   Harness home and work area are two different things: by default they are separate, and only
   `-RepoAsHome` makes this repository the `$DSH_HOME`.
3. **Tabletop Simulator** plus the target mod. `tts\lua\dsh_global.lua` is injected into a save
   by `install_save2.ps1` and becomes the bridge.
4. **Node.js** — only for `tts\validate_lua.js`, which must be run before touching the Lua.
   It needs `luaparse`; `cache\` is not committed, so run `npm i luaparse` (or set `LUAPARSE_DIR`).

## On a new machine (**first step after cloning**)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\doctor.ps1      # read-only check + injection cost
powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1   # every script: BOM + real parser
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1
```

`doctor.ps1` also works out **how many bytes get injected on every request**: this repository's
`AGENTS.md` (about 1.9 KB) plus **the `AGENTS.md` in *your* harness home**. That second file is
**not part of this repository** — it is the harness's *user-global* instruction file
(`$DSH_HOME\AGENTS.md`). If `DSH_HOME` points at this repository (which only `-RepoAsHome` arranges),
the two deduplicate into one.

⚠️ `.gitattributes` (`* -text`) **freezes line endings and encoding**: a clone is byte-identical
to what was committed. **Do not switch it to `text=auto`** — that rewrites every stored blob
once and can break the UTF-8 BOM that `.ps1` files require.

## Path configuration (never write your user name into a script again)

Every machine-specific path is resolved once, in **`tts\config.ps1`**; the other scripts only
reference its variables:

```powershell
$env:DSH_HOME       = 'D:\somewhere\tts-agent'  # workspace root (default: the parent of tts\)
$env:TTS_SAVES_DIR  = 'D:\...\Saves'            # TTS saves folder
$env:TTS_IMAGES_DIR = 'D:\...\Mods\Images'      # TTS image cache
```

⚠️ **`param()` must be the first statement of a script**, and the config dot-source must come
**after** it. Never reference config variables inside `param()` defaults — they are evaluated
before the dot-source runs. The correct pattern is a default of `''` plus a backfill *after*
the dot-source, and `tts\tests\test_param_backfill.ps1` enforces exactly that.

## Guardrails on the destructive verbs

- **`roll.ps1` — intent is mandatory.** `-Roll` throws the dice, `-NoRoll` only reads the faces.
  A bare call prints a usage error and exits 2 **without touching TTS**: a throw cannot be
  undone, and those are the opponent's dice. (`play.ps1 roll` behaves the same way: read-only
  unless you pass `-Roll`.)
- **`play.ps1 ... -Apply` is the only thing that writes HP/CP.** Add `-WhatIf` and it prints the
  exact change — `WILL WRITE  HP moon 26 -> 22  (-4)` — and writes nothing. Every real write is
  read back, and a mismatch is a hard `BAD DATA` stop.
- **`install_save2.ps1`**, the only script allowed to write a save file, has `-DryRun`.
- Everything else is read-only.

## Code rules (this repository paid for every one of them)

1. **Commit before you edit** (`git checkout -- <file>` undoes it) · ⛔ **never edit live code with a bulk string replace** (that is how 22 scripts broke at once here) · a `.ps1` containing Chinese must be UTF-8 **with** BOM (5.1 reads a BOM-less file as ANSI → mojibake → a misleading parse error).
2. **After editing any `.ps1`, run `tts\check_ps1.ps1`** (adds the BOM recursively and syntax-checks with the real parser). **Passing a syntax check does not mean the script works** — the `param()` default of `''` that was never resolved is caught by the `param backfill` gate inside `tts\tests\run_all.ps1`.
3. **A validator needs a positive control** — two tools here were themselves broken while reporting success. Feed them a deliberately broken probe before you trust them. Full rules ⇒ **[`CONTRIBUTING.md`](CONTRIBUTING.md)**; this machine's sandbox/encoding ⇒ `tts\docs\MAINTENANCE.md` §0.

## Status

- ✅ **Every `.ps1` under `tts\` parses clean** (`check_ps1.ps1`, recursive), BOM present · **no personal paths** (tts\config.ps1 is the only resolver) · `LICENSE` = **MIT**.
- ✅ **7 offline gates, no TTS needed**: one entry point, `tts\tests\run_all.ps1` (list ⇒ `CONTRIBUTING.md` §3) · guardrails on `roll.ps1`, `play.ps1 -Apply`, `install_save2.ps1 -DryRun`.
- ⏸ A match is **suspended**; its status and resume steps are **not in the repository** (see `local\games\_current.md`).
- ⚡ **Per-turn cost** (measured 2026-10-08): open a turn with the single command `tts\play.ps1 turn` — about **1.5s** (was ~2.9s for `status` + `roll` + `tabread`); `say.ps1` costs **0.79s** per message. **Starting one PowerShell process costs a flat ~0.27s (271 ms — the authoritative baseline lives in `tts\docs\MAINTENANCE.md` section 1b), so merging commands is what saves time** — TTS round trips are not the bottleneck.

## Related work (prior art)

The full survey — key facts per project, and what we did and did not adopt — is in
[`tts\docs\PRIOR_ART.md`](tts/docs/PRIOR_ART.md) (Chinese). Summary:

- **[Smirk1921/tts-toolkit](https://github.com/Smirk1921/tts-toolkit)** (MIT) — a mod-creator
  toolchain whose **hub daemon owns the single TTS connection on 39997 and fans it out** to CLI,
  VSCode and **MCP agents**, plus byte-identical save pack/unpack, **in-game Lua tests** and
  Workshop publishing. We did **not** adopt it (our retry loop is stable enough and adopting it is
  a protocol change), but it solves the same "who holds 39998" problem we hand-rolled around.
  Companion extension: [tts-lua-hub](https://github.com/Smirk1921/tts-lua-hub).
- **[libin7099901/TabletopSimulatorCompanion](https://github.com/libin7099901/TabletopSimulatorCompanion)**
  — the only complete "LLM × TTS" project, but it only answers rules questions; our
  "read the PDF URL out of the save" trick comes from it.
- **[rolandostar/tts-editor](https://github.com/rolandostar/tts-editor)** (Node) ·
  **[LucasOe/tts-external-api](https://github.com/LucasOe/tts-external-api)** (Rust) — the two
  independent reference implementations of the External Editor API; we speak the same protocol.
- **[cloudwu/cardocr](https://github.com/cloudwu/cardocr)** — the card-OCR/VLM route, which is our
  contrast case: we read the 40-character `FaceURL` hash instead, which is free and deterministic.
- **[pr1m8/haive-games](https://pr1m8.github.io/haive-games/overview.html)** — an LLM board-game
  agent framework we deliberately did **not** install: it binds its own environment, so wiring it
  in would give a mirror state that disagrees with the real table.
- Academic: arXiv [2510.25595](https://arxiv.org/abs/2510.25595) (communication and verification
  under information asymmetry — we adopted only its training-free verifier half) ·
  [Tabletop Games Framework](https://rdgain.github.io/assets/pdf/TAG.pdf) · BALROG.

**Where we sit**: as of 2026-10-08 there is still **no public project where an AI plays a full
board game inside Tabletop Simulator as a player**. What exists is either tooling/plumbing
(tts-toolkit), rules Q&A (Companion), or a different platform. What this project adds is the
**player layer**: semantic state reading, hidden-information discipline, a per-turn token/time
budget, and a human/AI split where the human only decides and clicks End Turn.

## License and third parties

This repository's **code and documentation** are MIT licensed — see `LICENSE`,
Copyright (c) 2026 ElementaryEunectes.
That does **not** cover **any Steam Workshop mod you load into TTS**: a mod's card text, artwork and
rulebook belong to **their respective rights holders** (Tabletop Simulator itself belongs to Berserk
Games). **None of that content ships with this repository** — this machine's own play-aid lives in
`local\games\` (gitignored; it transcribes parts of some card text and **includes no card art**), and the
card-text and image caches live in `cache\`, neither of which is committed.
> ⚠️ **This repository names no specific mod**: every document writes `<game>` or a description instead.
> The gate `tts\tests\test_agents_hygiene.ps1` enforces that character by character.
`tts\validate_lua.js` needs **`luaparse`** (MIT), which is not vendored here: run
`npm i luaparse`, or set `LUAPARSE_DIR`.
