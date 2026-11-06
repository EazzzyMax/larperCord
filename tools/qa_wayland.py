#!/usr/bin/env python3
"""Native Wayland smoke test, without a desktop or GPU.

Requires Weston, Xvfb and a built app. Uses isolated demo data, never an account.
    python3 tools/qa_wayland.py zig-out/bin/larpercord
"""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager, ExitStack


@contextmanager
def server(args, env, log, pass_fds=()):
    with open(log, "w") as output:
        proc = subprocess.Popen(args, env=env, stdout=output, stderr=output, pass_fds=pass_fds)
        try:
            yield proc
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def ready(proc, predicate, log):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            break
        if predicate():
            return
        time.sleep(0.05)
    raise RuntimeError(f"Display server did not start:\n{log.read_text()}")


def shot(binary, root, env, label, driver):
    image = root / f"{label}.png"
    result = subprocess.run(
        [binary, "--demo", "--no-live", "--stats", "--shot", str(image)],
        env=env, capture_output=True, text=True, timeout=45,
    )
    log = result.stdout + result.stderr
    if result.returncode or f"SDL video: {driver}," not in log:
        raise RuntimeError(f"{label}: expected {driver}, exit {result.returncode}\n{log}")
    data = image.read_bytes()
    if len(data) < 10000 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"{label}: missing rendered screenshot")
    size = struct.unpack(">II", data[16:24])
    print(f"PASS {label}: {driver}, {size[0]} x {size[1]}", flush=True)
    return size


def main():
    binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else "zig-out/bin/larpercord").resolve())
    for command in ("weston", "Xvfb"):
        if not shutil.which(command):
            raise RuntimeError(f"Install {command} to run the Wayland smoke test")
    with tempfile.TemporaryDirectory(prefix="larpercord-wayland-") as tmp, ExitStack() as servers:
        root = Path(tmp)
        env = {k: v for k, v in os.environ.items() if k not in (
            "DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET", "SDL_VIDEO_DRIVER",
            "SDL_VIDEODRIVER", "LARPER_TOKEN", "LARPER_HIDDEN", "LARPER_INSTANCE",
            "LARPER_SHOT_REAL", "DBUS_SESSION_BUS_ADDRESS", "QA_SUITE", "QA_SCENE",
        )}
        env.update(HOME=tmp, XDG_CONFIG_HOME=tmp + "/config", XDG_CACHE_HOME=tmp + "/cache",
                   XDG_RUNTIME_DIR=tmp, XDG_SESSION_TYPE="wayland", SDL_AUDIODRIVER="dummy",
                   LARPER_RENDERER="software", LARPER_NO_PICS="1", LARPER_EGL_ALL="1")
        # Keep X11 available alongside Wayland to exercise the native preference.
        # -displayfd allocates a free display; no fixed number or user's desktop.
        display_file = root / "display"
        log = root / "xvfb.log"
        with display_file.open("w") as display:
            proc = servers.enter_context(server(
                ["Xvfb", "-displayfd", str(display.fileno()), "-screen", "0", "1280x800x24",
                 "-nolisten", "tcp"], env, log, (display.fileno(),)))
            ready(proc, lambda: bool(display_file.read_text().strip()), log)
        env["DISPLAY"] = ":" + display_file.read_text().strip()
        help_text = subprocess.run(["weston", "--help"], capture_output=True, text=True).stdout
        renderer = "--renderer=pixman" if "--renderer" in help_text else "--use-pixman"
        sizes = []
        for scale in (1, 2):
            socket = f"wayland-test-{scale}"
            log = root / f"weston-{scale}.log"
            args = ["weston", "--backend=headless-backend.so", renderer, "--idle-time=0",
                    "--no-config", f"--socket={socket}", "--width=2560", "--height=1600",
                    f"--scale={scale}"]
            with server(args, env, log) as proc:
                ready(proc, lambda: (root / socket).exists(), log)
                native = dict(env, WAYLAND_DISPLAY=socket)
                # Auto must prefer Wayland even with a working X11 server.
                sizes.append(shot(binary, root, native, f"auto-{scale}x", "wayland"))
                # No DISPLAY: forced Wayland must also work without XWayland.
                forced = dict(native, SDL_VIDEO_DRIVER="wayland")
                forced.pop("DISPLAY")
                shot(binary, root, forced, f"forced-{scale}x", "wayland")
                if scale == 1:
                    shot(binary, root, dict(native, SDL_VIDEO_DRIVER="offscreen"), "offscreen-override", "offscreen")
        if sizes[1] != tuple(d * 2 for d in sizes[0]):
            raise RuntimeError(f"High-DPI framebuffer did not scale: {sizes}")

        x11 = dict(env, WAYLAND_DISPLAY="missing")
        shot(binary, root, x11, "x11-fallback", "x11")
        shot(binary, root, dict(x11, SDL_VIDEO_DRIVER="x11"), "x11-override", "x11")
        shot(binary, root, dict(env, XDG_SESSION_TYPE="x11"), "x11-session", "x11")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
