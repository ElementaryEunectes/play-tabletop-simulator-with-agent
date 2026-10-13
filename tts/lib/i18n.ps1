# i18n.ps1 - the localisation mechanism as functions. tts\tools\i18n_export.ps1 and i18n_apply.ps1 are
# thin CLI wrappers around these; tts\tests\test_i18n.ps1 calls them DIRECTLY.
#
# WHY THE MECHANISM LIVES IN lib\ AND NOT IN THE TOOLS: the offline gates must not spawn a PowerShell
# child (this sandbox blocks powershell.exe and its descendants), and a tool script that ends in `exit`
# would take the test process down with it if it were dot-sourced. So: mechanism here (no exit, no I/O),
# file handling and exit codes in the tools, assertions in the test. Same split as lib\bridge.ps1.
#
# See tts\docs\I18N.md for the contract. The short version:
#   * one regex finds every translatable VALUE; its position in the file is the row `id`
#   * both halves use that same regex, so `id` is stable as long as the save itself has not changed
#   * nothing is ever parsed-and-reserialised (JavaScriptSerializer drops/reorders fields on the way out)
#
# ASCII only on purpose: no CJK here means no BOM to lose.
. (Join-Path $PSScriptRoot 'jsontext.ps1')

function Get-I18nPattern {
    param([string[]]$Fields = @('Nickname', 'Description', 'GMNotes'))
    return '"(' + (($Fields | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')"\s*:\s*"((?:[^"\\]|\\.)*)"'
}

function Get-I18nMatch {
    param([string]$Raw, [string[]]$Fields = @('Nickname', 'Description', 'GMNotes'))
    return [regex]::Matches($Raw, (Get-I18nPattern -Fields $Fields))
}

function ConvertTo-I18nFlat {
    # A tab or newline inside a value would break the TSV: escape them (and the backslash itself, or the
    # escaping would not be reversible). Display-layer only - both halves apply it, so it cancels out.
    param([string]$Text)
    return $Text.Replace('\', '\\').Replace("`t", '\t').Replace("`r", '\r').Replace("`n", '\n')
}

function ConvertFrom-I18nFlat {
    # NO switch HERE ON PURPOSE: inside a PowerShell switch, `continue` moves to the next switch item and
    # then FALLS THROUGH to the code after the switch - so the escaped character was appended a second
    # time and the index advanced twice. Caught by test_i18n.ps1 on the first run. Plain ifs, and
    # `continue` then means the enclosing while.
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        if ($ch -eq '\' -and $i -lt $Text.Length - 1) {
            $nx = $Text[$i + 1]
            if ($nx -eq '\') { [void]$sb.Append('\'); $i += 2; continue }
            if ($nx -eq 't') { [void]$sb.Append("`t"); $i += 2; continue }
            if ($nx -eq 'r') { [void]$sb.Append("`r"); $i += 2; continue }
            if ($nx -eq 'n') { [void]$sb.Append("`n"); $i += 2; continue }
        }
        [void]$sb.Append($ch)
        $i++
    }
    return $sb.ToString()
}

function Get-I18nTsvLines {
    # The exporter's whole output, as lines. Rows are one-to-one with the matches, EMPTY VALUES INCLUDED:
    # skipping them would shift every later id and pair translations with the wrong card.
    param([string]$SaveName, $Matches)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# i18n_export - translate column 4, keep columns 1-3 exactly as they are')
    $lines.Add('# save: ' + $SaveName)
    $lines.Add('# rows: ' + $Matches.Count + '  (empty source = leave empty)')
    $lines.Add('id' + "`t" + 'field' + "`t" + 'source')
    for ($i = 0; $i -lt $Matches.Count; $i++) {
        $field = $Matches[$i].Groups[1].Value
        $text = ConvertFrom-JsonStringBody $Matches[$i].Groups[2].Value
        $lines.Add(([string]($i + 1)) + "`t" + $field + "`t" + (ConvertTo-I18nFlat $text))
    }
    return $lines
}

function Read-I18nTsv {
    param([string[]]$Lines)
    $rows = @{}
    foreach ($line in $Lines) {
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $cols = $line -split "`t"
        if ($cols.Count -lt 3) { continue }
        if ($cols[0] -eq 'id') { continue }
        $id = 0
        if (-not [int]::TryParse($cols[0], [ref]$id)) { continue }
        $target = ''
        if ($cols.Count -ge 4) { $target = $cols[3] }
        $rows[$id] = @{ field = $cols[1]; source = $cols[2]; target = $target }
    }
    return $rows
}

function Merge-I18nText {
    # Pair by id (not by line order - a translator may reorder, and positional pairing would then swap
    # two cards' text in silence), verify every row against a fresh scan, then replace the VALUE bytes
    # from the end of the file backwards so earlier offsets stay valid.
    # Returns a hashtable: text / replaced / unchanged / emptyTarget / mismatches / log. Never writes.
    param([string]$Raw, [string[]]$Fields, $Rows, [switch]$Force)
    $matches = Get-I18nMatch -Raw $Raw -Fields $Fields
    $log = New-Object System.Collections.Generic.List[string]
    $plan = New-Object System.Collections.Generic.List[object]
    $mismatch = 0
    $unchanged = 0
    $emptyTarget = 0
    for ($i = 0; $i -lt $matches.Count; $i++) {
        $id = $i + 1
        if (-not $Rows.ContainsKey($id)) {
            $mismatch++
            if ($log.Count -lt 4) { $log.Add('id ' + $id + ' missing from the tsv - re-export') }
            continue
        }
        $field = $matches[$i].Groups[1].Value
        $source = ConvertTo-I18nFlat (ConvertFrom-JsonStringBody $matches[$i].Groups[2].Value)
        $row = $Rows[$id]
        if ($row.field -ne $field -or $row.source -ne $source) {
            $mismatch++
            if ($log.Count -lt 4) {
                $a = [Math]::Min(40, $row.source.Length)
                $b = [Math]::Min(40, $source.Length)
                $log.Add('id ' + $id + ' differs: tsv [' + $row.field + '] "' + $row.source.Substring(0, $a) +
                         '" vs save [' + $field + '] "' + $source.Substring(0, $b) + '"')
            }
            continue
        }
        if ($row.target -eq '') { $emptyTarget++; $unchanged++; continue }
        if ($row.target -eq $row.source) { $unchanged++; continue }
        # The target column carries the same TSV escaping as the source column (a tab written as \t, and
        # so on), so it has to be un-flattened BEFORE it becomes JSON. Forgetting this shipped "Z2-NIE\tX"
        # literally into the save instead of a tab - also caught by test_i18n.ps1.
        $plan.Add([pscustomobject]@{
            index  = $matches[$i].Groups[2].Index
            length = $matches[$i].Groups[2].Length
            text   = (ConvertTo-JsonStringBody (ConvertFrom-I18nFlat $row.target))
        })
    }
    $out = $Raw
    if ($mismatch -eq 0 -or $Force) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append($Raw)
        foreach ($r in @($plan | Sort-Object -Property index -Descending)) {
            [void]$sb.Remove($r.index, $r.length)
            [void]$sb.Insert($r.index, $r.text)
        }
        $out = $sb.ToString()
    }
    return @{
        text        = $out
        replaced    = $plan.Count
        unchanged   = $unchanged
        emptyTarget = $emptyTarget
        mismatches  = $mismatch
        scanned     = $matches.Count
        log         = $log
    }
}

function Read-I18nDictionary {
    # TSV: `source<TAB>target`, `#` comments. Returned longest-source-first so that a specific phrase is
    # tried before the general words it contains ("Draw two cards." before "Draw").
    #
    # SEVERAL FILES, MERGED, FIRST WINS: this is what makes a layered table possible - the shared card
    # terms live in the repository (tts\i18n\terms_card.tsv), while one game's own names live in
    # local\games\<game>\ (per the charter: game-specific content does not ship). Pass the specific table
    # FIRST and it overrides the general one for the same source string.
    param([string[]]$Path)
    $terms = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($p in $Path) {
        if (-not (Test-Path -LiteralPath $p)) { throw ('no such dictionary: ' + $p) }
        foreach ($line in [System.IO.File]::ReadAllLines($p, [System.Text.Encoding]::UTF8)) {
            if ($line -eq '' -or $line.StartsWith('#')) { continue }
            $c = $line -split "`t"
            if ($c.Count -lt 2 -or $c[0] -eq '') { continue }
            if ($seen.ContainsKey($c[0])) { continue }
            $seen[$c[0]] = $true
            $terms.Add([pscustomobject]@{ src = $c[0]; dst = $c[1] })
        }
    }
    return @($terms | Sort-Object -Property @{ Expression = { $_.src.Length }; Descending = $true })
}

function Convert-I18nTsvWithDict {
    # The dictionary "translator": fills column 4 for any row it has a term for, leaves the rest empty
    # (empty target = keep the original text - that is the contract, see tts\docs\I18N.md section 0).
    #
    # EXACT MATCH ONLY BY DEFAULT, and that default was corrected by measurement (2026-10-13): substituting
    # terms inside a sentence produced "洗牌 the 牌库 and 抽一张牌" - half translated, and the model pass
    # then skips the row precisely because the target is no longer empty. A whole sentence belongs to the
    # engine; a dictionary is for terms. -AllowInside re-enables the old behaviour if someone wants it.
    param([string[]]$Lines, $Terms, [switch]$CaseSensitive, [switch]$AllowInside)
    $cmp = [System.StringComparison]::Ordinal
    if (-not $CaseSensitive) { $cmp = [System.StringComparison]::OrdinalIgnoreCase }
    $out = New-Object System.Collections.Generic.List[string]
    $total = 0
    $exact = 0
    $inside = 0
    $missed = 0
    foreach ($line in $Lines) {
        if ($line -eq '' -or $line.StartsWith('#')) { $out.Add($line); continue }
        $c = $line -split "`t"
        if ($c.Count -lt 3 -or $c[0] -eq 'id') { $out.Add($line); continue }
        $src = $c[2]
        if ($src -eq '') { $out.Add($c[0] + "`t" + $c[1] + "`t" + $src + "`t"); continue }
        $total++
        $dst = ''
        foreach ($t in $Terms) {
            if ($src.Equals($t.src, $cmp)) { $dst = $t.dst; $exact++; break }
        }
        if ($dst -eq '' -and $AllowInside) {
            $work = $src
            $changed = $false
            foreach ($t in $Terms) {
                if ($work.IndexOf($t.src, $cmp) -ge 0) {
                    $work = [regex]::Replace($work, [regex]::Escape($t.src), $t.dst.Replace('$', '$$'), 'IgnoreCase')
                    $changed = $true
                }
            }
            if ($changed) { $dst = $work; $inside++ }
        }
        if ($dst -eq '') { $missed++ }
        $out.Add($c[0] + "`t" + $c[1] + "`t" + $src + "`t" + $dst)
    }
    return @{ text = $out; total = $total; exact = $exact; inside = $inside; missed = $missed }
}
