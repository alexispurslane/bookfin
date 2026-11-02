import android_proxy


class RemainingHandler(android_proxy.Handler):
    def forward(self):
        if self.path.startswith('/probe/'):
            android_proxy.record({'method': self.command, 'path': android_proxy.evidence_path(self.path), 'probeSink': True, 'status': 200})
            body = b'<!doctype html><html><head><title>Owned request control</title></head><body><h1>Owned request control reached</h1><p>Synthetic loopback sink only.</p></body></html>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(body)
            return
        super().forward()


if __name__ == '__main__':
    android_proxy.Handler = RemainingHandler
    android_proxy.main()
