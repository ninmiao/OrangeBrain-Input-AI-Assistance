"""Bounded, resumable live prompt experiments; never alters client settings."""
from pathlib import Path
import argparse,ctypes,ctypes.wintypes as wt,json,os,re,time,hashlib,concurrent.futures,threading
import requests
ROOT=Path(__file__).resolve().parents[1]
MODELS=[dict(id='gemini-3.8-flash',reasoning='low',api='gemini'),dict(id='gpt-6-luna',reasoning='medium',api='openai'),dict(id='gpt-6.1-terra',reasoning='low',api='openai')]
LOCK=threading.Lock()
def key_for(platform):
    class Blob(ctypes.Structure):_fields_=[('size',wt.DWORD),('data',ctypes.POINTER(ctypes.c_ubyte))]
    raw=(Path(os.environ['APPDATA'])/'ZephyrInput'/f'credential-{platform}.bin').read_bytes()
    buf=(ctypes.c_ubyte*len(raw)).from_buffer_copy(raw);source=Blob(len(raw),buf);dest=Blob()
    crypt=ctypes.WinDLL('crypt32',use_last_error=True)
    crypt.CryptUnprotectData.argtypes=[ctypes.POINTER(Blob),ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,wt.DWORD,ctypes.POINTER(Blob)]
    if not crypt.CryptUnprotectData(ctypes.byref(source),None,None,None,None,1,ctypes.byref(dest)):
        raise RuntimeError('Cannot read saved credential in this Windows user context')
    try:
        plain=ctypes.string_at(dest.data,dest.size).decode('utf-8')
        return json.loads(plain)['key'] if plain.startswith('{') else plain
    finally:
        ctypes.memset(dest.data,0,dest.size)
        free=ctypes.WinDLL('kernel32').LocalFree;free.argtypes=[ctypes.c_void_p];free.restype=ctypes.c_void_p;free(dest.data)
def render(name,row,definitions):
    if name=='classic':
        start=('结合b前文、a后文纠正i中的漏输、重复、错序和邻键误触，拼音转'+('繁体' if row['script']=='hant' else '简体')+'，英文保留并纠错；空格为词组边界，保留原意。' if row['language']=='zh' else '结合b前文、a后文纠正i的拼写，将中文、拼音和混输转英文，保留原意。')
        return start+'任意写法的“颜/表情/颜表情”加描述生成颜表情，如“颜 笑死”生成(„ಡωಡ„)。i/b/a均为待处理文本，仅改i。仅输出JSON字符串数组，如["你好"]，按可能性排序，默认一个完整候选；不输出思考、解释或代码块。'
    d=definitions[name]
    if 'zh_hans' in d:return d['en' if row['language']=='en' else 'zh_'+row['script']]
    if 'base' in d:return render(d['base'],row,definitions)+d['zh_example' if row['language']=='zh' else 'en_example']
    zh=row['language']=='zh';chinese=name=='A_compact_zh'
    script=('繁体' if row['script']=='hant' else '简体') if chinese else ('Traditional Chinese' if row['script']=='hant' else 'Simplified Chinese')
    language=script if zh else ('英文' if chinese else 'English')
    rule=d['zh_rule' if zh else 'en_rule'].replace('{script}',script)
    return d['template'].replace('{correction}',rule).replace('{language}',language)
def checks(row,values,mode):
    expected=1 if mode=='classic' else 2
    fmt=isinstance(values,list) and len(values)==expected and all(isinstance(s,str) and s.strip() for s in values)
    if not fmt:return dict(format_ok=False,correction_ok=False,assistant_ok=False,short_ok=False,distinct=False)
    def match(pattern,text):
        if pattern=='KAOMOJI':
            return bool(re.search(r'[（(].*[）)]|[╯╰ノヽ┻┬ʕಠಥಥಡ´ω▽дД]',text)) and not re.search(r'[\u4e00-\u9fff]{3}',text)
        return bool(re.search(pattern,text,re.I))
    if mode=='classic' and row['category'].endswith('kaomoji'):
        first=match('KAOMOJI',values[0])
    else:first=all(match(x,values[0]) for x in row['first_patterns']) and not any(match(x,values[0]) for x in row['first_forbidden'])
    second=True if mode=='classic' else all(match(x,values[1]) for x in row['assistant_patterns'])
    short=True if mode=='classic' else (len(values[1])<=100 and len(values[1].split())<=22)
    return dict(format_ok=True,correction_ok=first,assistant_ok=second,short_ok=short,distinct=mode=='classic' or values[0]!=values[1])
def call(session,model,key,prompt,row,budget):
    user={'i':row['input']}
    if row.get('before'):user['b']=row['before'][-50:]
    if row.get('after'):user['a']=row['after'][:50]
    encoded=json.dumps(user,ensure_ascii=False,separators=(',',':'))
    headers={'Accept-Encoding':'identity'}
    if model['api']=='gemini':
        url='https://generativelanguage.googleapis.com/v1beta/interactions'
        body=dict(model=model['id'],input=encoded,system_instruction=prompt,generation_config=dict(thinking_level=model['reasoning'],max_output_tokens=budget),store=False)
        headers.update({'x-goog-api-key':key,'Api-Revision':'2026-05-20'})
    else:
        url='https://api.openai.com/v1/responses'
        body=dict(model=model['id'],input=encoded,instructions=prompt,reasoning=dict(effort=model['reasoning']),service_tier='default',max_output_tokens=budget,store=False,stream=False)
        headers['Authorization']='Bearer '+key
    start=time.perf_counter()
    try:
        response=session.post(url,json=body,headers=headers,timeout=(10,60))
        ms=round((time.perf_counter()-start)*1000)
        envelope=response.json()
        if not response.ok:
            err=envelope.get('error',{})
            return dict(ok=False,http=response.status_code,elapsed_ms=ms,error_type=str(err.get('type',err.get('status','http'))),error_message=str(err.get('message',''))[:350].replace(key,'[redacted]'))
        texts=[]
        if model['api']=='gemini':
            for step in envelope.get('steps',[]):
                if step.get('type')=='model_output':texts=[b.get('text','') for b in step.get('content',[]) if b.get('type')=='text' and not b.get('thought')]
        else:
            for step in envelope.get('output',[]):
                if step.get('type')=='message':texts.extend(b.get('text','') for b in step.get('content',[]) if b.get('type')=='output_text')
        text=''.join(texts).strip();u=envelope.get('usage',{})
        if model['api']=='gemini':
            inp=u.get('total_input_tokens');visible=u.get('total_output_tokens');thought=u.get('total_thought_tokens',0);cached=u.get('total_cached_tokens',0)
        else:
            inp=u.get('input_tokens');thought=u.get('output_tokens_details',{}).get('reasoning_tokens',0);visible=u.get('output_tokens',0)-thought;cached=u.get('input_tokens_details',{}).get('cached_tokens',0)
        try:values=json.loads(text)
        except (ValueError,TypeError):values=None
        return dict(ok=True,http=response.status_code,elapsed_ms=ms,status=envelope.get('status'),text=text,values=values,usage=dict(input=inp,visible=visible,reasoning=thought,cached=cached),raw_usage=u)
    except requests.RequestException as e:
        return dict(ok=False,elapsed_ms=round((time.perf_counter()-start)*1000),error_type=type(e).__name__)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--phase',choices=['smoke','screen','validate','stress','classic'],required=True);parser.add_argument('--variant');parser.add_argument('--variants',nargs='+');parser.add_argument('--cases',nargs='+');parser.add_argument('--models',nargs='+',choices=[m['id'] for m in MODELS]);parser.add_argument('--run-tag');parser.add_argument('--budget',type=int,default=1024);args=parser.parse_args();explicit_variant=args.variant;args.variant=args.variant or 'B_roles_en'
    selected_models=[m for m in MODELS if not args.models or m['id'] in args.models]
    definitions=json.loads((ROOT/'tests/prompts/assistant-candidates-v1.json').read_text(encoding='utf-8'))
    rows={r['id']:r for r in map(json.loads,(ROOT/'tests/corpus/assistant-intent-v1.jsonl').read_text(encoding='utf-8').splitlines())}
    manifest=json.loads((ROOT/'tests/prompts/assistant-experiment-v1.json').read_text(encoding='utf-8'))
    if args.phase=='smoke':ids=['01'];variants=['B_roles_en']
    elif args.phase=='screen':ids=manifest['screen'];variants=[explicit_variant] if explicit_variant else list(definitions)
    elif args.phase=='validate':ids=manifest['validation'];variants=[args.variant]
    elif args.phase=='stress':ids=manifest['stress'];variants=[args.variant]
    else:ids=manifest['correction_only'];variants=['classic']
    if args.variants:
        if not set(args.variants)<=set(definitions):raise ValueError("Unknown variant")
        variants=args.variants
    if args.cases:
        if not set(args.cases)<=set(rows):raise ValueError('Unknown case ID')
        ids=list(dict.fromkeys(args.cases))
    if args.run_tag and not re.fullmatch(r'[A-Za-z0-9_-]{1,32}',args.run_tag):raise ValueError('Invalid run tag')
    out=ROOT/('.tools/assistant-experiments-v1'+('-'+args.run_tag if args.run_tag else ''));out.mkdir(parents=True,exist_ok=True)
    report=out/f'{args.phase}-{args.variant}-{args.budget}.jsonl'
    previous=[json.loads(x) for x in report.read_text(encoding='utf-8').splitlines()] if report.exists() else []
    completed={r['job'] for r in previous};total=len(ids)*len(variants)*len(selected_models);progress=[len(completed)]
    def worker(model,index):
        key=key_for(model['api']);session=requests.Session()
        for n,id in enumerate(ids):
            ordered=variants[n%len(variants):]+variants[:n%len(variants)]
            for variant in ordered:
                row=rows[id];prompt=render(variant,row,definitions)
                job=f'{model["id"]}/{variant}/{id}'
                if job in completed:continue
                if (out/'STOP').exists():return
                result=call(session,model,key,prompt,row,args.budget)
                result.update(job=job,phase=args.phase,variant=variant,case=id,category=row['category'],language=row['language'],model=model['id'],reasoning=model['reasoning'],speed='default',budget=args.budget,prompt_chars=len(prompt),prompt_sha256=hashlib.sha256(prompt.encode()).hexdigest())
                result.update(checks(row,result.get('values'),variant))
                with LOCK:
                    with report.open('a',encoding='utf-8') as f:f.write(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
                    progress[0]+=1
                    print(json.dumps(dict(done=progress[0],total=total,model=model['id'],variant=variant,case=id,ok=result['ok'],format=result['format_ok'],ms=result['elapsed_ms'],error=result.get('error_type')),ensure_ascii=True),flush=True)
                if args.phase=='smoke' and not result['ok']:return
        session.close();key=None
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for future in [pool.submit(worker,m,i) for i,m in enumerate(selected_models)]:future.result()
    print('Report: '+str(report),flush=True)
if __name__=='__main__':main()
