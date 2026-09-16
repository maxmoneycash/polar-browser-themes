import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("native_adapter", ROOT / "scripts/native_adapter.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class Installer(unittest.TestCase):
    @unittest.skipUnless(shutil.which("pgrep") and shutil.which("sleep"), "pgrep and sleep are required")
    def test_running_application_is_rejected_and_stopped_one_is_accepted(self):
        # Exercise pgrep's own regular-expression dialect, including paths with spaces.
        with tempfile.TemporaryDirectory(prefix="polar themes ") as directory:
            app = Path(directory) / "Polar.app"
            executable = app / "Contents/MacOS/Polar"
            executable.parent.mkdir(parents=True)
            executable.symlink_to(shutil.which("sleep"))
            process = subprocess.Popen([str(executable), "30"])
            try:
                with self.assertRaisesRegex(ValueError, "Quit Polar normally"):
                    adapter.require_stopped(app)
            finally:
                process.terminate()
                process.wait(timeout=5)
            adapter.require_stopped(app)
