# i18n_apply.ps1 - put a translator's TSV back into a TTS save, replacing only the text bytes.
#
# Thin CLI wrapper: the mechanism is tts\lib\i18n.ps1 (contract + rationale in tts\docs\I18N.md).
#
# EXPLICIT SWITCH, per repository rule: without -Apply this only reports what it WOULD do.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\i18n_apply.ps1 -Save <save.json> -In <zh.tsv> -Out <patched.json>
#   ... -Apply
#
# ASCII only on purpose: no CJK here means no BOM to lose.
param(
    [string]$Root = '',
    [string]$Save = '',
    [string]$In = '',
    [string]$Out = '',
    [string[]]$Fields = @('Nickname', 'Description', 'GMNotes'),
    [switch]$Apply,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
. (Join-Path $Root 'tts\lib\i18n.ps1')

if ($Save -eq '') { Write-Host 'ERR -Save is required (the same file you exported from)'; exit 2 }
if ($In -eq '') { Write-Host 'ERR -In is required (the translator TSV)'; exit 2 }
if (-not (Test-Path -LiteralPath $Save)) { Write-Host ('ERR no such save: ' + $Save); exit 2 }
if (-not (Test-Path -LiteralPath $In)) { Write-Host ('ERR no such tsv: ' + $In); exit 2 }
if ($Out -eq '') { $Out = Join-Path $DshCache 'i18n_patched.json' }
$same = $false
try { $same = ([System.IO.Path]::GetFullPath($Out) -eq [System.IO.Path]::GetFullPath($Save)) } catch { }
if ($same -and -not $Force) { Write-Host 'ERR -Out is the input save; refusing to overwrite it without -Force'; exit 2 }

$raw = [System.IO.File]::ReadAllText($Save, [System.Text.Encoding]::UTF8)
$rows = Read-I18nTsv -Lines ([System.IO.File]::ReadAllLines($In, [System.Text.Encoding]::UTF8))
$r = Merge-I18nText -Raw $raw -Fields $Fields -Rows $rows -Force:$Force

Write-Host ('save        : ' + (Split-Path $Save -Leaf) + '   ' + ('{0:N0}' -f $raw.Length) + ' bytes')
Write-Host ('scanned     : ' + $r.scanned + ' text field(s)')
Write-Host ('tsv rows    : ' + $rows.Count + '   (empty target: ' + $r.emptyTarget + ')')
Write-Host ('to replace  : ' + $r.replaced + '   (unchanged: ' + $r.unchanged + ')')

if ($r.mismatches -gt 0) {
    if (-not $Force) {
        Write-Host ('REFUSING    : ' + $r.mismatches + ' row(s) do not line up with this save.')
        foreach ($l in $r.log) { Write-Host ('  ' + $l) }
        Write-Host 'the save changed since the export, or the tsv was edited - re-export and merge, or pass -Force.'
        exit 3
    }
    Write-Host ('WARNING     : ' + $r.mismatches + ' mismatch(es) ignored because -Force is set')
    foreach ($l in $r.log) { Write-Host ('  ' + $l) }
}

if (-not $Apply) {
    Write-Host 'REPORT ONLY (no -Apply): nothing written. Add -Apply to write the patched save.'
    exit 0
}

# Prove the output is still a save. Reading is safe - it is writing that corrupts, which is exactly why
# nothing here ever parses-and-reserialises the file.
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$ok = $false
try { $null = $ser.DeserializeObject($r.text); $ok = $true } catch { $ok = $false }
if (-not $ok) { Write-Host 'ERR the patched text is not valid JSON - nothing written'; exit 4 }

$outDir = Split-Path -Parent $Out
if ($outDir -ne '' -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
[System.IO.File]::WriteAllText($Out, $r.text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('wrote       : ' + $Out + '   ' + ('{0:N0}' -f $r.text.Length) + ' bytes  (delta ' +
            ('{0:+#;-#;0}' -f ($r.text.Length - $raw.Length)) + ')')
Write-Host 're-parsed   : OK - still valid save JSON'
Write-Host 'next        : put it in Saves\ and Save & Load in TTS (this never touches Saves\ itself)'
