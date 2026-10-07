# start-agent.ps1 - launch DSH with THIS folder as the project workspace.
#
# WHY THIS STILL EXISTS (two live reasons; the third became obsolete on 2026-10-08)
#   1. SESSION CWD. The project chain is injected only while the working directory is inside this
#      repo - the harness walks project-root -> cwd looking for AGENTS.md. Start dsh from anywhere
#      else and the project charter is simply NOT injected. That is why this launcher Set-Location's
#      to the repo root.
#   2. AGENTS.md DEDUPLICATION. With $DSH_HOME = this folder, the harness's "user global"
#      instruction file is <repo>\AGENTS.md - the SAME absolute path as the project one - so the two
#      dedupe into one injection. Without it you pay both: ~2.9 KB extra on EVERY request.
#   COST of reason 2: $DSH_HOME is also the harness's home (sessions\, credentials, profiles\).
#      Pinning it moves that state here - free on a fresh machine, a migration on one that already
#      has state. THIS machine has not migrated, so it does not use the pin.
#
#   OBSOLETE REASON (it was reason 1 before 2026-10-08): "if the shell still has the old $DSH_HOME
#      (e.g. C:\Users\<you>\.dsh), every script silently reads/writes a folder that no longer
#      exists". tts\config.ps1 now resolves the workspace by first asking whether $DSH_HOME really
#      contains tts\config.ps1 and otherwise falling back to its OWN location - so the scripts heal
#      themselves. Proof: a whole session ran with $DSH_HOME still pointing at ~\.dsh and every
#      script resolved this repo correctly, including the new game variables.
#
# USAGE (from anywhere):
#   powershell -NoProfile -ExecutionPolicy Bypass -File <project>\start-agent.ps1
#   ...then run `dsh web` (or plain `dsh`) in that same window.
#
# NOTE: param() must stay the first statement; nothing may precede it.
param(
    [switch]$NoLaunch,
    [string]$DshCommand = 'dsh web'
)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:DSH_HOME = $root
Write-Host ("DSH_HOME = " + $env:DSH_HOME)
Write-Host ("project  = " + $root)
if (-not (Test-Path (Join-Path $root 'tts\config.ps1'))) {
    Write-Host "WARN: tts\config.ps1 not found under this project root." -ForegroundColor Yellow
}
if ($NoLaunch) { Write-Host "(-NoLaunch: set the variable only; nothing started)"; return }
Write-Host ("launching: " + $DshCommand)
Set-Location -LiteralPath $root
& powershell -NoProfile -Command $DshCommand
