# test_i18n.ps1 - offline gate for the localisation mechanism in tts\lib\i18n.ps1.
#
# No TTS, no network, no spawn: it dot-sources the library and calls it (see the header of i18n.ps1 for
# why the mechanism does not live in the two CLI tools).
#
# WHAT IT PROVES, and why each control exists:
#   * the JSON and TSV escapes round-trip, including quotes, backslashes and newlines
#   * a save shaped like a real one (nested, duplicate values, empty values) scans to the expected rows
#   * DUPLICATE VALUES PAIR BY id, NOT BY VALUE - the single most dangerous failure mode: two cards that
#     happen to share a nickname must receive their own translations, not each other's
#   * fields that are not on the list survive untouched
#   * the patched text is still a valid save (re-parsed)
#   * NEGATIVE CONTROL 1: a save edited after the export is REFUSED (and nothing is changed)
#   * NEGATIVE CONTROL 2: a tsv missing a row is REFUSED
#   * and -Force does override the refusal, so the escape hatch works
#
# ASCII only on purpose: no CJK here means no BOM to lose.
param([string]$Root = '')
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\lib\i18n.ps1')

$failed = 0
function Check {
    param([string]$Name, $Ok, [string]$Hint = '')
    if ($Ok) { Write-Host ('PASS  ' + $Name) }
    else {
        Write-Host ('FAIL  ' + $Name + $(if ($Hint) { '  <- ' + $Hint } else { '' }))
        $script:failed++
    }
}
Add-Type -AssemblyName System.Web.Extensions
function Test-IsSaveJson([string]$Text) {
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue
    try { $null = $ser.DeserializeObject($Text); return $true } catch { return $false }
}

$fixture = Join-Path $Root 'tts\tests\fixtures\fake_save.json'
$raw = [System.IO.File]::ReadAllText($fixture, [System.Text.Encoding]::UTF8)
$fields = @('Nickname', 'Description', 'GMNotes')

# ---- 1. escapes ----
$nasty = 'he said "hi" \ then' + "`n" + 'a tab' + "`t" + 'end'
Check 'json escape round trip (quotes, backslash, newline, tab)' `
    ((ConvertFrom-JsonStringBody (ConvertTo-JsonStringBody $nasty)) -eq $nasty)
$flat = 'tab' + "`t" + 'nl' + "`n" + 'bs\ end'
Check 'tsv flat round trip' ((ConvertFrom-I18nFlat (ConvertTo-I18nFlat $flat)) -eq $flat)

# ---- 2. the scan ----
$matches = Get-I18nMatch -Raw $raw -Fields $fields
Check 'fixture scans to 11 translatable fields' ($matches.Count -eq 11) ('got ' + $matches.Count)
$nonEmptyIds = @()
for ($i = 0; $i -lt $matches.Count; $i++) {
    if ((ConvertFrom-JsonStringBody $matches[$i].Groups[2].Value) -ne '') { $nonEmptyIds += ($i + 1) }
}
Check '7 of them are non-empty' ($nonEmptyIds.Count -eq 7) ('got ' + $nonEmptyIds.Count)
Check 'empty values still get a row (ids stay dense)' `
    ((Get-I18nTsvLines -SaveName 'x' -Matches $matches).Count -eq 15) `
    'header is 4 lines + one row per match'

# ---- 3. a translator's tsv: duplicate values must get DIFFERENT targets ----
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# test tsv')
$lines.Add('id' + "`t" + 'field' + "`t" + 'source' + "`t" + 'target')
for ($i = 0; $i -lt $matches.Count; $i++) {
    $id = $i + 1
    $field = $matches[$i].Groups[1].Value
    $src = ConvertTo-I18nFlat (ConvertFrom-JsonStringBody $matches[$i].Groups[2].Value)
    $tgt = ''
    if ($src -ne '') {
        switch ($id) {
            1 { $tgt = 'A-ONE' }      # both id 1 and id 4 are "Draw two cards."
            4 { $tgt = 'B-FOUR' }
            default { $tgt = 'Z' + $id + '-NIE\tX' }   # a literal \t in the TSV; must arrive as a real tab
        }
    }
    $lines.Add(([string]$id) + "`t" + $field + "`t" + $src + "`t" + $tgt)
}
$rows = Read-I18nTsv -Lines $lines
Check 'tsv reader keeps every row' ($rows.Count -eq 11) ('got ' + $rows.Count)

$r = Merge-I18nText -Raw $raw -Fields $fields -Rows $rows
Check 'merge replaces exactly the non-empty rows' ($r.replaced -eq 7) ('replaced ' + $r.replaced)
Check 'merge reports no mismatch on an untouched save' ($r.mismatches -eq 0) (($r.log -join ' | '))
Check 'duplicate values pair by id, not by value' `
    (($r.text -match '"Nickname": "A-ONE"') -and ($r.text -match '"Nickname": "B-FOUR"')) `
    'the two "Draw two cards." cards must not share one translation'
Check 'a tab inside a target arrives as a real tab' ($r.text.Contains('\tX'))
Check 'fields not on the list survive untouched' `
    (($r.text -match '"Name": "Card"') -and ($r.text -match '"TurnOrder"') -and ($r.text -match '"VersionNumber": 13'))
Check 'patched text is still a valid save (re-parsed)' (Test-IsSaveJson $r.text)

# ---- 4. NEGATIVE CONTROL 1: the save changed after the export ----
$edited = $raw.Replace('"Nickname": "Unused card"', '"Nickname": "Someone renamed this"')
Check 'the edit used for the negative control really changed the file' ($edited -ne $raw)
$r2 = Merge-I18nText -Raw $edited -Fields $fields -Rows $rows
Check 'NEGATIVE: a save edited after the export is refused' `
    (($r2.mismatches -gt 0) -and ($r2.text -eq $edited)) `
    'must refuse AND leave the text alone'
$r2f = Merge-I18nText -Raw $edited -Fields $fields -Rows $rows -Force
Check 'FORCE: the escape hatch does override the refusal' (($r2f.mismatches -gt 0) -and ($r2f.text -ne $edited))

# ---- 5. NEGATIVE CONTROL 2: the tsv is missing a row ----
$short = New-Object System.Collections.Generic.List[string]
foreach ($l in $lines) { if (-not $l.StartsWith('9' + "`t")) { $short.Add($l) } }
$r3 = Merge-I18nText -Raw $raw -Fields $fields -Rows (Read-I18nTsv -Lines $short)
Check 'NEGATIVE: a tsv missing a row is refused' `
    (($r3.mismatches -gt 0) -and ($r3.text -eq $raw)) `
    'a missing id means the tsv and the save are out of step'

if ($failed -gt 0) { Write-Host ("$failed i18n case(s) failed"); exit 1 }
Write-Host 'all i18n cases passed'
exit 0
