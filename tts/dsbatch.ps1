# dsubatch.ps1 - run MANY TTS commands inside ONE PowerShell process.
#
# WHY
#   The expensive part of talking to TTS was never the socket: it was spawning a fresh
#   PowerShell for every command (~470 ms) on top of the transport. This runs N commands
#   in one process.
#
# USAGE
#   powershell -NoProfile -File dsubatch.ps1 -Commands 'ping;;getState:93da54'
#   powershell -NoProfile -File dsubatch.ps1 -File C:\path\cmds.txt    # one command per line
#
# NOT SUPPORTED HERE: commands that need -TextFile (tabwrite / notepush / sync) --
# those already go through say.ps1 or a dedicated ds.ps1 call.
#
# NOTE: param() must stay the FIRST statement in this file; the config dot-source comes after.
param(
    [string]$Commands = '',
    [string]$File = '',
    [string]$Ds = ''
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($Ds -eq '') { $Ds = Join-Path $DshTts 'ds.ps1' }
$ErrorActionPreference = 'Continue'

$list = @()
if ($File -ne '') {
    if (-not (Test-Path -LiteralPath $File)) { Write-Host "ERR no such file: $File"; return }
    foreach ($l in [System.IO.File]::ReadAllLines($File, [System.Text.Encoding]::UTF8)) {
        $s = $l.Trim()
        if ($s -ne '' -and -not $s.StartsWith('#')) { $list += $s }
    }
} elseif ($Commands -ne '') {
    $list = @($Commands -split ';;' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
} else {
    Write-Host "ERR nothing to do: pass -Commands 'a;;b' or -File <path>"; return
}
if (-not (Test-Path -LiteralPath $Ds)) { Write-Host "ERR no ds.ps1 at $Ds"; return }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$n = 0
foreach ($c in $list) {
    $n++
    $t0 = $sw.ElapsedMilliseconds
    $out = & $Ds -Do $c 6>&1            # 6>&1 captures ds.ps1's Write-Host stream
    $ms = $sw.ElapsedMilliseconds - $t0
    Write-Host ("[{0,2}] {1}   ({2} ms)" -f $n, $c, $ms)
    foreach ($o in @($out)) { Write-Host ("      " + $o) }
}
Write-Host ("--- {0} commands in {1} ms (avg {2} ms, one PowerShell start total)" -f `
    $n, $sw.ElapsedMilliseconds, [int]($sw.ElapsedMilliseconds / [math]::Max(1, $n)))
