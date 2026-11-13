import subprocess,sys,pathlib,json,hashlib,datetime
root=pathlib.Path(__file__).parent
name,*cmd=sys.argv[1:]
head=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
patch=subprocess.check_output(['git','diff','HEAD'])
(root/(name+'.patch')).write_bytes(patch)
start=datetime.datetime.now(datetime.timezone.utc).isoformat()
with (root/(name+'.log')).open('wb') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
data=(root/(name+'.log')).read_bytes()
record=dict(name=name,command=cmd,head=head,started=start,ended=datetime.datetime.now(datetime.timezone.utc).isoformat(),exitCode=r.returncode,log=name+'.log',sha256=hashlib.sha256(data).hexdigest(),patch=name+'.patch',patchSha256=hashlib.sha256(patch).hexdigest())
with (root/'commands.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
print(json.dumps(record),flush=True)
print('\n'.join(data.decode(errors='replace').splitlines()[-12:]),flush=True)
sys.exit(r.returncode)
