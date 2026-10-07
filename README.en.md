# tts-agent — an AI plays the board game, you make the decisions

A work area for having an AI play a board game **inside Tabletop Simulator**. The human only
makes **decisions** and clicks **End Turn**; every other piece movement is done by the agent
through a message bridge into the running game. The current game is **Dice Throne**.

> ⚠️ This repository holds **what you need to run it** — no credentials, sessions, logs, caches
> or archives (all of that is in `.gitignore`).
> 📖 The run-time documents are written in Chinese (the game's own terms are Chinese); **every
> code comment and the whole test suite are English**.

## How to read this repo (never read it all — read by role)

| What you want | Read |
|---|---|
| Platform discipline (cross-project, auto-injected) | `AGENTS.md` |
| **Doing TTS work**: tool map, the End Turn button, bridge traps, the one-line conventions | `tts\docs\TTS_RULES.md` |
| Starting a round | `tts\docs\CURRENT.md` → `tts\docs\<game>_STATE.md` → `tts\docs\PLAY.md` |
| This game's rules, skills and dice faces | `tts\docs\DICETHRONE_FLOW.md` · card text in `cache\dicethrone_cards.md` |
| Script inventory (core / dormant / rename-time reference graph) | `tts\SCRIPTS.md` |
| New game, cold start | `tts\docs\BOOTSTRAP.md` |
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
- ⏸ The Dice Throne match is **suspended**; how to resume is in `tts\docs\DICETHRONE_STATE.md`.
- 🧾 `LICENSE` = **MIT** (see below).

## License and third parties

This repository's **code and documentation** are MIT licensed — see `LICENSE`,
Copyright (c) 2026 ElementaryEunectes.
That does **not** cover: **Tabletop Simulator** (Berserk Games), **Dice Throne** and its card
text/art (Roxley / MINDVG), or the Workshop mod itself. `tts\docs\DICETHRONE_FLOW.md` is a
personal play-aid that transcribes parts of the card text; **no card art is included** — the
images and the card-text cache live in `cache\`, which is not committed.
`tts\validate_lua.js` needs **`luaparse`** (MIT), which is not vendored here: run
`npm i luaparse`, or set `LUAPARSE_DIR`.
