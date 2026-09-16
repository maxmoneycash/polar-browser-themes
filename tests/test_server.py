from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
import os
import tempfile
from threading import Thread
import unittest
from unittest.mock import patch
from polar_themes.server import make_handler
from polar_themes.theme import config_dir, load_theme


class Studio(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {"POLAR_THEMES_HOME": self.temp.name})
        self.env.start()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler("test-token"))
        self.thread = Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.origin = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.env.stop()
        self.temp.cleanup()

    def request(self, method, path, data=None, headers=None):
        connection = HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        connection.request(method, path, body=data, headers=headers or {})
        response = connection.getresponse()
        status, body = response.status, response.read()
        connection.close()
        return status, body

    def test_static_preview_loads_without_authority_to_write(self):
        for path in ("/", "/app.js", "/style.css", "/themes/aurora.json", "/schema/theme.schema.json"):
            with self.subTest(path=path):
                self.assertEqual(self.request("GET", path)[0], 200)
        self.assertEqual(self.request("GET", "/themes/../../pyproject.toml")[0], 404)

    def test_apply_rejects_other_sites_missing_tokens_and_dns_rebinding(self):
        data = json.dumps(load_theme("aurora"))
        good = {"Origin": self.origin, "Content-Type": "application/json", "X-Polar-Themes-Token": "test-token"}
        for headers in ({}, {**good, "Origin": "https://example.com"},
                        {**good, "X-Polar-Themes-Token": "wrong"},
                        {**good, "Host": "evil.example"}):
            self.assertEqual(self.request("POST", "/api/apply", data, headers)[0], 403)
        self.assertFalse((config_dir() / "current.json").exists())

    def test_apply_validates_before_writing_and_saves_valid_data(self):
        headers = {"Origin": self.origin, "Content-Type": "application/json", "X-Polar-Themes-Token": "test-token"}
        self.assertEqual(self.request("POST", "/api/apply", "{}", headers)[0], 400)
        self.assertFalse((config_dir() / "current.json").exists())
        self.assertEqual(self.request("POST", "/api/apply", json.dumps(load_theme("porcelain")), headers)[0], 200)
        self.assertEqual(load_theme(str(config_dir() / "current.json"))["id"], "porcelain")


if __name__ == "__main__":
    unittest.main()
