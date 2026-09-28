"""Exercise real Quickshell IPC and the worker against a local HTTP fixture."""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest


@unittest.skipUnless(shutil.which("qs") and shutil.which("uv"), "Quickshell and uv required")
class ServiceIntegrationTest(unittest.TestCase):
    def test_shared_service_download_and_generation_guard(self):
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                raw = b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:integration\r\nDTSTART:20260928T090000\r\nSUMMARY:Integration meeting\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
                self.send_response(200)
                self.send_header("Content-Type", "text/calendar")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def log_message(self, *_):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".config/intemporel/calendars.jsonc"
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({"calendars": [{"name": "Test", "url": f"http://127.0.0.1:{server.server_port}/feed.ics"}]}))
            env = {**os.environ, "HOME": directory, "XDG_CACHE_HOME": str(home / ".cache"),
                   "UV_CACHE_DIR": str(Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "uv"),
                   "QT_QPA_PLATFORM": "offscreen", "QS_DISABLE_FILE_WATCHER": "1", "PYTHONDONTWRITEBYTECODE": "1"}
            # Quickshell scopes relative imports to its config root. Keep the
            # temporary entry point alongside the plugin, not inside tests/.
            source = Path(__file__).with_name("service.qml").read_text().replace('"../service"', '"service"')
            with tempfile.NamedTemporaryFile(mode="w", suffix=".qml", prefix="test-service-", dir=Path(__file__).parent.parent) as harness:
                harness.write(source)
                harness.flush()
                result = subprocess.run(["qs", "--no-color", "-p", harness.name],
                                        env=env, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertIn("SERVICE_TEST_PASSED", output, output)
            self.assertNotIn("SERVICE_TEST_FAILED", output)
            self.assertEqual(requests, ["/feed.ics"])
            cache = json.loads((home / ".cache/intemporel-calendar-cache.json").read_text())
            self.assertEqual(len(cache["feeds"]), 1)
