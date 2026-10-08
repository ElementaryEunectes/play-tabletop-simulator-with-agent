# tts-agent — an AI plays the board game, you make the decisions

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
opens those in Notepad). The launcher moves the session into this folder, pins `$DSH_HOME` and then
starts DSH; if `dsh` is missing it stops and tells you how to install it.

**First time, in this order**: Windows → **Node.js** → `npm i -g @deepseek-ai/dsh` → **Tabletop
Simulator** (Steam, paid) + subscribe to the target mod → **bake the bridge into a save**
(`tts\docs\BOOTSTRAP.md`) → double-click `start.cmd` → load that save in TTS.
⚠️ No game rules or card text ship with this repository (that is one game's content, kept under
`local\games\`).

## How to read this repo (never read it all — read by role)

| What you want | Read |
|---|---|
| Platform discipline (cross-project, auto-injected) | `AGENTS.md` |
| **Doing TTS work**: tool map, the End Turn button, bridge traps, the one-line conventions | `tts\docs\TTS_RULES.md` |
| Starting a round | `tts\docs\PLAY.md` (generic per-turn card) + `local\games\<game>\STATE.md` (that match's state, not shipped); `tts\docs\BOOTSTRAP.md` only when changing mods |
| This game's rules, skills and dice faces | `local\games\<game>\FLOW.md` (not shipped) · card text in `cache\` |
| Script inventory (core / dormant / rename-time reference graph) | `tts\docs\TTS_RULES.md（§二 工具清单）` |
| New game, cold start | `tts\docs\BOOTSTRAP.md` |
| **How a human uses it** (hand this to the player) | `tts\docs\USER_GUIDE.md` (Chinese) |
| Doc and directory index | `tts\docs\README.md` |
| **How to verify an edit** | `tts\check_ps1.ps1` (recursive BOM + real parser) → `tts\tests\test_*.ps1` (**no TTS needed**) |

## What it needs

1. **Windows + PowerShell 5.1** — the scripts use `System.Drawing`, WinRT and GDI screen grabs.
2. **DSH**, the agent harness that provides the tool calls and the sentinel wake-up mechanism.
   This work area *is* `$DSH_HOME` for it.
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
`AGENTS.md` (about 2.9 KB) plus **the `AGENTS.md` in *your* harness home**. That second file is
**not part of this repository** — it is the harness's *user-global* instruction file
(`$DSH_HOME\AGENTS.md`). If `DSH_HOME` points at this repository, the two deduplicate into one
(which is what `start-agent.ps1` arranges).

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

1. **Commit before you edit**: `git add -A && git commit -m "before: xxx"`. Undo with
   `git checkout -- <file>`.
2. **After editing any `.ps1`, run**
   `powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1`
   It adds the UTF-8 BOM where it is missing and syntax-checks every script with the real
   parser, recursively — including `tts\tests\`.
3. ⛔ **Never edit live code with a bulk string replace.** That is how 22 scripts broke here at
   once: the replacement text was expanded by PowerShell, quotes were eaten, and the BOM
   multiplied to three copies. Back up first, edit precisely, then validate file by file.
4. **A `.ps1` containing Chinese must be UTF-8 *with* BOM.** PowerShell 5.1 reads a BOM-less
   file as ANSI, the Chinese becomes mojibake, and the parser dies with a misleading error
   ("missing closing parenthesis"). New throwaway scripts should keep their comments ASCII.
5. **Passing a syntax check does not mean the script works.** A whole class of bug here was a
   `param()` default of `''` that was never resolved: the script started, then wrote to an empty
   path. `tts\tests\test_param_backfill.ps1` catches that class.
6. **A validator needs a positive control.** Two tools in this repo were themselves broken while
   reporting success — a BOM rewriter whose condition was inverted, and a regex anchored to the
   start of a line that therefore matched nothing. Feed them a deliberately broken probe and
   watch them fail before you trust them.
7. **Test offline.** `tts\tests\test_diff_index.ps1` needs no TTS and no save (a stub stands in
   for `live_index.ps1`, and the fixtures are synthetic), so the diff chain can be verified with
   the game closed.

## Status

- ✅ **31/31 `.ps1` parse clean** (`check_ps1.ps1`, recursive), BOM present everywhere.
- ✅ **Offline tests**: `tts\tests\test_diff_index.ps1`, `tts\tests\test_param_backfill.ps1`.
- ✅ **Guardrails** on `roll.ps1`, `play.ps1 -Apply` and `install_save2.ps1 -DryRun`.
- ✅ **No personal paths** anywhere in the tree: `tts\config.ps1` is the only resolver.
- ⏸ A match is **suspended**; its status and resume steps are **not in the repository** (see `local\games\_current.md`).
- ⚡ **Per-turn cost** (measured 2026-10-08): open a turn with the single command
  `tts\play.ps1 turn` — about **1.5s**, replacing the ~2.9s of `status` + `roll` + `tabread`.
  `say.ps1` costs **0.79s** per message (was ~1.7s, two child processes fewer). **Starting one
  PowerShell process costs a flat ~0.35s, so merging commands is what saves time** — TTS round
  trips are not the bottleneck.
- 🧾 `LICENSE` = **MIT** (see below).

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
That does **not** cover: **Tabletop Simulator** (Berserk Games), **Dice Throne** and its card
text/art (Roxley / MINDVG), or the Workshop mod itself. No game rules or card text ship with this repository (the self-use notes live in `local\games\`); that file is a
personal play-aid that transcribes parts of the card text; **no card art is included** — the
images and the card-text cache live in `cache\`, which is not committed.
`tts\validate_lua.js` needs **`luaparse`** (MIT), which is not vendored here: run
`npm i luaparse`, or set `LUAPARSE_DIR`.
