# jsontext.ps1 - convert between a JSON string literal's body and the text a human sees.
#
# WHY THIS EXISTS AT ALL (and why the two obvious shortcuts are both wrong):
#   * (ConvertFrom|ConvertTo)-Json cannot be used: a bare field value is not a JSON document, and the
#     save file itself is far too big for ConvertFrom-Json (it blows up - that is why every reader in
#     this repo uses JavaScriptSerializer with MaxJsonLength raised).
#   * Regex.Unescape is .NET escaping, not JSON escaping: it does not know \/ , and it treats \uXXXX
#     under .NET rules. Close enough is not good enough here: i18n_apply.ps1 compares an escaped
#     string it just produced against bytes that came out of a real save file.
#   * So: only the escapes JSON actually defines are handled; anything unrecognised is passed through
#     unchanged (a save written by another serialiser must not be mangled by our reader).
#
# ASCII only on purpose: no CJK in this file means no BOM to lose.
#
#   . (Join-Path $Root 'tts\lib\jsontext.ps1')
#   ConvertTo-JsonStringBody   'he said "hi"'      -> he said \"hi\"
#   ConvertFrom-JsonStringBody 'he said \"hi\"'    -> he said "hi"

function ConvertTo-JsonStringBody {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        switch ($ch) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`b" { [void]$sb.Append('\b') }
            "`f" { [void]$sb.Append('\f') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ([int]$ch -lt 0x20) { [void]$sb.Append('\u{0:x4}' -f [int]$ch) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    return $sb.ToString()
}

function ConvertFrom-JsonStringBody {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $ch = $Text[$i]
        if ($ch -ne '\' -or $i -eq $n - 1) { [void]$sb.Append($ch); $i++; continue }
        $esc = $Text[$i + 1]
        switch ($esc) {
            '"' { [void]$sb.Append('"'); $i += 2 }
            '\' { [void]$sb.Append('\'); $i += 2 }
            '/' { [void]$sb.Append('/'); $i += 2 }
            'b' { [void]$sb.Append("`b"); $i += 2 }
            'f' { [void]$sb.Append("`f"); $i += 2 }
            'n' { [void]$sb.Append("`n"); $i += 2 }
            'r' { [void]$sb.Append("`r"); $i += 2 }
            't' { [void]$sb.Append("`t"); $i += 2 }
            'u' {
                if ($i + 5 -lt $n) {
                    $hex = $Text.Substring($i + 2, 4)
                    $code = 0
                    if ([int]::TryParse($hex, [System.Globalization.NumberStyles]::HexNumber,
                            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$code)) {
                        [void]$sb.Append([char]$code)
                        $i += 6
                    } else {
                        # Not a valid \uXXXX: hand the backslash through untouched rather than guess.
                        [void]$sb.Append($ch); $i++
                    }
                } else {
                    [void]$sb.Append($ch); $i++
                }
            }
            default {
                # Unrecognised escape: keep both characters, change nothing.
                [void]$sb.Append($ch); [void]$sb.Append($esc); $i += 2
            }
        }
    }
    return $sb.ToString()
}
