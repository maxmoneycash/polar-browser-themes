"""Read-only discovery. Installing the native adapter is a separate explicit step."""
from pathlib import Path
import plistlib
import platform

VERSION = "0.1.92"
BUILD = "20260913071337"


def doctor(app=Path("/Applications/Polar.app")):
    result = {"platform": platform.system(), "app_found": app.exists(), "supported_version": VERSION,
              "supported_build": BUILD, "adapter_installed": False, "version_matches": False}
    if not app.exists():
        return result
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    result.update(version=info.get("CFBundleShortVersionString"), build=info.get("CFBundleVersion"))
    result["version_matches"] = (result["version"], result["build"]) == (VERSION, BUILD)
    result["adapter_installed"] = (app / "Contents/Resources/PolarThemes/manifest.json").is_file()
    result["note"] = "Installation also verifies the original executable SHA-256; version alone is insufficient."
    return result
