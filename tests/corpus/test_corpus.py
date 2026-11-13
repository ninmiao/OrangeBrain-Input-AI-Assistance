import unittest,json,hashlib,collections,csv,tempfile
from pathlib import Path
from generate import mutations,NEIGHBORS,HERE,build

class CorpusTests(unittest.TestCase):
    def test_long_gold_inputs(self):
        with (HERE/'gold.tsv').open(encoding='utf-8') as stream:
            rows=list(csv.DictReader(stream,delimiter='\t'))
        for language in ('zh','en'):
            long_rows=[r for r in rows if r['language']==language and len(r['input'])>50]
            self.assertGreaterEqual(len(long_rows),8)
            self.assertTrue(all(len(r['input'])<=300 and r['expected'] for r in long_rows))

    def test_existing_corpus_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory);(out/'typos.jsonl').write_text('preserved',encoding='utf-8')
            with self.assertRaises(FileExistsError):build(1,out)
            self.assertEqual('preserved',(out/'typos.jsonl').read_text(encoding='utf-8'))

    def test_neighbor_geometry(self):
        self.assertIn('s',NEIGHBORS['a']);self.assertIn('q',NEIGHBORS['a']);self.assertNotIn('p',NEIGHBORS['a'])
    def test_mutations_reconstruct_input(self):
        for text in ['nihao','hanbaowang haochi','The keyboard works well.','123','I do not want to delete the file.']:
            for category,noisy,operations in mutations(text,42):
                actual=text
                for op,index,old,new in operations:
                    self.assertEqual(actual[index:index+len(old)],old)
                    actual=actual[:index]+new+actual[index+len(old):]
                self.assertEqual(actual,noisy)
                if category!='clean':self.assertNotEqual(text,noisy)
    def test_deterministic(self):self.assertEqual(list(mutations('keyboard',1)),list(mutations('keyboard',1)))
    def test_entire_generated_corpus(self):
        manifest=json.loads((HERE/'generated/manifest.json').read_text('utf-8'));digest=hashlib.sha256();count=0;splits={};counts=collections.Counter()
        with (HERE/'generated/typos.jsonl').open('rb') as f:
            for raw in f:
                digest.update(raw);row=json.loads(raw);count+=1;counts[row['language']+'/'+row['category']]+=1
                self.assertEqual(splits.setdefault(row['family'],row['split']),row['split'])
                self.assertTrue(row['expected']);self.assertTrue(all(isinstance(x,str) and x for x in row['expected']))
                self.assertLessEqual(len(row['input']),300)
                actual=row['clean_input']
                for _,i,old,new in row['operations']:
                    self.assertEqual(actual[i:i+len(old)],old);actual=actual[:i]+new+actual[i+len(old):]
                self.assertEqual(actual,row['input'])
        self.assertEqual(count,manifest['total']);self.assertEqual(digest.hexdigest(),manifest['sha256']);self.assertEqual(dict(counts),manifest['counts'])
if __name__=='__main__':unittest.main()
