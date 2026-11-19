import argparse
import http.server
import socket
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def send(self, status, body, content_type="text/plain; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.send(200, '{"service":"fixture-opensim","status":"ready"}', "application/json; charset=utf-8")
        else:
            self.send(404, "not found")

    def do_POST(self):
        if self.path == "/StartSession/":
            self.send(200, "<ConsoleSession><SessionID>fixture-session</SessionID></ConsoleSession>", "application/xml; charset=utf-8")
        elif self.path == "/SessionCommand/":
            self.send(200, "shutdown accepted")
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        elif self.path == "/CloseSession/":
            self.send(200, "closed")
        else:
            self.send(404, "not found")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--world-port", type=int, required=True)
    parser.add_argument("--remote-admin-port", type=int, required=True)
    parser.add_argument("--unresponsive", action="store_true")
    args = parser.parse_args()
    if args.unresponsive:
        threading.Event().wait()
        return

    remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    remote.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    remote.bind(("127.0.0.1", args.remote_admin_port))
    remote.listen(8)
    remote.settimeout(0.5)
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.bind(("127.0.0.1", args.world_port))
    udp.settimeout(0.5)

    def answer_udp_probes():
        while True:
            try:
                _data, address = udp.recvfrom(256)
                udp.sendto(b"WOW-LIFECYCLE-READY", address)
            except socket.timeout:
                continue
            except OSError:
                return

    def drain(listener):
        while True:
            try:
                connection, _ = listener.accept()
                connection.close()
            except socket.timeout:
                continue
            except OSError:
                return

    threading.Thread(target=drain, args=(remote,), daemon=True).start()
    threading.Thread(target=answer_udp_probes, daemon=True).start()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.world_port), Handler)
    try:
        server.serve_forever(poll_interval=0.1)
    finally:
        server.server_close()
        remote.close()
        udp.close()


if __name__ == "__main__":
    main()
