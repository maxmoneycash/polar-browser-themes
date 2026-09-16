#!/usr/bin/env python3
"""Build the dependency-free, preview-only GitHub Pages site."""
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from polar_themes.theme import ASSETS, load_theme

destination = ROOT / "build/site"
destination.mkdir(parents=True, exist_ok=True)
for theme in (ASSETS / "themes").glob("*.json"):
    if theme.name != "index.json":
        load_theme(str(theme))
for file in (ASSETS / "studio").iterdir():
    shutil.copy2(file, destination / file.name)
for name in ("themes", "schema"):
    shutil.copytree(ASSETS / name, destination / name, dirs_exist_ok=True)
(destination / ".nojekyll").touch()
print(destination)
