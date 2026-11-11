"""Deterministically sample up to 100 printable-ASCII inputs per language/category."""
from pathlib import Path
import json,collections
root=Path(__file__).resolve().parent/'generated';counts=collections.Counter()
with (root/'typos.jsonl').open(encoding='utf-8') as source,(root/'native-sample.tsv').open('w',encoding='utf-8',newline='\n') as dest:
    for line in source:
        row=json.loads(line);group=(row['language'],row['category']);raw=row['input']
        if counts[group]>=100 or not raw or not all(32<=ord(c)<=126 for c in raw):continue
        dest.write(row['language']+'\t'+raw+'\n');counts[group]+=1
print('Native IPC cases:',sum(counts.values()))
