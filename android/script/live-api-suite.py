"""Bounded real-service evaluation using the shipped prompt and synthetic cases."""
import concurrent.futures
import datetime
import hashlib
import json
import pathlib
import statistics

ROOT = pathlib.Path(__file__).resolve().parents[2]

def validate(response, completion):
    if response.get('status') != 200:
        return False
    try:
        text = response['choices'][0]['message']['content']
        obj = json.loads(text)
        candidates = obj['candidates']
        assert set(obj) == {'candidates', 'completion'}
        assert len(text.encode()) <= 32768
        assert isinstance(candidates, list) and len(candidates) <= 3
        assert all(isinstance(x, str) and x.strip() and len(x.encode('utf-16-le')) // 2 <= 2000 for x in candidates)
        assert len({x.strip() for x in candidates}) == len(candidates)
        assert isinstance(obj['completion'], str) and len(obj['completion'].encode('utf-16-le')) // 2 <= 2000
        response['parsed'] = obj
        response['completion_off_respected'] = completion or obj['completion'] == ''
        return True
    except (KeyError, ValueError, TypeError, AssertionError, IndexError):
        return False

def run(request, suffix='initial', case_ids=None):
    model = 'gpt-4.1-mini'
    if isinstance(case_ids, dict):
        model = case_ids.get('model', model)
        case_ids = case_ids.get('ids')
    if model not in ('gpt-4.1-mini', 'gpt-5-mini', 'gpt-5.4-mini'):
        raise ValueError('This bounded suite allows only the three reviewed small models')
    raw = (ROOT / 'shared/ai-core/src/main/resources/default-prompts.json').read_bytes()
    pack = json.loads(raw)
    cases = json.loads((ROOT / 'docs/ai/evaluation-cases.json').read_text(encoding='utf-8'))['cases']
    if case_ids:
        cases = [x for x in cases if x['id'] in case_ids]
    jobs = []
    for case in cases:
        for style in pack['styles']:
            completion = case.get('completion_enabled', False)
            prompt = '\n\n'.join([pack['base_prompt'], style['instruction'],
                pack['completion_on' if completion else 'completion_off'],
                pack['keyboard_language_rules']['chinese' if case['chinese_keyboard'] else 'non_chinese']])
            payload = {'model': model, 'stream': False, 'messages': [
                {'role': 'system', 'content': prompt},
                {'role': 'user', 'content': json.dumps({'input': case['input'], 'before': '', 'after': ''}, ensure_ascii=False)}],
                'max_completion_tokens': 1000}
            jobs.append((case['id'], style['id'], completion, payload))
    if not case_ids:
        base = next(x[3] for x in jobs if x[0] == 'mixed-english' and x[1] == 'original')
        variants = [
            ('omitted', 'gpt-4.1-mini', {}),
            ('normal', 'gpt-4.1-mini', {'service_tier': 'default', 'max_completion_tokens': 512}),
            ('fast', 'gpt-4.1-mini', {'service_tier': 'priority', 'max_completion_tokens': 512}),
            ('temperature', 'gpt-4.1-mini', {'temperature': 0, 'max_completion_tokens': 512}),
            ('top-p', 'gpt-4.1-mini', {'top_p': 0.8, 'max_completion_tokens': 512}),
            ('reasoning-minimal', 'gpt-5-mini', {'reasoning_effort': 'minimal', 'max_completion_tokens': 2048}),
            ('reasoning-low', 'gpt-5-mini', {'reasoning_effort': 'low', 'max_completion_tokens': 2048}),
            ('reasoning-none', 'gpt-5.4-mini', {'reasoning_effort': 'none', 'max_completion_tokens': 1024}),
            ('invalid-reasoning', 'gpt-4.1-mini', {'reasoning_effort': 'low', 'max_completion_tokens': 512}),
            ('invalid-temperature', 'gpt-5-mini', {'temperature': 0.2, 'reasoning_effort': 'minimal', 'max_completion_tokens': 512}),
        ]
        for name, parameter_model, params in variants:
            jobs.append(('parameter-' + name, 'original', False,
                {**{k: v for k, v in base.items() if k != 'max_completion_tokens'}, 'model': parameter_model, **params}))
    results = []
    def execute(job):
        case, style, completion, payload = job
        response = request('chat/completions', payload)
        return {'case': case, 'style': style, 'requested_model': payload['model'],
            'parameters': {k: v for k, v in payload.items() if k not in ('model', 'messages', 'stream')},
            'protocol_valid': validate(response, completion), **response}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(execute, jobs):
            results.append(result)
            if len(results) % 10 == 0 or len(results) == len(jobs):
                print(json.dumps({'progress': len(results), 'total': len(jobs), 'http_ok': sum(x.get('status') == 200 for x in results)}), flush=True)
    output = ROOT / 'docs/ai' / ('live-results-' + suffix + '.json')
    report = {'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'prompt_sha256': hashlib.sha256(raw).hexdigest(), 'prompt_version': pack['version'],
        'model': model, 'synthetic_cases_only': True, 'results': results}
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    times = sorted(x['seconds'] for x in results if x.get('status') == 200)
    return {'report': str(output), 'requests': len(results), 'http_ok': len(times),
        'protocol_valid': sum(x['protocol_valid'] for x in results),
        'p50_seconds': statistics.median(times) if times else None,
        'prompt_tokens': sum(x.get('usage', {}).get('prompt_tokens', 0) for x in results),
        'completion_tokens': sum(x.get('usage', {}).get('completion_tokens', 0) for x in results)}
