import argparse
import json
from pathlib import Path
import sys
from .theme import ASSETS, ThemeError, apply_theme, config_dir, load_theme, encode, atomic_write


def main(argv=None):
    parser = argparse.ArgumentParser(description="Themes for Polar Browser. Design, validate, preview, apply.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="List bundled themes")
    for command in ("validate", "use"):
        p = sub.add_parser(command, help="Validate a theme" if command == "validate" else "Apply a theme to the native adapter")
        p.add_argument("theme", help="Bundled ID or JSON file")
    p = sub.add_parser("new", help="Create an editable theme")
    p.add_argument("output", type=Path)
    p.add_argument("--from", dest="source", default="midnight")
    sub.add_parser("reset", help="Restore the Midnight theme")
    sub.add_parser("undo", help="Restore the previously applied theme")
    sub.add_parser("status", help="Show the active theme and native adapter status")
    p = sub.add_parser("studio", help="Serve the local theme editor")
    p.add_argument("--port", type=int, default=0, help="Loopback port; default chooses an available port")
    sub.add_parser("doctor", help="Check native adapter compatibility without changing Polar")
    args = parser.parse_args(argv)
    try:
        if args.command == "list":
            for row in json.loads((ASSETS / "themes/index.json").read_text()):
                theme = load_theme(row["id"])
                print("{:<12} {} — {}".format(theme["id"], theme["name"], theme["description"]))
        elif args.command == "validate":
            theme = load_theme(args.theme)
            print("Valid v1 theme: " + theme["name"])
        elif args.command in ("use", "reset", "undo"):
            name = "midnight" if args.command == "reset" else str(config_dir() / "previous.json") if args.command == "undo" else args.theme
            theme = load_theme(name)
            path = apply_theme(theme)
            print("Applied {} → {}".format(theme["name"], path))
            print("The native adapter reloads automatically. Install it first to change Polar's interface.")
        elif args.command == "new":
            if args.output.exists():
                raise ThemeError("Output already exists; choose another path")
            theme = load_theme(args.source)
            theme.update(id="my-theme", name="My Theme", author="", description="My Polar Browser theme")
            atomic_write(args.output, encode(theme))
            print("Created " + str(args.output))
        elif args.command in ("status", "doctor"):
            from .native import doctor
            result = doctor()
            current = config_dir() / "current.json"
            result["theme_file"] = str(current)
            result["active_theme"] = load_theme(str(current))["id"] if current.exists() else "midnight (default)"
            print(json.dumps(result, indent=2))
        elif args.command == "studio":
            from .server import serve
            serve(args.port)
    except (ThemeError, OSError, RuntimeError) as error:
        parser.exit(1, "polar-themes: " + str(error) + "\n")


if __name__ == "__main__":
    main()
