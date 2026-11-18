"""Local deterministic HTTPS fixture. Never use this service for real input."""
import http.server,json,ssl,time,pathlib
root=pathlib.Path(__file__).resolve().parents[2]
class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    requests=0
    retry_requests=0
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
        gemini=self.path=='/v1beta/interactions'
        if (self.headers.get('x-goog-api-key') if gemini else self.headers.get('Authorization'))!=('emulator-test-key' if gemini else 'Bearer emulator-test-key'):
            self.send_error(401);return
        type(self).requests += 1
        payload=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if payload.get('model') in ('assistant-test','assistant-stream-test','assistant-retry-test'):
            system=payload.get('instructions',payload.get('system_instruction','')) or payload.get('messages',[{}])[0].get('content','')
            assert 'No requests for more info; Give your best result directly.' in system
            assert '默认一个候选' not in system
            values=['What should I eat?','Try a sandwich.'] if 'Both candidates use English only.' in system else ['吃什么？','吃碗面吧。']
            if payload.get('model')=='assistant-retry-test':
                type(self).retry_requests += 1
                attempt = type(self).retry_requests
                values = [f'纠错第{attempt}次', f'助手第{attempt}次']
            if payload.get('model') in ('assistant-stream-test','assistant-retry-test'):
                assert payload.get('stream') is True
                self.send_response(200);self.send_header('Content-Type','text/event-stream');self.send_header('Connection','close');self.end_headers();self.close_connection=True
                def event(text):
                    e={'choices':[{'index':0,'delta':{'content':text}}]}
                    self.wfile.write(('data: '+json.dumps(e,ensure_ascii=False)+'\n\n').encode());self.wfile.flush()
                try:
                    event('['+json.dumps(values[0],ensure_ascii=False));time.sleep(2)
                    event(','+json.dumps(values[1],ensure_ascii=False)+']')
                    self.wfile.write(b'data: [DONE]\n\n');self.wfile.flush()
                except (BrokenPipeError,ConnectionResetError,ssl.SSLError):pass
                return
            if gemini:self.reply({'status':'completed','steps':[{'type':'model_output','content':[{'type':'text','text':values}]}]})
            elif self.path=='/v1/responses':self.reply({'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':values}]}]})
            else:self.reply({'choices':[{'message':{'content':values}}]})
            return
        if gemini:
            assert self.headers.get('Authorization') is None
            assert payload['generation_config']['thinking_level']=='low' and payload['store'] is False
            assert json.loads(payload['input'])['i']=='woxianghekafe' and 'before' not in payload and 'previous_interaction_id' not in payload
            self.reply({'status':'completed','steps':[{'type':'model_output','content':[{'type':'text','text':'我想喝咖啡'}]}],'usage':{'total_input_tokens':100,'total_output_tokens':7,'total_thought_tokens':20,'total_cached_tokens':0}});return
        if self.path=='/v1/responses':
            assert payload['reasoning']['effort']=='low' and payload['store'] is False
            assert json.loads(payload['input'])['i']=='woxianghekafe' and 'previous_response_id' not in payload
            self.reply({'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':'我想喝咖啡'}]}]});return
        request={'input':json.loads(payload['messages'][1]['content'])['i']}
        assert isinstance(request['input'],str)
        system=payload['messages'][0]['content']
        if payload.get('model')=='transport-slow-body':
            self.reply({'choices':[{'message':{'content':'你好，世界'}}]},delay=4);return
        if payload.get('model')=='transport-duplicates':
            value='我今天下午有一个重要的会议，需要和团队一起讨论项目进度以及下周计划，请你明天早上九点之前把文件发给我。'
            self.reply({'choices':[{'message':{'content':value}}]});return
        if payload.get('model')=='transport-provider-error':
            self.reply({'error':{'code':429,'message':'private synthetic provider details'}});return
        if request['input']=='slow':time.sleep(2)
        if payload.get('model')=='candidates-test':
            if '一个完整候选' not in system or 'candidates' in system:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':'你好，这是一段用于验证单个长候选仍然可以横向查看并点击上屏的文字。'}}]});return
        if payload.get('model')=='segmentation-test':
            if request['input']!='hanbaowang haochi' or '词组边界' not in system:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':'汉堡王好吃'}}]});return

        if payload.get('model')=='parameter-test':
            expected={'reasoning_effort':'low','service_tier':'priority','max_completion_tokens':128}
            if any(payload.get(k)!=v for k,v in expected.items()) or set(payload)!={'model','stream','messages',*expected}:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':'Parameters accepted'}}]});return
        if payload.get('model','').startswith('benchmark-') or payload.get('model')=='gpt-4o-mini':
            model=payload['model']
            if model=='benchmark-fail':self.send_error(400);return
            if model=='benchmark-slow':time.sleep(2)
            expected={'service_tier':'default'}
            if model!='gpt-4o-mini':expected['reasoning_effort']='none'
            if model=='benchmark-low':expected={'reasoning_effort':'low','service_tier':'priority'}
            if any(payload.get(k)!=v for k,v in expected.items()) or set(payload)!={'model','stream','messages',*expected}:
                self.send_error(422);return
            self.reply({'choices':[{'message':{'content':'参数正确'}}]});return
        candidate='Hello from AI.' if ('转英文' in system) else '你好，世界'
        self.reply({'choices':[{'message':{'content':candidate}}]})
    def reply(self,value,delay=0):
        # Production model text uses the compact JSON array contract.
        for choice in value.get('choices',[]):
            message=choice.get('message',{})
            if isinstance(message.get('content'),(str,list)):message['content']=json.dumps(message['content'] if isinstance(message['content'],list) else [message['content']],ensure_ascii=False,separators=(',',':'))
        for step in value.get('steps',[])+value.get('output',[]):
            for part in step.get('content',[]):
                if isinstance(part.get('text'),(str,list)):part['text']=json.dumps(part['text'] if isinstance(part['text'],list) else [part['text']],ensure_ascii=False,separators=(',',':'))
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
