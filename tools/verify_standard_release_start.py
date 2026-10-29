"""Target one owned Windows game window; retain screenshots for manual review."""

import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
from pathlib import Path
import subprocess
import time

USER = ctypes.windll.user32
USER.SetProcessDPIAware()
USER.GetForegroundWindow.restype = wintypes.HWND
CALLBACK = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def find_window(pid):
    found = []

    @CALLBACK
    def visit(hwnd, _):
        owner = wintypes.DWORD()
        USER.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and USER.IsWindowVisible(hwnd):
            found.append(int(hwnd))
        return True

    USER.EnumWindows(visit, 0)
    return found[0] if found else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action", choices=["launch", "capture", "click", "key", "close"]
    )
    parser.add_argument("state", type=Path)
    parser.add_argument("--exe", type=Path)
    parser.add_argument("--name", default="capture")
    parser.add_argument("--x", type=int)
    parser.add_argument("--y", type=int)
    parser.add_argument("--vk", type=int)
    args = parser.parse_args()
    if args.action == "launch":
        if args.state.exists() or not args.exe or not args.exe.is_file():
            raise RuntimeError("Fresh state and existing explicit executable required")
        with args.exe.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        process = subprocess.Popen(
            [str(args.exe), "--windowed", "--resolution", "1280x720"],
            cwd=args.exe.parent,
            creationflags=0x08000000,
        )
        state = {
            "pid": process.pid,
            "exe": str(args.exe.resolve()),
            "exe_sha256": digest,
        }
        args.state.write_text(json.dumps(state, indent=2), encoding="utf8")
        print(json.dumps(state))
        return
    state = json.loads(args.state.read_text(encoding="utf8"))
    # Query the live process image, not only a possibly reused PID.
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
        raise RuntimeError("Owned process is absent")
    buffer = ctypes.create_unicode_buffer(32768)
    length = wintypes.DWORD(len(buffer))
    try:
        if not kernel.QueryFullProcessImageNameW(
            handle, 0, buffer, ctypes.byref(length)
        ):
            raise RuntimeError("Cannot verify owned executable")
    finally:
        kernel.CloseHandle(handle)
    if Path(buffer.value).resolve() != Path(state["exe"]).resolve():
        raise RuntimeError("PID image mismatch")
    hwnd = find_window(state["pid"])
    if not hwnd:
        raise RuntimeError("Owned visible window is absent")
    if args.action == "close":
        USER.PostMessageW(hwnd, 0x0010, 0, 0)
        return
    rect = wintypes.RECT()
    USER.GetClientRect(hwnd, ctypes.byref(rect))
    origin = wintypes.POINT(0, 0)
    USER.ClientToScreen(hwnd, ctypes.byref(origin))
    if args.action == "capture":
        if USER.GetForegroundWindow() != hwnd:
            raise RuntimeError("Owned window is not foreground; no capture made")
        target = args.state.parent / (args.name + ".png")
        if target.exists():
            raise RuntimeError("Screenshot would overwrite evidence")
        subprocess.run(
            [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                "C:/Users/Zhang/.codex/skills/screenshot/scripts/take_screenshot.ps1",
                "-Path",
                str(target),
                "-Region",
                f"{origin.x},{origin.y},{rect.right},{rect.bottom}",
            ],
            check=True,
            capture_output=True,
        )
        print(target)
    elif args.action == "click":
        if (
            args.x is None
            or args.y is None
            or not (0 <= args.x < rect.right and 0 <= args.y < rect.bottom)
        ):
            raise RuntimeError("Inspected client coordinates required")
        position = args.x | (args.y << 16)
        if not USER.PostMessageW(hwnd, 0x0201, 1, position):
            raise RuntimeError("Owned-window mouse-down delivery failed")
        if not USER.PostMessageW(hwnd, 0x0202, 0, position):
            raise RuntimeError("Owned-window mouse-up delivery failed")
    elif args.action == "key":
        if args.vk is None or not 0 <= args.vk <= 255:
            raise RuntimeError("Explicit valid virtual key required")
        if not USER.PostMessageW(hwnd, 0x0100, args.vk, 0):
            raise RuntimeError("Owned-window key-down delivery failed")
        if not USER.PostMessageW(hwnd, 0x0101, args.vk, 0xC0000000):
            raise RuntimeError("Owned-window key-up delivery failed")
    event = {
        "action": args.action,
        "name": args.name,
        "x": args.x,
        "y": args.y,
        "vk": args.vk,
        "time": time.time(),
    }
    with (args.state.parent / "actions.jsonl").open("a", encoding="utf8") as stream:
        stream.write(json.dumps(event) + "\n")


if __name__ == "__main__":
    main()
