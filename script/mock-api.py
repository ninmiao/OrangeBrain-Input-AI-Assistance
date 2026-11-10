"""Local deterministic HTTPS fixture. Never use this service for real input."""
import http.server,json,ssl,time,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
class Handler(http.server.BaseHTTPRequestHandler):
    requests=0
    def log_message(self,*args): pass
    def do_GET(self):
        if self.path=="/stats": self.reply({"requests":type(self).requests});return
        if self.path=="/v1/models":
            if self.headers.get('Authorization')!='Bearer emulator-test-key':self.send_error(401);return
            self.reply({'object':'list','data':[{'id':'mock','object':'model','owned_by':'fixture'},{'id':'parameter-test','object':'model','owned_by':'fixture'}]});return
        if self.path=="/model-catalog.json":
            if self.headers.get('Authorization'):self.send_error(403);return
            catalog=json.loads((root/'docs/ai/models-example.json').read_text(encoding='utf-8'))
            catalog['models'][0]['id']='parameter-test'
            self.reply(catalog);return
        if self.headers.get('Authorization'):self.send_error(403);return
        pack=json.loads((root/'ai-core/src/main/resources/default-prompts.json').read_text(encoding='utf-8'))
        pack['revision']=100;pack['version']='mock-100'
        self.reply(pack)
    def do_POST(self):
        if self.headers.get('Authorization')!='Bearer emulator-test-key':
            self.send_error(401);return
        type(self).requests += 1
        payload=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        request=json.loads(payload['messages'][1]['content'])
        assert set(request)=={'input','before','after'}
        system=payload['messages'][0]['content']
        if request['input']=='slow':time.sleep(2)
        if payload.get('model')=='candidates-test':
            if 'Target 5 distinct candidates' not in system:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':json.dumps({'candidates':['第一候选用于验证横向滑动','第二候选用于验证横向滑动','第三候选用于验证横向滑动','第四候选用于验证横向滑动','第五候选用于验证横向滑动'],'completion':''},ensure_ascii=False)}}]});return
        if payload.get('model')=='segmentation-test':
            if request['input']!='hanbaowang haochi' or '词组边界' not in system:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':json.dumps({'candidates':['汉堡王好吃'],'completion':''},ensure_ascii=False)}}]});return

        if payload.get('model')=='parameter-test':
            expected={'reasoning_effort':'low','service_tier':'priority','max_completion_tokens':128}
            if any(payload.get(k)!=v for k,v in expected.items()) or set(payload)!={'model','stream','messages',*expected}:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':json.dumps({'candidates':['Parameters accepted'],'completion':''})}}]});return
        if payload.get('model','').startswith('benchmark-') or payload.get('model')=='gpt-4o-mini':
            model=payload['model']
            if model=='benchmark-fail':self.send_error(400);return
            if model=='benchmark-slow':time.sleep(2)
            expected={'service_tier':'default'}
            if model!='gpt-4o-mini':expected['reasoning_effort']='none'
            if model=='benchmark-low':expected={'reasoning_effort':'low','service_tier':'priority'}
            if any(payload.get(k)!=v for k,v in expected.items()) or set(payload)!={'model','stream','messages',*expected}:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':json.dumps({'candidates':['参数正确'],'completion':''})}}]});return
        candidate='Hello from AI.' if ('当前为非中文键盘' in system or '当前为英文键盘' in system) else '你好，世界'
        self.reply({'choices':[{'message':{'content':json.dumps({'candidates':[candidate],'completion':''},ensure_ascii=False)}}]})
    def reply(self,value):
        body=json.dumps(value,ensure_ascii=False).encode()
        self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
server=http.server.ThreadingHTTPServer(('127.0.0.1',8443),Handler)
context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(root/'.tools/mock-cert.pem',root/'.tools/mock-key.pem')
server.socket=context.wrap_socket(server.socket,server_side=True)
print('Mock HTTPS listening on loopback:8443',flush=True)
server.serve_forever()
