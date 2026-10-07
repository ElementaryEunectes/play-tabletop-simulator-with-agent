# check_ps1.ps1 - make every .ps1 here (and below) BOM-safe, then syntax-check it with the
# real parser.
#
# WHY THIS EXISTS (a real incident)
#   Editing a .ps1 with a tool that REWRITES the file drops the UTF-8 BOM. PowerShell 5.1
#   then reads the file as ANSI, the Chinese comments become mojibake, and the parser dies
#   with a MISLEADING error ("Missing closing ')' in expression"). The script still "runs"
#   instantly -- it just fails at parse time, which looks like a suspiciously fast success.
#   Rule: after ANY edit to a .ps1 in this folder, run this script.
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1 -Dir C:\other
# NOTE: param() must stay the FIRST statement in the file -- nothing may precede it
#       (a dot-source before param() silently kills every parameter; cost me once).
param(
    [string]$Dir = '',
    [switch]$Quiet
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ([string]::IsNullOrWhiteSpace($Dir)) { $Dir = $DshTts }

$enc  = New-Object System.Text.UTF8Encoding($true)
$utf8 = [System.Text.Encoding]::UTF8
$bad  = @()
$all  = Get-ChildItem -LiteralPath $Dir -Filter *.ps1 -Recurse -File
foreach ($f in $all) {
    $bytes  = [System.IO.File]::ReadAllBytes($f.FullName)
    $hadBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
    # IMPORTANT: Encoding.UTF8.GetString keeps a leading BOM as a U+FEFF CHARACTER, and
    # WriteAllText(..., UTF8Encoding(true)) then writes ANOTHER one -> the BOM multiplies
    # on every run and PowerShell finally refuses to parse `param(`. Strip it first.
    $text = $utf8.GetString($bytes).TrimStart([char]0xFEFF)
    # Write back ONLY when the BOM is missing. (This condition used to read `if ($hadBom)`,
    # i.e. it rewrote exactly the files that were already fine and never fixed the broken
    # ones -- which is why three Chinese .ps1 kept failing to parse while this script kept
    # reporting "BOM-FIXED". Caught 2026-10-08.)
    if (-not $hadBom) { [System.IO.File]::WriteAllText($f.FullName, $text, $enc) }
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    $n = @($errs).Count
    if ($n -gt 0) { $bad += $f.Name }
    $flag = 'ok'
    if (-not $hadBom) { $flag = 'BOM-FIXED' }
    if ($n -gt 0)     { $flag = 'PARSE-ERROR' }
    if (-not $Quiet -or $n -gt 0 -or -not $hadBom) {
        Write-Host ("{0,-26} {1,-12} errors={2}" -f $f.Name, $flag, $n)
    }
}
if ($bad.Count -gt 0) {
    Write-Host ("`nPARSE ERRORS in: " + ($bad -join ', '))
    exit 1
}
Write-Host ("`nall .ps1 ({0} files): BOM ok, 0 parse errors" -f $all.Count)
