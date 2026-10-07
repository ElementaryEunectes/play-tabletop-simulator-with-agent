# tts_click.ps1 - guarded mouse control for Tabletop Simulator.
#
# WHY THE GUARD EXISTS
#   Injected SendInput events go to the FOREGROUND window. This process cannot
#   raise a window itself: SetForegroundWindow returns False even under
#   danger-full-access, because that is a Windows foreground-lock rule, not a
#   sandbox rule. Measured on this machine, Edge and TTS occupy the exact same
#   maximised rectangle (-7,-7)-(1714,1026), so a stray click lands silently in
#   the wrong app. Therefore EVERY action verifies the foreground window title
#   first and refuses to click when TTS is not in front. Fullscreen does not
#   help: focus can move without any window becoming visible.
#
# ACTIONS
#   -Action probe    report foreground + TTS geometry, move nothing
#   -Action click    -X -Y  guarded left click at absolute screen coords
#   -Action rclick   guarded right click
#   -Action drag     -X -Y -X2 -Y2  guarded drag (for moving cards)
#   -Action key      -Vk <code>  guarded single key press
#
# ASCII only.
param(
    [ValidateSet('probe', 'click', 'rclick', 'drag', 'key')]
    [string]$Action = 'probe',
    [int]$X = 0, [int]$Y = 0,
    [int]$X2 = 0, [int]$Y2 = 0,
    [int]$Vk = 0,
    [string]$WindowTitle = 'Tabletop Simulator',
    [switch]$Force,
    # Emit position and button inside ONE absolute event. Try this when plain
    # SetCursorPos + button events move the pointer but never register a press.
    [switch]$Absolute
)

$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class TtsIn {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extraInfo; }
    [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion u; }

    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);

    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] arr, int size);

    const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
    const uint MOUSEEVENTF_MOVE = 0x0001, MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004;
    const uint MOUSEEVENTF_RIGHTDOWN = 0x0008, MOUSEEVENTF_RIGHTUP = 0x0010, MOUSEEVENTF_ABSOLUTE = 0x8000;
    const uint KEYEVENTF_KEYUP = 0x0002;

    public static IntPtr FindWindow(string needle) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder sb = new StringBuilder(400);
            GetWindowTextW(h, sb, 400);
            if (sb.ToString().IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static string TitleOf(IntPtr h) {
        StringBuilder sb = new StringBuilder(400);
        GetWindowTextW(h, sb, 400);
        return sb.ToString();
    }

    public static string RectOf(IntPtr h) {
        RECT r; GetWindowRect(h, out r);
        return "(" + r.Left + "," + r.Top + ")-(" + r.Right + "," + r.Bottom + ")";
    }

    static uint Mouse(uint flags, int dx, int dy) {
        INPUT[] a = new INPUT[1];
        a[0].type = INPUT_MOUSE;
        a[0].u.mi.dx = dx; a[0].u.mi.dy = dy; a[0].u.mi.dwFlags = flags;
        return SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void MoveTo(int x, int y) { SetCursorPos(x, y); }
    public static uint LeftDown()  { return Mouse(MOUSEEVENTF_LEFTDOWN, 0, 0); }
    public static uint LeftUp()    { return Mouse(MOUSEEVENTF_LEFTUP, 0, 0); }
    public static uint RightDown() { return Mouse(MOUSEEVENTF_RIGHTDOWN, 0, 0); }
    public static uint RightUp()   { return Mouse(MOUSEEVENTF_RIGHTUP, 0, 0); }

    // ABSOLUTE variant: position and button in ONE event, sent with
    // MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE. Some fullscreen games build their
    // pointer state only from the event that carries the position, so a separate
    // SetCursorPos followed by a button event at (0,0) delta can be discarded.
    // Absolute coords must be normalised to 0..65535 across the virtual screen.
    public static uint AbsClick(int x, int y, bool right) {
        int vx = GetSystemMetrics(0), vy = GetSystemMetrics(1);
        int nx = (int)((x * 65535.0) / Math.Max(1, vx - 1));
        int ny = (int)((y * 65535.0) / Math.Max(1, vy - 1));
        INPUT[] a = new INPUT[2];
        a[0].type = INPUT_MOUSE;
        a[0].u.mi.dx = nx; a[0].u.mi.dy = ny;
        a[0].u.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
        a[1].type = INPUT_MOUSE;
        a[1].u.mi.dx = nx; a[1].u.mi.dy = ny;
        a[1].u.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE |
                            (right ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN);
        uint r = SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
        System.Threading.Thread.Sleep(120);
        INPUT[] b = new INPUT[1];
        b[0].type = INPUT_MOUSE;
        b[0].u.mi.dx = nx; b[0].u.mi.dy = ny;
        b[0].u.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE |
                            (right ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_LEFTUP);
        r += SendInput(1, b, Marshal.SizeOf(typeof(INPUT)));
        return r;
    }

    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);

    public static uint KeyPress(ushort vk) {
        INPUT[] a = new INPUT[1];
        a[0].type = INPUT_KEYBOARD;
        a[0].u.ki.wVk = vk; a[0].u.ki.dwFlags = 0;
        uint r = SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
        a[0].u.ki.dwFlags = KEYEVENTF_KEYUP;
        r += SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
        return r;
    }
    public static string Cursor() { POINT p; GetCursorPos(out p); return p.X + "," + p.Y; }
    // What window is actually under a point? The last line of defence against
    // clicking an overlapping app.
    public static string WindowAt(int x, int y) {
        POINT p; p.X = x; p.Y = y;
        IntPtr h = WindowFromPoint(p);
        return TitleOf(h);
    }
}
"@

function Show-State {
    $fg = [TtsIn]::GetForegroundWindow()
    $tts = [TtsIn]::FindWindow($WindowTitle)
    Write-Host ("foreground : hwnd=" + $fg + "  [" + [TtsIn]::TitleOf($fg) + "]")
    Write-Host ("TTS window : hwnd=" + $tts + "  rect=" + $(if ($tts -ne [IntPtr]::Zero) { [TtsIn]::RectOf($tts) } else { 'n/a' }))
    Write-Host ("TTs is foreground : " + ($fg -eq $tts))
    Write-Host ("cursor now : " + [TtsIn]::Cursor())
    return @{ Fg = $fg; Tts = $tts }
}

# The guard: never inject unless TTS owns the foreground.
function Assert-TtsForeground {
    param($State, [switch]$ForceIt)
    if ($ForceIt) { Write-Host "  !! -Force given: guard bypassed"; return }
    if ($State.Fg -ne $State.Tts) {
        Write-Host "REFUSED: TTS is not the foreground window."
        # Write-Host takes -Object as ONE argument, so a bare
        # "text" + [Type]::Call() list is parsed as separate args and printed
        # literally. Wrap the whole concatenation in parentheses.
        Write-Host ("  foreground = [" + [TtsIn]::TitleOf($State.Fg) + "]")
        Write-Host "  Clicking now would send the event to that window instead."
        Write-Host "  Bring Tabletop Simulator to the front, then retry."
        exit 4
    }
}

$st = Show-State

switch ($Action) {
    'probe' { exit 0 }

    'click' {
        Assert-TtsForeground $st -ForceIt:$Force
        $under = [TtsIn]::WindowAt($X, $Y)
        Write-Host ("under (" + $X + "," + $Y + ") : [" + $under + "]")
        if ($under -notlike ('*' + $WindowTitle + '*') -and -not $Force) {
            Write-Host "REFUSED: the window under that point is not TTS."; exit 5
        }
        [TtsIn]::MoveTo($X, $Y); Start-Sleep -Milliseconds 200
        if ($Absolute) {
            $u = [TtsIn]::AbsClick($X, $Y, $false)
            Write-Host ("ABSOLUTE click sent at " + $X + "," + $Y + "  events=" + $u)
        } else {
            $d = [TtsIn]::LeftDown(); Start-Sleep -Milliseconds 150
            $u = [TtsIn]::LeftUp()
            Write-Host ("click sent at " + $X + "," + $Y + "  down=" + $d + " up=" + $u)
        }
    }

    'rclick' {
        Assert-TtsForeground $st -ForceIt:$Force
        [TtsIn]::MoveTo($X, $Y); Start-Sleep -Milliseconds 200
        if ($Absolute) {
            $u = [TtsIn]::AbsClick($X, $Y, $true)
            Write-Host ("ABSOLUTE right-click sent at " + $X + "," + $Y + "  events=" + $u)
        } else {
            $d = [TtsIn]::RightDown(); Start-Sleep -Milliseconds 150
            $u = [TtsIn]::RightUp()
            Write-Host ("right-click sent at " + $X + "," + $Y + "  down=" + $d + " up=" + $u)
        }
    }

    'drag' {
        Assert-TtsForeground $st -ForceIt:$Force
        Write-Host ("drag " + $X + "," + $Y + "  ->  " + $X2 + "," + $Y2)
        [TtsIn]::MoveTo($X, $Y); Start-Sleep -Milliseconds 200
        $d = [TtsIn]::LeftDown(); Start-Sleep -Milliseconds 250
        # intermediate steps: a single jump can be read as a teleport, not a drag
        for ($i = 1; $i -le 8; $i++) {
            $mx = [int]($X + ($X2 - $X) * $i / 8.0)
            $my = [int]($Y + ($Y2 - $Y) * $i / 8.0)
            [TtsIn]::MoveTo($mx, $my); Start-Sleep -Milliseconds 90
        }
        Start-Sleep -Milliseconds 200
        $u = [TtsIn]::LeftUp()
        Write-Host ("drag done  down=" + $d + " up=" + $u)
    }

    'key' {
        Assert-TtsForeground $st -ForceIt:$Force
        if ($Vk -le 0) { Write-Host "need -Vk"; exit 2 }
        $r = [TtsIn]::KeyPress([ushort]$Vk)
        Write-Host ("key 0x" + ('{0:X2}' -f $Vk) + " sent  events=" + $r)
    }
}
exit 0
