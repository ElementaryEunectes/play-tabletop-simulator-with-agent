# grab_window.ps1 - capture a window's pixels to a PNG, trying several strategies.
#
# Why this exists: screen-control tools (MAA and friends) get screen control from the OS,
# not from the game. On Windows that means one of:
#   GDI / ScreenDC      - copy the screen rectangle (fails when occluded)
#   PrintWindow         - ask the window to render itself (works while occluded IF the app
#                         honours WM_PRINT; Unity usually does NOT)
#   DXGI DesktopDup/WGC - the modern GPU-level route (needs WinRT, not in PS 5.1)
# This script tries PrintWindow (with PW_RENDERFULLCONTENT) and falls back to BitBlt from
# the screen DC, then reports WHICH ONE produced non-black output so the result is evidence
# rather than a guess.
#
# ASCII only. USAGE: grab_window.ps1 [-Handle <hwnd>] [-TitleMatch 'Tabletop Simulator']
# NOTE: param() must stay the FIRST statement in this file; the config dot-source comes after.
param(
    [string]$TitleMatch = 'Tabletop Simulator',
    [string]$OutDir = '',
    [int]$MinNonBlackPct = 2,
    [long]$Handle = 0
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($OutDir -eq '') { $OutDir = $DshShots }

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Drawing;

public class WinCap {
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr dst, int dx, int dy, int w, int h, IntPtr src, int sx, int sy, int rop);
    [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetWindowDC_Desktop(IntPtr h);

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public const uint PW_RENDERFULLCONTENT = 0x00000002;
    public const int SRCCOPY = 0x00CC0020;

    public static IntPtr Find(string needle) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(512);
            GetWindowTextW(h, sb, 512);
            string t = sb.ToString();
            if (t.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    // Returns [width, height, nonBlackPercent, methodUsed]
    public static object[] Grab(IntPtr hwnd, string outPng) {
        RECT wr, cr;
        GetWindowRect(hwnd, out wr);
        GetClientRect(hwnd, out cr);
        int w = wr.Right - wr.Left;
        int h = wr.Bottom - wr.Top;
        if (w <= 0 || h <= 0) return new object[] { 0, 0, 0.0, "empty-rect" };

        string method = "PrintWindow";
        Bitmap bmp = new Bitmap(w, h);
        using (Graphics g = Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            bool ok = PrintWindow(hwnd, hdc, PW_RENDERFULLCONTENT);
            g.ReleaseHdc(hdc);
            if (!ok) method = "PrintWindow-failed";
        }
        double pct = NonBlack(bmp);
        if (pct < 2.0) {
            // fall back: blit the screen rectangle the window occupies
            method = "ScreenBitBlt";
            using (Graphics g = Graphics.FromImage(bmp)) {
                IntPtr dst = g.GetHdc();
                IntPtr src = GetWindowDC(IntPtr.Zero);
                BitBlt(dst, 0, 0, w, h, src, wr.Left, wr.Top, SRCCOPY);
                ReleaseDC(IntPtr.Zero, src);
                g.ReleaseHdc(dst);
            }
            pct = NonBlack(bmp);
        }
        bmp.Save(outPng, System.Drawing.Imaging.ImageFormat.Png);
        bmp.Dispose();
        return new object[] { w, h, pct, method };
    }

    static double NonBlack(Bitmap b) {
        int step = 8;                 // sample every 8th pixel in both axes
        long total = 0, lit = 0;
        for (int y = 0; y < b.Height; y += step) {
            for (int x = 0; x < b.Width; x += step) {
                Color c = b.GetPixel(x, y);
                total++;
                if (c.R > 12 || c.G > 12 || c.B > 12) lit++;
            }
        }
        return total == 0 ? 0.0 : (100.0 * lit / total);
    }
}
"@ -ReferencedAssemblies System.Drawing

if ($Handle -ne 0) { $hwnd = [IntPtr]$Handle } else { $hwnd = [WinCap]::Find($TitleMatch) }
if ($hwnd -eq [IntPtr]::Zero) { Write-Host "no visible window matching '$TitleMatch'"; exit 2 }
Write-Host ("found window handle: " + $hwnd)

$fg = [WinCap]::GetForegroundWindow()
Write-Host ("foreground handle  : " + $fg + "   target is foreground: " + ($fg -eq $hwnd))

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$png = Join-Path $OutDir ("win_" + $stamp + ".png")
$r = [WinCap]::Grab($hwnd, $png)
Write-Host ("size               : " + $r[0] + " x " + $r[1])
Write-Host ("non-black          : " + [math]::Round([double]$r[2], 1) + " %")
Write-Host ("method             : " + $r[3])
Write-Host ("png                : " + $png)
if (Test-Path $png) { Write-Host ("png bytes          : " + (Get-Item $png).Length) }
exit 0
