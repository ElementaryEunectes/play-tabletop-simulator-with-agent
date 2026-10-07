# test_param_backfill.ps1 - every param() default of '' must be resolved or tested somewhere
# in the same file.
#
# Why: a whole class of bug in this repo (5 scripts at once) was "the param default '' is never
# backfilled after the config dot-source" -- the script parses, starts, then writes to an empty
# path (Test-Path '', Export-Csv '', ReadAllText ''). A syntax check cannot see it; this can.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1
#   exit 0 = every default is resolved or tested, exit 1 = offenders listed
#
# A default counts as resolved if the file, anywhere, backfills it ("$X = ...") or tests it in
# one of the usual ways (-eq '', -ne '', if ($X), if (-not $X), IsNullOrWhiteSpace($X), ...).
param([string]$Dir = '')

$ErrorActionPreference = 'Stop'
if ($Dir -eq '') { $Dir = Split-Path -Parent $PSScriptRoot }        # tts\

# Parameters that are legitimately allowed to stay empty. Each is guarded further down through
# another variable, so the patterns below cannot see it. Keep this list SHORT and commented.
$Allow = @{
    'say.ps1' = @('Message')    # $text = $Message, then "if ($text.Trim() -eq '') { throw }"
}

$q2       = ([string][char]39) + ([string][char]39)
# NOTE: deliberately NOT anchored to the start of a line. An earlier version was, and it
# silently matched nothing in a script that writes param([string]$X = '') on one line -- the
# positive control (a deliberately broken probe script) then exited 0 and proved the test was
# blind. Over-matching is the safe direction here: an extra hit is visible, a miss is not.
$patParam = '\[(?:string|int|double|bool)\]\s*\$(\w+)\s*=\s*' + $q2
$bad      = 0

foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter *.ps1 -Recurse -File) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    foreach ($n in @([regex]::Matches($text, $patParam) | ForEach-Object { $_.Groups[1].Value })) {
        if ($Allow.ContainsKey($f.Name) -and $Allow[$f.Name] -contains $n) { continue }
        $guards = @(
            ('(?m)^\s*\$' + $n + '\s*='),                    # backfilled after the dot-source
            ('\$' + $n + '\s*-(?:eq|ne)\s*' + $q2),          # compared against ''
            ('if\s*\(\s*-not\s+\$' + $n + '\s*\)'),          # if (-not $X)
            ('if\s*\(\s*\$' + $n + '\s*\)'),                 # if ($X)
            ('IsNullOrWhiteSpace\(\s*\$' + $n + '\s*\)'),
            ('\$null\s*-ne\s*\$' + $n)
        )
        $ok = $false
        foreach ($g in $guards) { if ([regex]::IsMatch($text, $g)) { $ok = $true; break } }
        if (-not $ok) {
            $bad++
            $rel = $f.FullName.Substring($Dir.Length).TrimStart('\')
            Write-Host ("UNRESOLVED  {0}  `${1}" -f $rel, $n)
        }
    }
}
if ($bad -gt 0) {
    Write-Host ("`n{0} param default(s) are never resolved or tested" -f $bad)
    exit 1
}
Write-Host "all param defaults of '' are resolved or tested"
