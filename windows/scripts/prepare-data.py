"""Generate Windows data directly from committed sources; no Android build needed."""
from pathlib import Path
import shutil, subprocess, sys
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'android/app/src/main/assets/shared'
target=ROOT/'windows/native/output/data';target.mkdir(parents=True,exist_ok=True)
for p in source.iterdir():
    if p.name.startswith('rime_ai_ios') or p.name=='opencc':continue
    if p.is_dir():shutil.copytree(p,target/p.name,dirs_exist_ok=True)
    else:shutil.copy2(p,target/p.name)
for p in (ROOT/'windows/data').glob('*.yaml'):shutil.copy2(p,target/p.name)
cc=ROOT/'android/app/src/main/jni/OpenCC/data';out=target/'opencc';out.mkdir(exist_ok=True)
for p in (cc/'dictionary').glob('*.txt'):shutil.copy2(p,out/p.name)
subprocess.run([sys.executable,str(cc/'scripts/merge.py'),*[str(cc/'dictionary'/f'{n}.txt') for n in ('TWPhrasesIT','TWPhrasesName','TWPhrasesOther')],str(out/'TWPhrases.txt')],check=True)
for n in ('TWPhrases','TWVariants','HKVariants','JPVariants'):
    subprocess.run([sys.executable,str(cc/'scripts/reverse.py'),str(out/f'{n}.txt'),str(out/f'{n}Rev.txt')],check=True)
for p in (cc/'config').glob('*.json'):
    (out/p.name).write_text(p.read_text('utf-8').replace('"ocd2"','"text"').replace('.ocd2','.txt'),encoding='utf-8')
print('Shared Rime Ice and generated OpenCC text dictionaries ready.')
