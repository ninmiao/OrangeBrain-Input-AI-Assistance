"""Deterministic, licensed-source typo corpus. No cloud requests; standard library only."""
from pathlib import Path
import argparse, hashlib, json, random, csv, collections, string

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
ROWS=[('qwertyuiop',0.0),('asdfghjkl',0.25),('zxcvbnm',0.75)]
POINTS={c:(i+offset,y) for y,(row,offset) in enumerate(ROWS) for i,c in enumerate(row)}
NEIGHBORS={c:sorted(d for d,(xx,yy) in POINTS.items() if d!=c and (x-xx)**2+(y-yy)**2<=1.6) for c,(x,y) in POINTS.items()}

def mutations(text,seed):
    rng=random.Random(seed)
    positions=[i for i,c in enumerate(text) if c.lower() in POINTS]
    rng.shuffle(positions)
    yield 'clean',text,[]
    for i in positions[:3]:
        c=text[i];adj=rng.choice(NEIGHBORS[c.lower()]);adj=adj.upper() if c.isupper() else adj
        replacement=rng.choice([x for x in string.ascii_lowercase if x!=c.lower() and x not in NEIGHBORS[c.lower()]])
        yield 'omission',text[:i]+text[i+1:],[['delete',i,c,'']]
        yield 'repeat',text[:i]+c+text[i:],[['insert',i,'',c]]
        yield 'insert',text[:i]+adj+text[i:],[['insert',i,'',adj]]
        yield 'neighbor',text[:i]+adj+text[i+1:],[['replace',i,c,adj]]
        yield 'wrong_key',text[:i]+replacement+text[i+1:],[['replace',i,c,replacement]]
        if i+1<len(text) and text[i+1].isalpha() and text[i+1]!=c:
            yield 'transpose',text[:i]+text[i+1]+c+text[i+2:],[['swap',i,text[i:i+2],text[i:i+2][::-1]]]
    if len(positions)>=2:
        i,j=sorted(positions[:2]);adj=rng.choice(NEIGHBORS[text[j].lower()])
        yield 'compound',text[:i]+text[i+1:j]+adj+text[j+1:],[['replace',j,text[j],adj],['delete',i,text[i],'']]
    if ' ' in text:
        i=text.index(' ');yield 'boundary_missing',text[:i]+text[i+1:],[['delete',i,' ','']]
    elif len(text)>5:
        i=len(text)//2;yield 'boundary_extra',text[:i]+' '+text[i:],[['insert',i,'',' ']]

def chinese_seeds(limit):
    path=ROOT/'android/app/src/main/assets/shared/cn_dicts/base.dict.yaml'
    grouped=collections.defaultdict(list)
    for line in path.read_text('utf-8').splitlines():
        if line.startswith('#'):continue
        columns=line.split('\t')
        if len(columns)<2:continue
        word,pinyin=columns[:2];raw=pinyin.replace(' ','')
        if not 2<=len(word)<=16 or not 4<=len(raw)<=90 or not raw.isascii() or not raw.isalpha():continue
        grouped[raw].append(word)
    # Sample throughout the dictionary, never just the beginning of alphabetical order.
    keys=sorted(grouped,key=lambda x:hashlib.sha256(x.encode()).digest())[:limit]
    for raw in keys:yield 'zh',raw,list(dict.fromkeys(grouped[raw])),'rime-ice/base'

def english_seeds():
    entries=set(x.strip() for x in (HERE/'english-seeds.txt').read_text('utf-8').splitlines() if x.strip())
    people=['I','You','We','They']
    actions=['need to review','want to update','have to check','plan to discuss','do not want to delete','would like to save','should finish','might change','will send','can open']
    objects=['the document','the project','the report','the message','the application','the settings','the schedule','the proposal','the contract','the file','the list','the plan','the draft','the presentation','the order']
    times=['today','tomorrow','before the meeting','this afternoon']
    for p in people:
        for a in actions:
            for o in objects:
                for t in times:entries.add(f'{p} {a} {o} {t}.')
    for text in sorted(entries):yield 'en',text,[text],'zephyr-authored'

def build(limit,out):
    out.mkdir(parents=True,exist_ok=True);stats=collections.Counter();families=0;total=0
    digest=hashlib.sha256()
    with (out/'typos.jsonl').open('w',encoding='utf-8',newline='\n') as f:
        for language,clean,expected,source in list(chinese_seeds(limit))+list(english_seeds()):
            family=hashlib.sha256((language+'\0'+clean).encode()).hexdigest()[:16]
            split=['train','development','test'][0 if int(family[:4],16)%10<8 else 1 if int(family[:4],16)%10==8 else 2]
            seen=set();families+=1
            for category,noisy,operations in mutations(clean,int(family,16)):
                if noisy in seen:continue
                seen.add(noisy)
                row=dict(id=family+'-'+str(len(seen)),family=family,split=split,language=language,category=category,input=noisy,clean_input=clean,expected=expected,source=source,reviewed=False,operations=operations)
                encoded=json.dumps(row,ensure_ascii=False,separators=(',',':'))+'\n';f.write(encoded);digest.update(encoded.encode());stats[language+'/'+category]+=1;total+=1
    with (out/'gold.jsonl').open('w',encoding='utf-8',newline='\n') as f:
        for i,row in enumerate(csv.DictReader((HERE/'gold.tsv').open(encoding='utf-8'),delimiter='\t')):
            row['expected']=row['expected'].split('|');row.update(id='gold-'+str(i+1),reviewed=True,split='regression',source='zephyr-authored')
            f.write(json.dumps(row,ensure_ascii=False)+'\n')
    report=dict(schema=1,total=total,seed_families=families,sha256=digest.hexdigest(),counts=dict(sorted(stats.items())),note='Synthetic expected alternatives are source-derived references, not verified unique intended meanings. Report live model quality separately.')
    (out/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--chinese-seeds',type=int,default=20000);parser.add_argument('--output',type=Path,default=HERE/'generated');a=parser.parse_args()
    if not 1<=a.chinese_seeds<=200000:parser.error('seed count must be 1..200000')
    build(a.chinese_seeds,a.output)
