"""Small, strict validator for the subset of JSON Schema used by theme v1.

The schema is shared by the Python CLI, browser editor, and native renderer.
Themes are complete data documents; unknown keys are errors, not silent no-ops.
"""
import json
import math
import os
from pathlib import Path
import re
import tempfile

ASSETS = Path(__file__).resolve().parent / "assets"
SCHEMA = json.loads((ASSETS / "schema/theme.schema.json").read_text())
MAX_BYTES = 32768


class ThemeError(ValueError):
    pass


def validate(value, rule, path="theme"):
    kind = rule.get("type")
    good = {"object": lambda: isinstance(value, dict),
            "string": lambda: isinstance(value, str),
            "number": lambda: type(value) in (int, float) and math.isfinite(value),
            "integer": lambda: type(value) is int,
            "boolean": lambda: type(value) is bool}
    if kind in good and not good[kind]():
        raise ThemeError("{} must be {}".format(path, kind))
    if "const" in rule and value != rule["const"]:
        raise ThemeError("{} must be {}".format(path, rule["const"]))
    if "enum" in rule and value not in rule["enum"]:
        raise ThemeError("{} must be one of {}".format(path, rule["enum"]))
    if kind == "object":
        props = rule["properties"]
        missing = set(rule.get("required", [])) - value.keys()
        extra = value.keys() - props.keys()
        if missing:
            raise ThemeError("{} is missing {}".format(path, ", ".join(sorted(missing))))
        if extra and rule.get("additionalProperties") is False:
            raise ThemeError("{} has unknown keys: {}".format(path, ", ".join(sorted(extra))))
        for key, item in value.items():
            if key in props:
                validate(item, props[key], path + "." + key)
    if kind == "string":
        if len(value) < rule.get("minLength", 0) or len(value) > rule.get("maxLength", 10000):
            raise ThemeError(path + " has an invalid length")
        if "pattern" in rule and not re.fullmatch(rule["pattern"], value):
            raise ThemeError(path + " has an invalid format")
    if kind in ("number", "integer"):
        if value < rule.get("minimum", -math.inf) or value > rule.get("maximum", math.inf):
            raise ThemeError(path + " is outside the supported range")


def validate_theme(value):
    validate(value, SCHEMA)
    return value


def decode_theme(data):
    if len(data) > MAX_BYTES:
        raise ThemeError("Theme exceeds 32 KiB")
    try:
        def unique(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise ThemeError("Duplicate JSON key: " + key)
                result[key] = value
            return result
        return validate_theme(json.loads(data, object_pairs_hook=unique))
    except (ValueError, UnicodeError) as error:
        raise ThemeError(str(error)) from error


def load_theme(name):
    path = Path(name).expanduser()
    if not path.is_file():
        if not re.fullmatch(r"[a-z][a-z0-9-]{0,47}", str(name)):
            raise ThemeError("Theme file not found: " + str(name))
        path = ASSETS / "themes" / (str(name) + ".json")
    try:
        with path.open("rb") as stream:
            return decode_theme(stream.read(MAX_BYTES + 1))
    except OSError as error:
        raise ThemeError("Cannot read theme: " + str(path)) from error


def config_dir():
    override = os.environ.get("POLAR_THEMES_HOME")
    return Path(override).expanduser() if override else Path.home() / "Library/Application Support/Polar Themes"


def atomic_write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".theme-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def apply_theme(theme):
    validate_theme(theme)
    path = config_dir() / "current.json"
    if path.is_file():
        try:
            old = decode_theme(path.read_bytes())
            atomic_write(config_dir() / "previous.json", encode(old))
        except ThemeError:
            pass
    atomic_write(path, encode(theme))
    return path


def encode(theme):
    return (json.dumps(theme, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")
