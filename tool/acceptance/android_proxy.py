import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import threading
import time
import urllib.parse


ROOT = Path(__file__).resolve().parents[2] / '.cache/sync/runtime'
CONTROL = ROOT / 'android-proxy-control.json'
EVENTS = ROOT / 'android-proxy-events.jsonl'
LOCK = threading.Lock()


def safe_report(value):
    fields = {'ItemId', 'MediaSourceId', 'PositionTicks', 'IsPaused',
              'IsMuted', 'CanSeek', 'PlayMethod'}
    return {key: item for key, item in value.items()
            if key in fields and isinstance(item, (str, int, bool))}


def safe_path(value):
    parsed = urllib.parse.urlsplit(value)
    return (value.startswith('/') and not value.startswith('//')
            and not parsed.scheme and not parsed.netloc)


def evidence_path(value):
    return urllib.parse.urlsplit(value).path


def request_body(headers, stream):
    if headers.get('Transfer-Encoding', '').lower() != 'chunked':
        return stream.read(int(headers.get('Content-Length', 0)))
    chunks = []
    while True:
        length = int(stream.readline().split(b';')[0], 16)
        if length == 0:
            while stream.readline() not in {b'\r\n', b''}:
                pass
            return b''.join(chunks)
        chunks.append(stream.read(length))
        if stream.read(2) != b'\r\n':
            raise ValueError('Invalid request chunk')


def record(value):
    with LOCK:
        with EVENTS.open('a') as output:
            output.write(json.dumps({'at': time.time(), **value}) + '\n')


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def forward(self):
        if not safe_path(self.path):
            self.send_error(400)
            return
        path = evidence_path(self.path)
        control = json.loads(CONTROL.read_text()) if CONTROL.exists() else {}
        download = path.startswith('/Items/') and path.endswith('/Download')
        body = request_body(self.headers, self.rfile)
        event = {'method': self.command, 'path': path}
        if path.startswith('/Sessions/Playing') and body:
            event['report'] = safe_report(json.loads(body))
        if download and control.get('failItem') == path.split('/')[2]:
            self.send_response(503)
            self.send_header('Content-Length', '0')
            self.end_headers()
            record({**event, 'status': 503, 'injectedFailure': True})
            return
        upstream = http.client.HTTPConnection('127.0.0.1', 7364, timeout=30)
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() not in {'host', 'connection', 'transfer-encoding'}}
        try:
            upstream.request(self.command, self.path, body, headers)
            response = upstream.getresponse()
            event['status'] = response.status
            if download:
                event.update(length=response.getheader('Content-Length'),
                             etag=response.getheader('ETag'),
                             range=self.headers.get('Range'),
                             ifRange=self.headers.get('If-Range'))
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in {'connection', 'transfer-encoding'}:
                    self.send_header(key, value)
            self.end_headers()
            record(event)
            sent = 0
            while chunk := response.read(4096):
                self.wfile.write(chunk)
                self.wfile.flush()
                sent += len(chunk)
                if download:
                    if control.get('cutAfter') and sent >= control['cutAfter']:
                        record({**event, 'cutAfter': sent})
                        return
                    time.sleep(control.get('delay', 0))
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            record({**event, 'connectionInterrupted': True})
        finally:
            upstream.close()


def main():
    os.umask(0o077)
    marker = json.loads((ROOT / 'fixture.json').read_text())
    upstream = http.client.HTTPConnection('127.0.0.1', 7364, timeout=5)
    upstream.request('GET', '/System/Info/Public')
    public = json.loads(upstream.getresponse().read())
    upstream.close()
    if public['Id'] != marker['serverId'] or public['Version'] != '12.4.0':
        raise RuntimeError('Only this checkout disposable Jellyfin is allowed')
    server = ThreadingHTTPServer(('127.0.0.1', 7365), Handler)
    server.daemon_threads = True
    print('Private Android observer on loopback7365, real Jellyfin on7364', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
