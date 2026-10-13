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

# ---- 6. the image half (tts\lib\i18nimg.ps1): cache-name mapping, url scan, redraw, size preserved ----
. (Join-Path $Root 'tts\lib\i18nimg.ps1')
$tmp = Join-Path $Root 'cache\i18n_imgtest'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $tmp 'images') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $tmp 'out') | Out-Null

$urlA = 'https://example.invalid/ugc/111/AAAABBBBCCCC/'
$urlB = 'https://example.invalid/ugc/222/DDDDEEEEFFFF/'
$nameA = Get-I18nImageCacheBase -Url $urlA
Check 'cache base name strips every non-alphanumeric character' `
    ($nameA -eq 'httpsexampleinvalidugc111AAAABBBBCCCC') ('got ' + $nameA)

$nameB = Get-I18nImageCacheBase -Url $urlB
$srcA = Join-Path $tmp ('images\' + $nameA + '.jpg')
$srcB = Join-Path $tmp ('images\' + $nameB + '.jpg')
foreach ($pair in @(@($srcA, [System.Drawing.Color]::FromArgb(255, 10, 200, 10)), @($srcB, [System.Drawing.Color]::FromArgb(255, 10, 10, 200)))) {
    $bmp = New-Object System.Drawing.Bitmap(200, 80)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear($pair[1])
    $g.Dispose()
    $bmp.Save($pair[0], [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $bmp.Dispose()
}
Check 'fixture images written' ((Test-Path $srcA) -and (Test-Path $srcB))

$found = Find-I18nCachedImage -Dir (Join-Path $tmp 'images') -Url $urlA
Check 'a cache file is found by url' (($null -ne $found) -and ($found.Name -eq ($nameA + '.jpg')))

$saveText = '{"ObjectStates":[{"FaceURL":"' + $urlA + '"},{"FaceURL":"' + $urlB + '"},{"FaceURL":"https://example.invalid/ugc/333/ZZZZ/"}]}'
$map = Get-I18nImageUrls -Raw $saveText
Check 'the url scan finds every distinct image url' ($map.Count -eq 3) ('got ' + $map.Count)
Check 'the url scan ignores empty urls' (-not $map.ContainsKey(''))

$blocks = @(@{ x = 0; y = 0; w = 120; h = 40; fill = '#000000'; alpha = 255; lines = @(
    @{ text = 'TEXT TEST'; x = 4; y = 4; font = 'Microsoft YaHei'; size = 14; bold = $true; color = '#FFFFFF' } ) })
$outA = Join-Path $tmp ('out\' + $nameA + '.jpg')
New-I18nPatchedImage -SourcePath $srcA -OutPath $outA -Blocks $blocks
Check 'patched image written' (Test-Path $outA)
$o = [System.Drawing.Image]::FromFile($outA)
$s = [System.Drawing.Image]::FromFile($srcA)
Check 'pixel size is preserved exactly (a size change itself breaks rendering)' `
    (($o.Width -eq $s.Width) -and ($o.Height -eq $s.Height))
$o.Dispose()
$s.Dispose()
$pb = New-Object System.Drawing.Bitmap($outA)
$covered = $pb.GetPixel(5, 5)
$untouched = $pb.GetPixel(190, 70)
$pb.Dispose()
Check 'the block really covered the corner' ($covered.R -lt 60 -and $covered.G -lt 60 -and $covered.B -lt 60) ('pixel ' + $covered.ToString())
Check 'the rest of the image is untouched' ($untouched.G -gt 120) ('pixel ' + $untouched.ToString())

$ruleJson = Join-Path $tmp 'rules.json'
[System.IO.File]::WriteAllText($ruleJson, '{"blocks":[{"match":"AAAABBBBCCCC","x":0,"y":0,"w":10,"h":10,"lines":[]}]}', (New-Object System.Text.UTF8Encoding($false)))
$rules = Get-I18nImageRule -RulePath $ruleJson
$hit = @($rules) | Where-Object { $urlA -like ('*' + $_.match + '*') } | Select-Object -First 1
$miss = @($rules) | Where-Object { $urlB -like ('*' + $_.match + '*') } | Select-Object -First 1
Check 'a rule matches its own url and not another' (($null -ne $hit) -and ($null -eq $miss))

# ---- 7. text-band detection (no OCR engine involved - see the function header for why) ----
$bandImg = Join-Path $tmp 'band.png'
$bmp = New-Object System.Drawing.Bitmap(300, 150)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$font = New-Object System.Drawing.Font('Microsoft YaHei', 18, [System.Drawing.FontStyle]::Bold)
$g.DrawString('TEXT BAND TEST 12345', $font, [System.Drawing.Brushes]::Black, 12, 40)
$g.Dispose()
$font.Dispose()
$bmp.Save($bandImg, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$bands = Get-I18nTextBands -Path $bandImg -WorkWidth 300
Check 'text band detection finds at least one band' (@($bands).Count -ge 1) ('got ' + @($bands).Count)
$hitBand = @($bands) | Where-Object { $_.y0 -le 52 -and $_.y1 -ge 52 } | Select-Object -First 1
Check 'a band covers the drawn text (y around 40-64)' ($null -ne $hitBand) `
    ((@($bands) | ForEach-Object { 'y' + $_.y0 + '-' + $_.y1 }) -join ' ')
$lowBand = @($bands) | Where-Object { $_.y0 -gt 90 } | Select-Object -First 1
Check 'the empty lower half produces no band' ($null -eq $lowBand)
$prev = Join-Path $tmp 'band_preview.png'
Export-I18nBandPreview -Path $bandImg -OutPath $prev -Bands $bands -PreviewWidth 300
Check 'band preview written' (Test-Path $prev)

# ---- 8. the dictionary translator: longest match first, empty in means empty out ----
# NOTE the parentheses around every concatenation below. WITHOUT them this array came out with SEVEN
# elements instead of three ("Draw two cards.", a bare tab, "TRANSLATED-EXACT", ...) and the dictionary
# file written from it was half a term per line - the translator then found nothing and eight assertions
# failed. The mechanism was right; the fixture was wrong. Caught 2026-10-13.
$dictPath = Join-Path $tmp 'terms.tsv'
[System.IO.File]::WriteAllLines($dictPath, @(
        '# test dictionary',
        ('Draw two cards.' + "`t" + 'TRANSLATED-EXACT'),
        ('Draw' + "`t" + 'TRANSLATED-WORD'),
        ('Discard' + "`t" + 'TRANSLATED-DISCARD')
    ), (New-Object System.Text.UTF8Encoding($false)))
$terms = Read-I18nDictionary -Path $dictPath
Check 'dictionary reader skips comments and sorts longest source first' `
    ((@($terms).Count -eq 3) -and ($terms[0].src -eq 'Draw two cards.')) `
    ((@($terms) | ForEach-Object { $_.src }) -join ' | ')
$tsvLines = @(
    ('id' + "`t" + 'field' + "`t" + 'source' + "`t" + 'target'),
    ('1' + "`t" + 'Nickname' + "`t" + 'Draw two cards.' + "`t"),
    ('2' + "`t" + 'Description' + "`t" + 'Draw a card.' + "`t"),
    ('3' + "`t" + 'GMNotes' + "`t" + 'Unknown prose here.' + "`t"),
    ('4' + "`t" + 'Nickname' + "`t" + '' + "`t")
)
$r4 = Convert-I18nTsvWithDict -Lines $tsvLines -Terms $terms
Check 'dictionary translator counts only translatable rows' ($r4.total -eq 3) ('total ' + $r4.total)
Check 'an exact match wins over the shorter term inside it' ($r4.exact -eq 1) ('exact ' + $r4.exact)
# DEFAULT IS EXACT-ONLY, corrected 2026-10-13 by measuring the output: substituting terms inside a
# sentence gave "洗牌 the 牌库 and 抽一张牌" and the engine pass then skips the row (target no longer
# empty), so a half-translated sentence could never be fixed. A whole sentence belongs to the engine.
Check 'by default, a term inside a sentence is NOT substituted' `
    (($r4.inside -eq 0) -and ($r4.missed -eq 2)) ('inside ' + $r4.inside + ' missed ' + $r4.missed)
$r5 = Convert-I18nTsvWithDict -Lines $tsvLines -Terms $terms -AllowInside
Check 'with -AllowInside the term inside a sentence is substituted again' ($r5.inside -eq 1) ('inside ' + $r5.inside)
Check 'rows with no matching term are left untouched' ($r4.missed -eq 2) ('missed ' + $r4.missed)
Check 'the exact row carries its translation' (@($r4.text)[1] -like '*TRANSLATED-EXACT') (@($r4.text)[1])
Check 'an untouched row keeps an empty target (empty = keep original)' `
    (((@($r4.text)[3] -split "`t")[3] -eq '')) (@($r4.text)[3])
Check 'an empty source stays empty and is not counted as translatable' `
    ((((@($r4.text)[4] -split "`t")[3] -eq '') -and ($r4.total -eq 3)))
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($failed -gt 0) { Write-Host ("$failed i18n case(s) failed"); exit 1 }
Write-Host 'all i18n cases passed'
exit 0
