#!/usr/bin/env python3
"""Build/install the experimental, version-locked native Polar theme adapter.

No Polar binary is distributed. Build from your own signed installation.
Installation is explicit, reversible, and refuses a running or unknown app.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "native"))
import compat
from polar_themes.theme import ASSETS, config_dir, atomic_write, load_theme, encode

OUTPUT = ROOT / "build"
STUB = 0x100C6C400
FLAG = 0x100DE3F00


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def branch(source, destination):
    delta = destination - source
    if delta % 4 or not -(1 << 27) <= delta < (1 << 27):
        raise ValueError("Branch is out of range")
    return 0x14000000 | ((delta // 4) & 0x3FFFFFF)


def payload(data):
    offset = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid Mach-O command")
        if command == 0x19 and data[offset + 8:offset + 24].rstrip(b"\0") == b"__LINKEDIT":
            end = struct.unpack_from("<Q", data, offset + 40)[0]
            return data[0x2708:end]
        offset += size
    raise ValueError("Missing Mach-O __LINKEDIT")


def patch(original):
    compat.patched_bytes(original)  # SHA-256 and every instruction preimage.
    data = bytearray(original)
    for index, (address, before, after, _) in enumerate(compat.PATCHES):
        stub = STUB + 40 * index
        delta = (FLAG >> 12) - ((stub + 4) >> 12)
        adrp = 0x90000010 | ((delta & 3) << 29) | (((delta >> 2) & 0x7FFFF) << 5)
        words = [0xA9BF47F0, adrp, 0x39400211 | ((FLAG & 4095) << 10), 0x35000091,
                 0xA8C147F0, after, branch(stub + 24, address + 4),
                 0xA8C147F0, before, branch(stub + 36, address + 4)]
        offset = compat.file_offset(data, stub)
        if data[offset:offset + 40] != bytes(40):
            raise ValueError("Expected unused executable padding is occupied")
        struct.pack_into("<10I", data, offset, *words)
        struct.pack_into("<I", data, compat.file_offset(data, address), branch(address, stub))
    name = b"@executable_path/../Libraries/libPolarZen.dylib\0"
    size = (24 + len(name) + 7) & ~7
    commands, command_bytes = struct.unpack_from("<II", data, 16)
    end = 32 + command_bytes
    if end != 0x2630 or end + size > 0x2708 or data[end:end + size] != bytes(size):
        raise ValueError("Expected load-command padding is unavailable")
    struct.pack_into("<6I", data, end, 0xC, size, 24, 0, 0x10000, 0x10000)
    data[end + 24:end + 24 + len(name)] = name
    struct.pack_into("<II", data, 16, commands + 1, command_bytes + size)
    return bytes(data)


def build_library():
    OUTPUT.mkdir(exist_ok=True)
    schema = json.loads((ASSETS / "schema/theme.schema.json").read_text())
    header = "// Generated from the public schema and Midnight theme.\n"
    for name, value in (("PTSchemaJSON", schema), ("PTDefaultJSON", load_theme("midnight"))):
        header += "static const char {}[] = {};\n".format(name, json.dumps(json.dumps(value, separators=(",", ":"))))
    (OUTPUT / "ThemeData.h").write_text(header)
    names = ("PolarZen", "ZenPalette", "ThemeRuntime", "ThemeFrame")
    for name in names:
        run("xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=14.0", "-fobjc-arc", "-Wall", "-Wextra",
            "-Wno-unused-parameter", "-I", OUTPUT, "-c", ROOT / "native" / (name + ".m"), "-o", OUTPUT / (name + ".o"))
    run("xcrun", "swiftc", "-target", "arm64-apple-macos14.0", "-emit-library", "-parse-as-library",
        ROOT / "native/ZenBridge.swift", *[OUTPUT / (name + ".o") for name in names],
        "-framework", "AppKit", "-framework", "QuartzCore", "-o", OUTPUT / "libPolarZen.dylib")
    run("codesign", "--force", "--sign", "-", OUTPUT / "libPolarZen.dylib")


def verify(app):
    run("codesign", "--verify", "--strict", app)
    run("codesign", "--verify", "--strict", app / "Contents/Support/Polar Host.app")


def require_original(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != ("0.1.92", "20260913071337"):
        raise ValueError("Only Polar 0.1.92 build 20260913071337 (arm64) is supported")
    original = (app / "Contents/MacOS/Polar").read_bytes()
    compat.patched_bytes(original)
    verify(app)
    return original


def copy_app(source, target):
    if target.exists():
        raise ValueError("Destination already exists: " + str(target))
    run("/bin/cp", "-cR", source, target)


def build(original_app):
    original_app = original_app.resolve()
    original = require_original(original_app)
    build_library()
    candidate = OUTPUT / "Polar Themes.app"
    if candidate.exists():
        raise ValueError("build/Polar Themes.app already exists. Move it before rebuilding the app; library-only rebuilds use --library-only")
    copy_app(original_app, candidate)
    executable = candidate / "Contents/MacOS/Polar"
    executable.write_bytes(patch(original))
    executable.chmod(0o755)
    libraries = candidate / "Contents/Libraries"
    libraries.mkdir(exist_ok=True)
    shutil.copy2(OUTPUT / "libPolarZen.dylib", libraries / "libPolarZen.dylib")
    resources = candidate / "Contents/Resources/PolarThemes"
    resources.mkdir(parents=True, exist_ok=True)
    (resources / "manifest.json").write_text(json.dumps({"adapter": "0.1.0", "polar": "0.1.92", "build": "20260913071337", "original_sha256": compat.SOURCE_SHA256}) + "\n")
    profile = candidate / "Contents/embedded.provisionprofile"
    if profile.exists():
        profile.unlink()
    # Preserve normal entitlements, removing identity-bound ones that cannot
    # accompany a local ad-hoc signature. Never re-sign the Chromium host.
    ent = run("codesign", "-d", "--entitlements", ":-", original_app, capture_output=True).stdout
    entitlements = plistlib.loads(ent)
    for key in list(entitlements):
        if key in ("application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups") or key.startswith("com.apple.developer."):
            del entitlements[key]
    entitlements["com.apple.security.cs.disable-library-validation"] = True
    entitlements.pop("com.apple.security.get-task-allow", None)
    entitlements_path = OUTPUT / "theme.entitlements.plist"
    entitlements_path.write_bytes(plistlib.dumps(entitlements))
    run("codesign", "--force", "--sign", "-", "--options", "runtime", "--entitlements", entitlements_path, candidate)
    verify(candidate)
    report = {"original": str(original_app), "candidate": str(candidate), "original_sha256": compat.SOURCE_SHA256,
              "candidate_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(), "runtime_tested": False}
    atomic_write(OUTPUT / "build-report.json", (json.dumps(report, indent=2) + "\n").encode())
    print("Built " + str(candidate))
    print("The original app is unchanged. Quit Polar, then run the install command to activate.")


def require_stopped(app):
    process = str(app / "Contents/MacOS/Polar")
    result = subprocess.run(["pgrep", "-f", "^" + re.escape(process) + "($| )"], capture_output=True)
    if result.returncode == 0:
        raise ValueError("Quit Polar normally before installing or restoring. Existing tabs and profiles are preserved.")
    if result.returncode != 1:
        raise ValueError("Could not determine whether Polar is running")


def known_current(app, original):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != ("0.1.92", "20260913071337"):
        raise ValueError("Installed Polar has a different version. Refusing to replace or downgrade it.")
    data = (app / "Contents/MacOS/Polar").read_bytes()
    if data != original and payload(data) != payload(patch(original)):
        raise ValueError("Installed executable is neither the original nor our known adapter; refusing to replace it")


def replace_app(source, target):
    # Stage on the same filesystem. Keep the previous app, and roll back if the
    # final rename fails. No profile directories are ever read or modified.
    parent = Path(tempfile.mkdtemp(prefix=".polar-themes-", dir=target.parent))
    stage, previous = parent / "next.app", parent / "previous.app"
    try:
        copy_app(source, stage)
        verify(stage)
        target.rename(previous)
        try:
            stage.rename(target)
        except BaseException:
            previous.rename(target)
            raise
        return previous
    except BaseException:
        if not previous.exists():
            shutil.rmtree(parent)
        raise


def install(target):
    require_stopped(target)
    report = json.loads((OUTPUT / "build-report.json").read_text())
    source = Path(report["original"])
    original = require_original(source)
    known_current(target, original)
    candidate = Path(report["candidate"])
    if hashlib.sha256((candidate / "Contents/MacOS/Polar").read_bytes()).hexdigest() != report["candidate_sha256"]:
        raise ValueError("Candidate changed after it was built")
    verify(candidate)
    backup = config_dir() / "backups/Polar Original 0.1.92.app"
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        copy_app(source, backup)
    require_original(backup)
    previous = replace_app(candidate, target)
    record = {"app": str(target), "original": str(backup), "previous": str(previous), "installed_at": int(time.time())}
    atomic_write(config_dir() / "installation.json", (json.dumps(record, indent=2) + "\n").encode())
    print("Installed. Reopen Polar normally; themes now reload without restarting.")
    print("Original signed app backed up at " + str(backup))


def restore(target):
    require_stopped(target)
    record = json.loads((config_dir() / "installation.json").read_text())
    if Path(record["app"]).resolve() != target.resolve():
        raise ValueError("Installation record is for another app")
    original_app = Path(record["original"])
    original = require_original(original_app)
    known_current(target, original)
    previous = replace_app(original_app, target)
    print("Restored the original signed Polar. Previous customized app retained at " + str(previous))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "install", "restore"])
    parser.add_argument("--app", type=Path, default=Path("/Applications/Polar.app"))
    parser.add_argument("--original", type=Path, help="Untouched, supported Polar installation to build from")
    parser.add_argument("--library-only", action="store_true", help="Compile native code without an app or installation")
    args = parser.parse_args()
    try:
        if platform.system() != "Darwin":
            raise ValueError("The native adapter requires macOS and Xcode command-line tools")
        if args.action == "build":
            build_library() if args.library_only else build(args.original or args.app)
        elif args.action == "install":
            install(args.app.resolve())
        else:
            restore(args.app.resolve())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, "native-adapter: " + str(error) + "\n")


if __name__ == "__main__":
    main()
