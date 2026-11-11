"""Local deterministic HTTPS fixture. Never use this service for real input."""
import http.server,json,ssl,time,pathlib
root=pathlib.Path(__file__).resolve().parents[2]
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
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
        pack=json.loads((root/'shared/ai-core/src/main/resources/default-prompts.json').read_text(encoding='utf-8'))
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
        if payload.get('model')=='transport-slow-body':
            self.reply({'choices':[{'message':{'content':json.dumps({'candidates':['你好，世界'],'completion':''},ensure_ascii=False)}}]},delay=4);return
        if payload.get('model')=='transport-duplicates':
            value='我今天下午有一个重要的会议，需要和团队一起讨论项目进度以及下周计划，请你明天早上九点之前把文件发给我。'
            self.reply({'choices':[{'message':{'content':json.dumps({'candidates':[value,value,value],'completion':''},ensure_ascii=False)}}]});return
        if payload.get('model')=='transport-provider-error':
            self.reply({'error':{'code':429,'message':'private synthetic provider details'}});return
        if request['input']=='slow':time.sleep(2)
        if payload.get('model')=='candidates-test':
            if '一个最可能的结果' not in system or '不编造或续写' not in system:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':json.dumps({'candidates':['你好，这是一段用于验证单个长候选仍然可以横向查看并点击上屏的文字。','不应显示的第二候选','不应显示的第三候选'],'completion':'不应显示的额外补全'},ensure_ascii=False)}}]});return
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
        candidate='Hello from AI.' if ('优先按英文纠错' in system) else '你好，世界'
        self.reply({'choices':[{'message':{'content':json.dumps({'candidates':[candidate],'completion':''},ensure_ascii=False)}}]})
    def reply(self,value,delay=0):
        body=json.dumps(value,ensure_ascii=False).encode()
        self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers()
        if delay:time.sleep(delay)
        try:self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError,ssl.SSLError):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',8443),Handler)
context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(root/'.tools/mock-cert.pem',root/'.tools/mock-key.pem')
server.socket=context.wrap_socket(server.socket,server_side=True)
print('Mock HTTPS listening on loopback:8443',flush=True)
server.serve_forever()
