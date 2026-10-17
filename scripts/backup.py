#!/usr/bin/env python3
import os,datetime,subprocess,hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1];os.chdir(root);os.umask(0o077)
def dc(*args,**kw):return subprocess.run(['docker','compose',*args],check=True,**kw)
if not (root/'.env').is_file():raise SystemExit('Falta .env')
for service in ['web','worker','redis']:
    if not dc('ps','--status','running','-q',service,capture_output=True,text=True).stdout.strip():
        raise SystemExit('Se requiere web, worker y redis activos en el contexto Compose correcto')
folder=root/'backups'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');folder.mkdir(parents=True)
try:
    dc('stop','web','worker')
    with (folder/'public.dump').open('wb') as out:
        dc('run','--rm','--no-deps','-T','--entrypoint','pg_dump','dbtools','--format=custom','--schema=public','--no-owner','--no-acl',stdout=out)
    dc('exec','-T','redis','sh','-c','REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli SAVE')
    dc('stop','redis')
    with (folder/'redis.tar.gz').open('wb') as out:
        dc('run','--rm','--no-deps','-T','--entrypoint','tar','redis','-czf','-','-C','/data','.',stdout=out)
    with (folder/'storage.tar.gz').open('wb') as out:
        dc('run','--rm','--no-deps','-T','--entrypoint','tar','web','-czf','-','-C','/app/storage','.',stdout=out)
    for name in ['.env','compose.yaml']:(folder/name).write_bytes((root/name).read_bytes())
    hashes={}
    for name in ['public.dump','redis.tar.gz','storage.tar.gz','.env','compose.yaml']:
        with (folder/name).open('rb') as f:hashes[name]=hashlib.file_digest(f,'sha256').hexdigest()
    (folder/'manifest.json').write_text(json.dumps({'version':'4.18.0-ce','schema':'public','status':'completed','sha256':hashes},indent=2))
finally:
    dc('start','redis')
    dc('start','web','worker')
print(f'Respaldo: {folder}. Revisar estado, cifrar y copiar fuera del VPS.')
