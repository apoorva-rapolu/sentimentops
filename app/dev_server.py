"""Tiny local stand-in for API Gateway — for frontend work without Docker or AWS.

    python dev_server.py            # API on http://localhost:8000
    then set API_BASE_URL: "http://localhost:8000" in frontend/config.js

It turns each HTTP request into an API Gateway (REST, v1) event, calls
handler.lambda_handler, and sends back the response. Not used in AWS.
"""

import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import handler  # noqa: E402

PORT = int(os.environ.get("PORT", "8000"))


class Proxy(BaseHTTPRequestHandler):
    def _forward(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8") if length else None
        event = {
            "httpMethod": self.command,
            "path": self.path.split("?")[0],
            "headers": dict(self.headers),
            "body": body,
            "isBase64Encoded": False,
        }
        res = handler.lambda_handler(event, None)
        self.send_response(res["statusCode"])
        for k, v in res.get("headers", {}).items():
            self.send_header(k, v)
        self.end_headers()
        if res.get("body"):
            self.wfile.write(res["body"].encode("utf-8"))

    do_GET = do_POST = do_OPTIONS = _forward


if __name__ == "__main__":
    print(f"SentimentOps dev API on http://localhost:{PORT}  (Ctrl+C to stop)")
    ThreadingHTTPServer(("", PORT), Proxy).serve_forever()
