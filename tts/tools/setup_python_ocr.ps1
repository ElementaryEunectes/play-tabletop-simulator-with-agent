# setup_python_ocr.ps1 - one-shot, idempotent setup of the OPTIONAL OCR stack, entirely inside local\.
#
# WHY THIS EXISTS: the OCR route was proven on 2026-10-14, but its steps lived in throwaway scripts under
# cache\ (which gets wiped). This is that recipe as a tool, so the next machine - or the next clone - can
# reproduce it. Everything lands in local\scratch\, which is gitignored; none of it ships.
#
# WHY THESE PARTICULAR ROUTES (all measured, see tts\docs\I18N.md 2d):
#   * the official Python installer exits 0x80070005 (access denied) even with the sandbox widened;
#   * winget is unusable here (App Execution Alias: no output, exit -1978335231 / 0x8A150001);
#   * get-pip.py unpacks into a temp dir and gets PermissionError - so pip comes as a WHEEL, unzipped;
#   * downloads go through node, because PowerShell's own HTTP stack is blocked here, and long single-shot
#     downloads get reset (the .mjs helpers resume with Range requests);
#   * the OCR package is rapidocr-onnxruntime, not PaddleOCR: its models are INSIDE the package, so
#     there is no second download to survive.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\setup_python_ocr.ps1
#   ... -Force        (redo the steps that look already done)
#
# ASCII only on purpose: no CJK here means no BOM to lose.
param(
    [string]$Root = '',
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')

$pyDir = Join-Path $Root 'local\scratch\python'
$py = Join-Path $pyDir 'python.exe'
$sp = Join-Path $pyDir 'Lib\site-packages'
$tmp = Join-Path $DshCache 'pytmp'
New-Item -ItemType Directory -Force $tmp | Out-Null
$env:TMP = $tmp
$env:TEMP = $tmp
$env:PYTHONIOENCODING = 'utf-8'

function Step([string]$t) { Write-Host ''; Write-Host ('== ' + $t) }

Push-Location $Root
try {
    # ---- 1. embeddable Python (no installer, no registry, no admin) ----
    Step 'embeddable Python 3.12'
    if ((Test-Path $py) -and -not $Force) {
        Write-Host ('   already installed: ' + (& $py --version 2>&1))
    } else {
        & node (Join-Path $Root 'tts\tools\get_python_embed.mjs')
        if ($LASTEXITCODE -ne 0) { throw 'download of the embeddable zip failed' }
        if (Test-Path $pyDir) { Remove-Item $pyDir -Recurse -Force }
        New-Item -ItemType Directory -Force $pyDir | Out-Null
        Expand-Archive -Path (Join-Path $DshCache 'python-embed.zip') -DestinationPath $pyDir -Force
        Write-Host ('   ' + (& $py --version 2>&1) + '  -> ' + $pyDir)
    }

    # ---- 2. ._pth WITHOUT which pip cannot work (a site is never imported) ----
    Step 'python312._pth'
    $pth = Join-Path $pyDir 'python312._pth'
    [System.IO.File]::WriteAllLines($pth, @('python312.zip', '.', 'Lib\site-packages', 'import site'),
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Host '   wrote the _pth with `import site` (without it, installed packages are invisible)'

    # ---- 3. pip, as a wheel ----
    Step 'pip'
    $pipOk = $false
    try { & $py -m pip --version *> $null; $pipOk = ($LASTEXITCODE -eq 0) } catch { $pipOk = $false }
    if ($pipOk -and -not $Force) {
        Write-Host ('   already installed: ' + (& $py -m pip --version 2>&1))
    } else {
        & node (Join-Path $Root 'tts\tools\get_pip_wheel.mjs')
        if ($LASTEXITCODE -ne 0) { throw 'download of the pip wheel failed' }
        New-Item -ItemType Directory -Force $sp | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $DshCache 'pip.whl'))
        try {
            foreach ($e in $zip.Entries) {
                $target = Join-Path $sp $e.FullName
                $dir = Split-Path $target -Parent
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
                if ($e.Name -ne '') { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true) }
            }
        } finally { $zip.Dispose() }
        Write-Host ('   ' + (& $py -m pip --version 2>&1))
    }

    # ---- 4. the OCR package (models are inside it) ----
    Step 'rapidocr-onnxruntime'
    $have = $false
    try { & $py -c "import rapidocr_onnxruntime" *> $null; $have = ($LASTEXITCODE -eq 0) } catch { $have = $false }
    if ($have -and -not $Force) {
        Write-Host '   already installed'
    } else {
        Write-Host '   NOTE: this step may need one escalation (pip writes temp files and spawns helpers)'
        & $py -m pip install --no-warn-script-location --disable-pip-version-check rapidocr-onnxruntime
        if ($LASTEXITCODE -ne 0) { throw 'pip install failed - see the note about escalation above' }
    }

    # ---- 5. prove it ----
    Step 'verify'
    & $py -c "import rapidocr_onnxruntime, onnxruntime; print('rapidocr OK, onnxruntime', onnxruntime.__version__)"
    if ($LASTEXITCODE -ne 0) { throw 'import check failed' }
    Write-Host ''
    Write-Host 'next: powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\ocr_boxes.ps1 -Image <card image>'
} finally {
    Pop-Location
}
