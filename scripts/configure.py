#!/usr/bin/env python3
import os,re,secrets,sys
from pathlib import Path
if len(sys.argv)!=3 or not re.fullmatch(r'[a-z][a-z0-9-]{2,39}',sys.argv[1]) or not re.fullmatch(r'(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}',sys.argv[2]):
    raise SystemExit('Uso: python3 scripts/configure.py cliente-demo atencion.tudominio.cl')
root=Path(__file__).resolve().parents[1];slug=sys.argv[1]
values={'COMPOSE_PROJECT_NAME':f'hefesto-atencion-{slug}','STORAGE_VOLUME':f'hefesto-atencion-{slug}-files','REDIS_VOLUME':f'hefesto-atencion-{slug}-redis','CHAT_HOST':sys.argv[2],'SECRET_KEY_BASE':secrets.token_hex(64),'REDIS_PASSWORD':secrets.token_hex(32),'POSTGRES_HOST':'CONFIGURAR','POSTGRES_USERNAME':'chatwoot_app','POSTGRES_PASSWORD':'CONFIGURAR','SUPABASE_DEDICATED_CONFIRMED':'false','SUPABASE_DATA_API_DISABLED':'false'}
try:fd=os.open(root/'.env',os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
except FileExistsError:raise SystemExit('.env ya existe; no se modifico.')
with os.fdopen(fd,'w') as f:
    for k,v in values.items():f.write(f'{k}={v}\n')
print('.env creado: completar conexion Supabase y SMTP. No mostrar ni subir sus secretos.')
