#!/usr/bin/env python3
"""Bundle the native build and its non-system dylibs into a relocatable macOS app."""
import argparse
import re
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output(args, text=True)


def dependencies(path, dylib=False):
    lines = run("otool", "-L", str(path)).splitlines()[1:]
    deps = [line.strip().split(" (", 1)[0] for line in lines]
    if dylib:
        # otool -L lists a dylib's LC_ID_DYLIB before its actual loads.
        ids = run("otool", "-D", str(path)).splitlines()[1:]
        if ids and deps and deps[0] == ids[0].strip():
            deps.pop(0)
    return deps


def rpaths(path):
    lines = run("otool", "-l", str(path)).splitlines()
    return [lines[i + 2].strip().removeprefix("path ").rsplit(" (offset ", 1)[0]
            for i, line in enumerate(lines) if line.strip() == "cmd LC_RPATH"]


def minimum_macos(path):
    if run("lipo", "-archs", str(path)).strip() != "arm64":
        raise RuntimeError(f"Expected an ARM64 Mach-O file: {path}")
    commands = run("otool", "-l", str(path))
    versions = re.findall(r"^\s+minos ([\d.]+)$", commands, re.MULTILINE)
    versions += re.findall(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([\d.]+)", commands)
    if not versions:
        raise RuntimeError(f"Missing macOS deployment target: {path}")
    return max(tuple(map(int, v.split("."))) for v in versions)


def expand_path(value, loader, executable):
    for prefix, directory in (("@loader_path", loader.parent),
                              ("@executable_path", executable.parent)):
        if value == prefix or value.startswith(prefix + "/"):
            return Path(str(directory) + value[len(prefix):])
    if value.startswith("@"):
        return None
    return Path(value)


def system_library(path):
    return str(path).startswith(("/System/Library/", "/usr/lib/"))


def resolve_dependency(dep, loader, executable, search_paths):
    if dep.startswith("@rpath/"):
        candidates = [path / dep[len("@rpath/"):] for path in search_paths]
    else:
        expanded = expand_path(dep, loader, executable)
        candidates = [expanded] if expanded else []
    for candidate in candidates:
        # System libraries can live in the dyld shared cache without a file on disk.
        if system_library(candidate):
            return candidate
        if candidate.is_file():
            return candidate.resolve()
    raise RuntimeError(f"Cannot resolve {dep!r} loaded by {loader}; searched {candidates}")


def make_icon(repo, resources):
    # Use the repository's existing logo artwork for the Finder/Dock icon.
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "LarperCord.iconset"
        iconset.mkdir()
        source = repo / "docs/assets/icon-180.png"
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = "@2x" if scale == 2 else ""
                run("sips", "-z", str(size * scale), str(size * scale), str(source),
                    "--out", str(iconset / f"icon_{size}x{size}{suffix}.png"))
        run("iconutil", "-c", "icns", str(iconset), "-o", str(resources / "LarperCord.icns"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, help="Destination .app (must not already exist)")
    parser.add_argument("--version", help="Version embedded in the build (defaults to source version)")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    source_binary = (repo / "zig-out/bin/larpercord").resolve(strict=True)
    minimum = max((15, 0), minimum_macos(source_binary))
    app = args.output.resolve()
    if app.suffix != ".app":
        raise SystemExit("The destination must end in .app")
    if app.exists():
        raise SystemExit(f"Refusing to replace existing bundle: {app}")
    contents = app / "Contents"
    binary_dir = contents / "MacOS"
    frameworks = contents / "Frameworks"
    resources = contents / "Resources"
    for directory in (binary_dir, frameworks, resources):
        directory.mkdir(parents=True)
    binary = binary_dir / "larpercord"
    shutil.copy2(source_binary, binary)
    version = args.version
    if version is None:
        match = re.search(r'pub const number = "([^"]+)";', (repo / "src/core/version.zig").read_text())
        if not match:
            raise RuntimeError("Could not determine app version; pass --version")
        version = match.group(1)
    plist = {
        "CFBundleName": "LarperCord",
        "CFBundleDisplayName": "LarperCord",
        "CFBundleIdentifier": "dev.larpercord",
        "CFBundleExecutable": "larpercord",
        "CFBundleIconFile": "LarperCord.icns",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "NSHighResolutionCapable": True,
        "NSMicrophoneUsageDescription": "LarperCord uses your microphone when you join a Discord voice call.",
        "NSPrincipalClass": "NSApplication",
    }
    make_icon(repo, resources)
    (resources / "fonts.conf").write_text('''<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
 <dir>/System/Library/Fonts</dir>
 <dir>/Library/Fonts</dir>
 <dir>~/Library/Fonts</dir>
 <cachedir prefix="xdg">fontconfig</cachedir>
 <alias><family>sans-serif</family><prefer><family>Helvetica Neue</family></prefer></alias>
 <alias><family>monospace</family><prefer><family>Menlo</family></prefer></alias>
 <alias><family>serif</family><prefer><family>Times</family></prefer></alias>
 <alias><family>emoji</family><prefer><family>Apple Color Emoji</family></prefer></alias>
</fontconfig>
''')
    licenses = resources / "Licenses"
    licenses.mkdir()
    shutil.copy2(repo / "LICENSE", licenses / "LarperCord-GPL-3.0.txt")
    for source in (repo / "third_party").rglob("*"):
        if source.is_file() and source.name.lower().startswith(("license", "copying")):
            target = licenses / source.relative_to(repo / "third_party")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    copied = {}
    # Carry the parent's run-path stack: dyld resolves @rpath through the load chain.
    queue = [(source_binary, binary, ())]
    while queue:
        source, target, inherited = queue.pop()
        local = []
        for entry in rpaths(source):
            path = expand_path(entry, source, source_binary)
            if path is None:
                raise RuntimeError(f"Unsupported rpath {entry!r} in {source}")
            local.append(path)
        search_paths = tuple(local) + inherited
        for dep in dependencies(source, dylib=(target != binary)):
            resolved = resolve_dependency(dep, source, source_binary, search_paths)
            if system_library(resolved):
                if dep != str(resolved):
                    run("install_name_tool", "-change", dep, str(resolved), str(target))
                continue
            name = resolved.name
            if name in copied and copied[name] != resolved:
                raise RuntimeError(f"Conflicting dylib names: {name}: {copied[name]} and {resolved}")
            if name not in copied:
                minimum = max(minimum, minimum_macos(resolved))
                copied[name] = resolved
                destination = frameworks / name
                shutil.copy2(resolved, destination)
                destination.chmod(0o755)
                run("install_name_tool", "-id", "@loader_path/" + name, str(destination))
                queue.append((resolved, destination, search_paths))
                keg = next((p for p in resolved.parents if p.parent.parent.name == "Cellar"), None)
                if keg:
                    for entry in keg.iterdir():
                        if entry.is_file() and entry.name.lower().startswith(("license", "copying")):
                            shutil.copy2(entry, licenses / (keg.parent.name + "-" + entry.name))
            prefix = "@executable_path/../Frameworks/" if target == binary else "@loader_path/"
            run("install_name_tool", "-change", dep, prefix + name, str(target))

    # All loads are now absolute system paths or bundle-relative paths. Remove
    # original rpaths so the finished bundle cannot accidentally use Homebrew.
    for target in [binary, *frameworks.iterdir()]:
        for path in rpaths(target):
            run("install_name_tool", "-delete_rpath", path, str(target))
    # Homebrew bottles can require a newer OS than the executable itself.
    plist["LSMinimumSystemVersion"] = ".".join(map(str, minimum))
    with (contents / "Info.plist").open("wb") as f:
        plistlib.dump(plist, f)
    for target in frameworks.iterdir():
        run("codesign", "--force", "--sign", "-", str(target))
    run("codesign", "--force", "--sign", "-", str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    print(f"Created {app} with {len(copied)} bundled libraries")


if __name__ == "__main__":
    main()
