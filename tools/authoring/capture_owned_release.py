import ctypes, json, sys
from ctypes import wintypes
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parents[1]))
import verify_standard_release_start as verify

state = json.loads(Path(sys.argv[1]).read_text())
kernel = ctypes.windll.kernel32
kernel.OpenProcess.restype = wintypes.HANDLE
kernel.QueryFullProcessImageNameW.argtypes = [
    wintypes.HANDLE,
    wintypes.DWORD,
    wintypes.LPWSTR,
    ctypes.POINTER(wintypes.DWORD),
]
kernel.CloseHandle.argtypes = [wintypes.HANDLE]
handle = kernel.OpenProcess(0x1000, False, state["pid"])
if not handle:
    raise RuntimeError("Owned process absent")
buffer = ctypes.create_unicode_buffer(32768)
length = wintypes.DWORD(len(buffer))
try:
    if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(length)):
        raise RuntimeError("Cannot verify owned image")
finally:
    kernel.CloseHandle(handle)
if Path(buffer.value).resolve() != Path(state["exe"]).resolve():
    raise RuntimeError("PID image mismatch")
h = verify.find_window(state["pid"])
assert h, "Owned visible window absent"
u = ctypes.windll.user32
g = ctypes.windll.gdi32
r = wintypes.RECT()
assert u.GetClientRect(h, ctypes.byref(r))
w = r.right
z = r.bottom
g.CreateCompatibleDC.restype = wintypes.HDC
g.CreateCompatibleBitmap.restype = wintypes.HBITMAP
u.GetDC.restype = wintypes.HDC
g.CreateCompatibleDC.argtypes = [wintypes.HDC]
g.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
g.SelectObject.argtypes = [wintypes.HDC, wintypes.HANDLE]
u.PrintWindow.argtypes = [wintypes.HWND, wintypes.HDC, wintypes.UINT]
g.GetDIBits.argtypes = [
    wintypes.HDC,
    wintypes.HBITMAP,
    wintypes.UINT,
    wintypes.UINT,
    ctypes.c_void_p,
    ctypes.c_void_p,
    wintypes.UINT,
]
g.DeleteObject.argtypes = [wintypes.HANDLE]
g.DeleteDC.argtypes = [wintypes.HDC]
u.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
s = u.GetDC(h)
d = g.CreateCompatibleDC(s)
b = g.CreateCompatibleBitmap(s, w, z)
previous = g.SelectObject(d, b)


class BI(ctypes.Structure):
    _fields_ = [
        ("size", wintypes.DWORD),
        ("w", wintypes.LONG),
        ("h", wintypes.LONG),
        ("planes", wintypes.WORD),
        ("bits", wintypes.WORD),
        ("compression", wintypes.DWORD),
        ("sizeimage", wintypes.DWORD),
        ("xp", wintypes.LONG),
        ("yp", wintypes.LONG),
        ("used", wintypes.DWORD),
        ("important", wintypes.DWORD),
    ]


try:
    assert u.PrintWindow(h, d, 3)
    i = BI()
    i.size = ctypes.sizeof(BI)
    i.w = w
    i.h = -z
    i.planes = 1
    i.bits = 32
    buf = ctypes.create_string_buffer(w * z * 4)
    assert g.GetDIBits(d, b, 0, z, buf, ctypes.byref(i), 0)
    target = Path(sys.argv[2])
    assert not target.exists()
    Image.frombuffer("RGB", (w, z), buf.raw, "raw", "BGRX", 0, 1).save(target)
finally:
    g.SelectObject(d, previous)
    g.DeleteObject(b)
    g.DeleteDC(d)
    u.ReleaseDC(h, s)
