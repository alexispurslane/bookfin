# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Serves the audio folder over HTTP with byte ranges, on 127.0.0.1 only,
# and logs each request's range and bytes, so the Android harness can
# stream a window through adb reverse as it would from Jellyfin. Usage:
#   speech_range_server.py <audio dir> <port> <log.jsonl>
import json, os, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT, PORT, LOG = os.path.realpath(sys.argv[1]), int(sys.argv[2]), sys.argv[3]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = os.path.realpath(os.path.join(ROOT, self.path.lstrip('/').split('?')[0]))
        if not path.startswith(ROOT + os.sep) or not os.path.isfile(path):
            self.send_error(404); return
        size = os.path.getsize(path)
        start, end = 0, size - 1
        match = re.match(r'bytes=(\d*)-(\d*)', self.headers.get('Range', ''))
        if match:
            if match.group(1): start = int(match.group(1))
            if match.group(2): end = min(int(match.group(2)), size - 1)
            if not match.group(1) and match.group(2): start, end = size - int(match.group(2)), size - 1
            self.send_response(206)
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        else:
            self.send_response(200)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Type', 'audio/mpeg')
        self.send_header('Content-Length', str(end - start + 1))
        self.end_headers()
        sent = 0
        try:
            with open(path, 'rb') as f:
                f.seek(start)
                while sent < end - start + 1:
                    chunk = f.read(min(65536, end - start + 1 - sent))
                    if not chunk: break
                    self.wfile.write(chunk); sent += len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        with open(LOG, 'a') as log:
            log.write(json.dumps({'at': time.time(), 'path': self.path, 'range': self.headers.get('Range'),
                                  'start': start, 'end': end, 'sent': sent}) + '\n')

    def log_message(self, *args):
        pass


ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
