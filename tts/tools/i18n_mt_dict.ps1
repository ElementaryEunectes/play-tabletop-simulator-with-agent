# i18n_mt_dict.ps1 - a translator that satisfies the TSV contract using a dictionary, not a model.
#
# Thin CLI wrapper: the logic is Read-I18nDictionary / Convert-I18nTsvWithDict in tts\lib\i18n.ps1, so the
# offline gate can call it directly instead of spawning a PowerShell child.
#
# WHY A DICTIONARY AND NOT THE ADAPTER IN THE DOCS: the contract in tts\docs\I18N.md is only "read TSV,
# write TSV, fill column 4", and the documented first choice (Transformers.js) cannot be installed on this
# machine (no npm network access). Shipping an adapter that was never run would be worse than shipping
# nothing. And this is not a consolation prize: for the part of localisation that is TERMINOLOGY - card
# names, keywords, recurring phrases - a dictionary beats a model, because it is consistent and
# reviewable. For prose, plug a real engine into the same contract.
#
# Dictionary file: TSV, `source<TAB>target`, one per line, `#` comments allowed.
# LONGEST SOURCE WINS, so list a specific phrase alongside the general words it contains.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\i18n_mt_dict.ps1 -In text.tsv -DictFile terms.tsv -Out zh.tsv
#
# ASCII only on purpose: no CJK here means no BOM to lose (the TSV and the dictionary are UTF-8).
param(
    [string]$Root = '',
    [string]$In = '',
    [string]$Out = '',
    [string]$DictFile = '',
    [switch]$CaseSensitive,
    [switch]$AllowInside
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
. (Join-Path $Root 'tts\lib\i18n.ps1')

if ($In -eq '') { Write-Host 'ERR -In is required (the TSV from i18n_export.ps1)'; exit 2 }
if (-not (Test-Path -LiteralPath $In)) { Write-Host ('ERR no such tsv: ' + $In); exit 2 }
if ($DictFile -eq '') { Write-Host 'ERR -DictFile is required (source<TAB>target per line)'; exit 2 }
if (-not (Test-Path -LiteralPath $DictFile)) { Write-Host ('ERR no such dictionary: ' + $DictFile); exit 2 }
if ($Out -eq '') { $Out = Join-Path $DshCache 'i18n_zh.tsv' }

$terms = Read-I18nDictionary -Path $DictFile
Write-Host ('dictionary: ' + @($terms).Count + ' term(s) from ' + (Split-Path $DictFile -Leaf))
$mode = 'exact rows only'
if ($AllowInside) { $mode = 'exact rows, then terms inside sentences' }
Write-Host ('mode      : ' + $mode + '   (a whole sentence belongs to an engine - see the header)')
$lines = [System.IO.File]::ReadAllLines($In, [System.Text.Encoding]::UTF8)
$r = Convert-I18nTsvWithDict -Lines $lines -Terms $terms -CaseSensitive:$CaseSensitive -AllowInside:$AllowInside

$outDir = Split-Path -Parent $Out
if ($outDir -ne '' -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
[System.IO.File]::WriteAllLines($Out, $r.text, (New-Object System.Text.UTF8Encoding($false)))

$pct = 0
if ($r.total -gt 0) { $pct = [int][Math]::Round(100.0 * ($r.exact + $r.inside) / $r.total) }
Write-Host ('rows      : ' + @($r.text).Count + '   translatable: ' + $r.total)
Write-Host ('exact     : ' + $r.exact + '   term-inside: ' + $r.inside + '   untouched: ' + $r.missed)
Write-Host ('coverage  : ' + $pct + '%')
Write-Host ('wrote     : ' + $Out)
if ($r.missed -gt 0) { Write-Host 'untouched rows keep their original text (empty target) - add terms and re-run' }
Write-Host 'next      : tts\tools\i18n_apply.ps1 -In <this file> -Out <patched.json> [-Apply]'
