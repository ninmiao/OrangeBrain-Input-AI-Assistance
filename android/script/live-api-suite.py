"""Bounded OpenAI evaluation of current-input-only, plain-text candidates.

The caller supplies an authenticated request callback. No credentials are accepted or saved here.
"""
import concurrent.futures
import datetime
import hashlib
import json
import pathlib
import statistics

ROOT=pathlib.Path(__file__).resolve().parents[2]

def validate(response):
    if response.get('status')!=200:return False
    try:
        assert response.get('response_status','completed')=='completed'
        text=''.join(part['text'] for item in response['output'] if item.get('type')=='message'
                     for part in item.get('content',[]) if part.get('type')=='output_text').strip()
        assert text and len(text.encode())<=32768 and len(text.encode('utf-16-le'))//2<=2000
        response['candidate']=text
        return True
    except (KeyError,ValueError,TypeError,AssertionError,IndexError):return False

def run(request,suffix='current',case_ids=None):
    model='gpt-6-luna'
    if isinstance(case_ids,dict):
        model=case_ids.get('model',model);case_ids=case_ids.get('ids')
    if not model.strip() or len(model)>256:raise ValueError('Invalid model ID')
    if not suffix or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_' for c in suffix):raise ValueError('Invalid report suffix')
    raw=(ROOT/'shared/ai-core/src/main/resources/default-prompts.json').read_bytes()
    pack=json.loads(raw)
    cases=json.loads((ROOT/'docs/ai/evaluation-cases.json').read_text(encoding='utf-8'))['cases']
    if case_ids:cases=[c for c in cases if c['id'] in case_ids]
    if len(cases)>100:raise ValueError('This smoke suite is limited to 100 cases')
    def execute(case):
        prompt=pack['keyboard_language_rules']['chinese' if case['chinese_keyboard'] else 'non_chinese'].replace('【简体/繁体】','简体')
        payload={'model':model,'stream':False,'store':False,'instructions':prompt,'input':case['input']}
        if model.startswith(('gpt-6-luna','gpt-6-sol','gpt-5.4')):payload['reasoning']={'effort':'none'}
        elif model.startswith('gpt-6.1-terra'):payload['reasoning']={'effort':'low'}
        response=request('responses',payload)
        valid=validate(response)
        # Reports contain only synthetic candidates, status, timing and usage.
        return {'case':case['id'],'model':model,'protocol_valid':valid,
                **{k:response[k] for k in ('status','seconds','usage','candidate') if k in response}}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(execute,cases))
    output=ROOT/'tests/reports'/('live-results-'+suffix+'.json')
    output.parent.mkdir(parents=True,exist_ok=True)
    report={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'prompt_sha256':hashlib.sha256(raw).hexdigest(),
            'prompt_version':pack['version'],'model':model,'synthetic_cases_only':True,'results':results}
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    times=sorted(r['seconds'] for r in results if r.get('status')==200 and 'seconds' in r)
    return {'report':str(output),'requests':len(results),'http_ok':sum(r.get('status')==200 for r in results),
            'protocol_valid':sum(r['protocol_valid'] for r in results),'p50_seconds':statistics.median(times) if times else None,
            'input_tokens':sum(r.get('usage',{}).get('input_tokens',0) for r in results),
            'output_tokens':sum(r.get('usage',{}).get('output_tokens',0) for r in results)}
