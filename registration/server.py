"""Local Woz's World registration website. Only binds to loopback."""
import configparser
import html
import json
import re
import secrets
import threading
import urllib.parse
import xmlrpc.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'server' / 'OpenSimulator-0.9.3.0' / 'bin' / 'OpenSim.ini'
INSTALL = ROOT / '.local' / 'install.json'
TOKEN = secrets.token_urlsafe(32)
LOCK = threading.Lock()

PAGE = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Woz's World | Create account</title><style>body{font:17px system-ui;background:#101d27;color:#ecf5f7;margin:0}main{max-width:500px;margin:6vh auto;padding:32px;background:#1b303d;border-radius:16px}h1{margin:0 0 8px}p{color:#c4d5db}label{display:block;margin-top:18px}input{box-sizing:border-box;width:100%;padding:11px;margin-top:5px;border:1px solid #78929d;border-radius:6px;font:inherit}button{margin-top:24px;padding:12px 20px;border:0;border-radius:6px;background:#50d7bf;color:#082624;font-weight:bold;font-size:17px;cursor:pointer}.notice{padding:12px;background:#254c52;border-radius:6px}a{color:#86ead7}</style></head><body><main><h1>Woz's World</h1><p>Create your account to explore the world.</p>{message}<form method="post" action="/login"><input type="hidden" name="token" value="{token}"><label>First name<input name="first" required maxlength="31" autocomplete="given-name"></label><label>Last name<input name="last" required maxlength="31" autocomplete="family-name"></label><label>Password<input name="password" type="password" required minlength="8" maxlength="128" autocomplete="new-password"></label><label>Confirm password<input name="confirm" type="password" required maxlength="128" autocomplete="new-password"></label><label>Email (optional)<input name="email" type="email" maxlength="254" autocomplete="email"></label><button type="submit">Create account</button></form><p>After creating your account, sign in to Woz's World in Aurora with the same name and password.</p></main></body></html>'''

def page(message=''):
    notice = '<p class="notice" role="alert"><strong>' + html.escape(message) + '</strong></p>' if message else ''
    return PAGE.replace('{message}', notice).replace('{token}', TOKEN).encode('utf-8')

def success_page(first, last):
    name = html.escape(first + ' ' + last)
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Account created | Woz's World</title><style>body{{font:18px system-ui;background:#101d27;color:#ecf5f7;margin:0}}main{{max-width:520px;margin:10vh auto;padding:36px;background:#1b303d;border-radius:16px}}h1{{color:#64e4bd}}p{{line-height:1.5}}a{{color:#86ead7}}</style></head><body><main><h1>Account created</h1><p>Your account <strong>{name}</strong> has been created successfully.</p><p>Open Aurora, choose Woz's World, and sign in using this name and the password you just chose.</p><p><a href="/login">Create another account</a></p></main></body></html>'''.encode('utf-8')

def admin_password():
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.read(CONFIG, encoding='utf-8-sig')
    return config.get('RemoteAdmin', 'access_password').strip('"')

def service_ports():
    settings = json.loads(INSTALL.read_text(encoding='utf-8'))
    return int(settings['registrationPort']), int(settings['remoteAdminPort'])

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def reply(self, status, content):
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        if urllib.parse.urlsplit(self.path).path not in ('/', '/login', '/login/'):
            return self.reply(404, page('Page not found.'))
        self.reply(200, page())

    def do_POST(self):
        if self.path != '/login':
            return self.reply(404, page('Page not found.'))
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if size < 1 or size > 4096:
                return self.reply(400, page('Please check the form.'))
            data = urllib.parse.parse_qs(self.rfile.read(size).decode('utf-8'), keep_blank_values=True)
            one = lambda k: data.get(k, [''])[0]
            if not secrets.compare_digest(one('token'), TOKEN):
                return self.reply(403, page('Please reload the page and try again.'))
            first, last, password, email = one('first').strip(), one('last').strip(), one('password'), one('email').strip()
            if not all(re.fullmatch(r'[A-Za-z0-9_-]{1,31}', name) for name in (first, last)):
                return self.reply(400, page('Use letters, numbers, hyphens or underscores in each name.'))
            if len(password) < 8 or len(password) > 128 or password != one('confirm'):
                return self.reply(400, page('Passwords must match and contain at least eight characters.'))
            if len(email) > 254 or any(ord(c) < 32 for c in email):
                return self.reply(400, page('Please check the email address.'))
            with LOCK:
                _, remote_admin_port = service_ports()
                with xmlrpc.client.ServerProxy(f'http://127.0.0.1:{remote_admin_port}/', allow_none=True) as rpc:
                    result = rpc.admin_create_user({'password': admin_password(), 'user_firstname': first, 'user_lastname': last, 'user_password': password, 'user_email': email, 'start_region_x': 1000, 'start_region_y': 1000})
            if result.get('success'):
                return self.reply(200, success_page(first, last))
            return self.reply(400, page('The account could not be created. The name may already be in use.'))
        except Exception:
            return self.reply(503, page('The account service did not confirm the result. Check whether the account exists before trying again.'))

if __name__ == '__main__':
    port, _ = service_ports()
    ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
