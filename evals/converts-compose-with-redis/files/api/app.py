import hashlib
import hmac
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

import redis

r = redis.Redis.from_url(os.environ["REDIS_URL"])
BASE_URL = os.environ.get("BASE_URL", "http://localhost:8000")
SECRET_KEY = os.environ["SECRET_KEY"].encode()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        url = self.rfile.read(int(self.headers["Content-Length"])).decode()
        key = hmac.new(SECRET_KEY, url.encode(), hashlib.sha256).hexdigest()[:8]
        r.set(f"link:{key}", url, ex=7 * 86400)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"{BASE_URL}/{key}\n".encode())

    def do_GET(self):
        url = r.get(f"link:{self.path.lstrip('/')}")
        self.send_response(302 if url else 404)
        if url:
            self.send_header("Location", url.decode())
        self.end_headers()


HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
