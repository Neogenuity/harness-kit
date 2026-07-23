#!/usr/bin/env python3
"""Standard-library HTTP fixture for deterministic live-runtime verification."""

import argparse
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SEED = {"items": [{"id": 1, "name": "Ada"}], "seed_version": 1}
BANNER_PATH = Path(__file__).with_name("banner.txt")


class AppHandler(BaseHTTPRequestHandler):
    server_version = "harness-runtime-fixture/1"

    def _log(self) -> None:
        with self.server.log_path.open("a", encoding="utf-8") as stream:
            stream.write(f"{self.command} {self.path} instance={self.server.instance}\n")

    def _send(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self._log()

    def _json(self, status: int, payload: object) -> None:
        body = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
        self._send(status, "application/json", body)

    def _data(self) -> dict:
        if not self.server.data_path.exists():
            return {"items": [], "seed_version": 0}
        return json.loads(self.server.data_path.read_text(encoding="utf-8"))

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler contract
        if self.path == "/health":
            status = "booting" if os.environ.get("HARNESS_FIXTURE_NEVER_READY") else "ready"
            self._json(200, {"instance": self.server.instance, "status": status})
        elif self.path == "/data":
            self._json(200, self._data())
        elif self.path == "/":
            items = self._data().get("items", [])
            name = items[0]["name"] if items else "unseeded"
            # Read per request so the fixture models the shipped verify-live
            # loop: change → health → reseed → replay on the same ready instance.
            banner = BANNER_PATH.read_text(encoding="utf-8").strip()
            self._send(200, "text/plain; charset=utf-8", f"{banner}: {name}\n".encode())
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler contract
        if self.path != "/seed":
            self._json(404, {"error": "not found"})
            return
        self.server.data_path.write_text(
            json.dumps(SEED, separators=(",", ":"), sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self._json(200, SEED)

    def log_message(self, _format: str, *_args: object) -> None:
        # Access records go to the repo-relative fixture log, never stdout.
        return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--instance", required=True)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()

    args.data.parent.mkdir(parents=True, exist_ok=True)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), AppHandler)
    server.instance = args.instance
    server.data_path = args.data
    server.log_path = args.log
    server.serve_forever()


if __name__ == "__main__":
    main()
