"""Interactive live API verification. Credentials exist only in process memory."""
import getpass
import warnings
import json
import sys
import time
import urllib.request
import urllib.error
import pathlib
import importlib.util
import http.server
import secrets
import ssl
import threading

ROOT = pathlib.Path(__file__).resolve().parents[2]

with warnings.catch_warnings():
    warnings.simplefilter('error', getpass.GetPassWarning)
    KEY = getpass.getpass('Temporary API key (hidden): ')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirect)

def request(path, payload=None):
    started = time.monotonic()
    req = urllib.request.Request('https://api.openai.com/v1/' + path,
        data=None if payload is None else json.dumps(payload).encode(),
        headers={'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json'})
    try:
        with opener.open(req, timeout=45) as response:
            status = response.status
            body = json.load(response)
    except urllib.error.HTTPError as exc:
        status = exc.code
        body = json.loads(exc.read().decode())
    except Exception as exc:
        return {'network_error': type(exc).__name__, 'message': str(exc).replace(KEY, '[redacted]')}
    result = {'status': status, 'seconds': round(time.monotonic() - started, 3)}
    if status != 200:
        error = body.get('error', {})
        result['error'] = {k: str(error.get(k, '')).replace(KEY, '[redacted]') for k in ('type', 'code', 'param', 'message')}
    elif path == 'models':
        result['models'] = sorted(x['id'] for x in body['data'])
    else:
        result.update({k: body.get(k) for k in ('model', 'choices', 'usage', 'service_tier')})
    return result

print(json.dumps({'ready': True}), flush=True)
server = None
while True:
    try:
        line = input()
        command = json.loads(line)
        if command.get('exit'):
            break
        if command.get('suite'):
            spec = importlib.util.spec_from_file_location('live_suite', ROOT / 'android/script/live-api-suite.py')
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            print(json.dumps(module.run(request, command.get('suffix', 'initial'), command.get('case_ids'))), flush=True)
            continue
        if command.get('bridge'):
            if server:
                server.shutdown()
                server.server_close()
            token = secrets.token_urlsafe(32)
            state = {'available': True, 'requests': 0}
            class Handler(http.server.BaseHTTPRequestHandler):
                def log_message(self, *args):
                    pass
                def do_GET(self):
                    if self.path != '/credential/' + token or not state['available']:
                        self.send_error(404)
                        return
                    state['available'] = False
                    state['requests'] += 1
                    body = json.dumps({'key': KEY}).encode()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Cache-Control', 'no-store')
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
            server = http.server.HTTPServer(('127.0.0.1', 8443), Handler)
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.load_cert_chain(ROOT / '.tools/mock-cert.pem', ROOT / '.tools/mock-key.pem')
            server.socket = tls.wrap_socket(server.socket, server_side=True)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            print(json.dumps({'bridge_token': token, 'port': 8443, 'one_shot': True}), flush=True)
            continue
        if command.get('bridge_status'):
            print(json.dumps({'requests': state['requests'], 'available': state['available']}), flush=True)
            continue
        print(json.dumps(request(command.get('path', 'models'), command.get('payload')), ensure_ascii=True), flush=True)
    except EOFError:
        break
    except Exception as exc:
        print(json.dumps({'runner_error': type(exc).__name__}), flush=True)
KEY = ''
if server:
    server.shutdown()
    server.server_close()
print(json.dumps({'credential_memory_cleared': True}), flush=True)
