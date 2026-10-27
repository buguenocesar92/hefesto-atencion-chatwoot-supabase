#!/usr/bin/env python3
"""Restaura el respaldo del kit hefesto-atencion.

Uso:
  python3 scripts/restore_db.py <respaldo> --dry-run
  python3 scripts/restore_db.py <respaldo> --confirmar CONFIRMAR_RESTAURACION 

--dry-run valida el respaldo con scripts/check_backup.py y muestra el plan
sin escribir nada. --confirmar CONFIRMAR_RESTAURACION es obligatorio para
actuar: sin esa cadena exacta se imprime el plan y se sale con 1 sin tocar el
destino. Cada restauracion deja restore-report.json y una linea de auditoria
en logs/restore-audit.log, sin valores de secretos.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
KIT = json.loads((ROOT / 'scripts' / 'kit.json').read_text())
TOKEN = 'CONFIRMAR_RESTAURACION'


def dc(*args, **kw):
    return subprocess.run(['docker', 'compose', *args], check=True, **kw)


def verifica(respaldo):
    verificador = ROOT / 'scripts' / 'check_backup.py'
    proc = subprocess.run([sys.executable, str(verificador), str(respaldo),
                           '--software', KIT['software']], capture_output=True, text=True)
    if proc.returncode != 0:
        print((proc.stderr or proc.stdout).strip(), file=sys.stderr)
        sys.exit(proc.returncode or 2)
    return Path(respaldo).resolve()


def extrae(respaldo, destino):
    """Extrae las piezas de data.tar.gz. Las rutas ya fueron validadas."""
    with tarfile.open(respaldo / 'data.tar.gz', 'r:gz') as tf:
        for miembro in tf.getmembers():
            if miembro.isfile():
                tf.extract(miembro, destino)
    return destino


def muestra_plan(respaldo, piezas):
    print('Plan de restauracion (no se ejecuta nada):')
    print('  origen   : ' + str(respaldo))
    print('  software : ' + KIT['software'] + ' ' + KIT['version'])
    print('  base     : ' + KIT['database'])
    print('  piezas   : ' + ', '.join(sorted(piezas)))
    print('  destino  : ' + str(ROOT))
    print('  exige    : --confirmar ' + TOKEN)


def auditoria(origen, sha, resultado, detalle=None):
    logs = ROOT / 'logs'
    logs.mkdir(parents=True, exist_ok=True)
    os.chmod(logs, 0o700)
    registro = {
        'fecha': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
        'origen': str(origen),
        'sha256': sha,
        'destino': str(ROOT),
        'resultado': resultado,
    }
    if detalle:
        registro['detalle'] = str(detalle)[:400]
    ruta = logs / 'restore-audit.log'
    with open(ruta, 'a', encoding='utf-8') as f:
        f.write(json.dumps(registro) + '\n')
    os.chmod(ruta, 0o600)


def reporte(origen, sha, resultado, detalle=None):
    datos = {
        'fecha': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
        'origen': str(origen),
        'sha256': sha,
        'destino': str(ROOT),
        'software': KIT['software'],
        'version': KIT['version'],
        'resultado': resultado,
    }
    if detalle:
        datos['detalle'] = str(detalle)[:400]
    (ROOT / 'restore-report.json').write_text(json.dumps(datos, indent=2))


def restaurar(destino, extras):
    """Cuerpo especifico del kit. `destino` contiene las piezas extraidas."""
    dump = destino / 'public.dump'
    if not dump.is_file():
        raise SystemExit('El respaldo no contiene el volcado de la base')
    for servicio in ['web', 'worker']:
        if dc('ps', '--status', 'running', '-q', servicio,
              capture_output=True, text=True).stdout.strip():
            raise SystemExit('Detener ' + servicio + ' antes de restaurar en destino nuevo')
    cuenta = dc('run', '--rm', '--no-deps', '-T', '--entrypoint', 'psql', 'dbtools',
                '-Atc', "SELECT count(*) FROM pg_tables WHERE schemaname='public'",
                capture_output=True, text=True).stdout.strip()
    if cuenta != '0':
        raise SystemExit('El esquema public no esta vacio: no se sobrescribiran datos')
    with dump.open('rb') as flujo:
        toc = dc('run', '--rm', '--no-deps', '-T', '--entrypoint', 'pg_restore', 'dbtools',
                 '--list', stdin=flujo, stdout=subprocess.PIPE).stdout.decode()
    # public ya existe en Supabase: no se dropea ni se restaura su SCHEMA.
    lineas = [l for l in toc.splitlines()
              if not re.match(r'^\d+;\s+\d+\s+\d+\s+SCHEMA\s+-\s+public(?:\s|$)', l)]

    with tempfile.TemporaryDirectory(prefix='hefesto-restore-') as d:
        lista = Path(d) / 'restore.list'
        lista.write_text('\n'.join(lineas) + '\n')
        os.chmod(d, 0o755)
        os.chmod(lista, 0o644)
        with dump.open('rb') as flujo:
            dc('run', '--rm', '--no-deps', '-T', '-v', d + ':/restore:ro',
               '--entrypoint', 'sh', 'dbtools', '-c exec pg_restore --exit-on-error --no-owner --no-acl --use-list=/restore/restore.list --dbname="$PGDATABASE"',
               '--use-list=/restore/restore.list', '--dbname=postgres', stdin=flujo)

    return 'piezas restauradas: ' + ', '.join(sorted(p.name for p in destino.iterdir()))


def main(argv=None):
    ap = argparse.ArgumentParser(description='Restaura el respaldo del kit ' + KIT['software'])
    ap.add_argument('respaldo', help='directorio del respaldo')
    ap.add_argument('--dry-run', action='store_true',
                    help='valida el respaldo y muestra el plan sin escribir nada')
    ap.add_argument('--confirmar', metavar=TOKEN,
                    help='token exacto exigido para ejecutar la restauracion')
    args, extras = ap.parse_known_args(argv)
    respaldo = verifica(args.respaldo)
    sha = hashlib.sha256((respaldo / 'data.tar.gz').read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='hefesto-restore-') as tmp:
        destino = extrae(respaldo, Path(tmp))
        muestra_plan(respaldo, [p.name for p in Path(tmp).iterdir()])
        if args.dry_run:
            print('Modo ensayo: no se escribio nada.')
            return 0
        if args.confirmar != TOKEN:
            print('Falta --confirmar ' + TOKEN + ': no se escribio nada.', file=sys.stderr)
            return 1
        try:
            detalle = restaurar(destino, extras)
        except Exception as exc:
            auditoria(respaldo, sha, 'error', exc)
            reporte(respaldo, sha, 'error', exc)
            raise
    auditoria(respaldo, sha, 'ok', detalle)
    reporte(respaldo, sha, 'ok', detalle)
    print('Restauracion completada. Informe en restore-report.json.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
