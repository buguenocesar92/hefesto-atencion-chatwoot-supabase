#!/usr/bin/env python3
"""Respaldo del kit segun docs/CONTRATO-RESPALDO.md.

Salida: backups/<timestamp-UTC>/
  data.tar.gz   las piezas de datos (volcado de la base y archivos)
  SHA256SUMS    sha256 de data.tar.gz, en formato sha256sum
  manifest.json software, version, database, sha256, status + metadatos
  env.vars      SOLO los nombres de las variables del entorno
  env.age       el .env cifrado, solo si hay receptor age configurado
  COMPLETED     marca escrita al final: sin ella el respaldo no restaura

El .env NUNCA se copia en claro. Sin receptor age el respaldo sale sin el
.env y el manifiesto lo dice. No hay modo degradado a texto plano.
"""
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
os.umask(0o077)

KIT = json.loads((ROOT / 'scripts' / 'kit.json').read_text())


def dc(*args, **kw):
    return subprocess.run(['docker', 'compose', *args], check=True, **kw)


def sha256_de(ruta):
    digest = hashlib.sha256()
    with open(ruta, 'rb') as f:
        for bloque in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(bloque)
    return digest.hexdigest()


def nombres_del_env(ruta):
    """Solo los NOMBRES de las variables. Los valores no se leen."""
    nombres = []
    if not ruta.is_file():
        return nombres
    for linea in ruta.read_text().splitlines():
        linea = linea.strip()
        if not linea or linea.startswith('#') or '=' not in linea:
            continue
        clave = linea.partition('=')[0].strip()
        if clave.startswith('export '):
            clave = clave[len('export '):].strip()
        if clave and clave not in nombres:
            nombres.append(clave)
    return nombres


def main(argv):
    if len(argv) > 1 and argv[1] in ('-h', '--help'):
        print(__doc__)
        return 0
    env = ROOT / '.env'
    if not env.is_file():
        print('Falta .env: el respaldo se genera en el servidor, no en una copia de trabajo.',
              file=sys.stderr)
        return 1
    comanda = KIT.get('comandos', {})
    piezas = KIT.get('piezas', [])
    for servicio in KIT.get('requiere', []):
        if not dc('ps', '--status', 'running', '-q', servicio,
                  capture_output=True, text=True).stdout.strip():
            print('El servicio ' + servicio + ' no esta activo en este contexto.',
                  file=sys.stderr)
            return 1
    destino = ROOT / 'backups' / datetime.datetime.now(datetime.timezone.utc).strftime(
        '%Y%m%dT%H%M%S%fZ')
    destino.mkdir(parents=True, mode=0o700)
    arrancados = [s for s in KIT.get('arranca', [])
                  if dc('ps', '--status', 'running', '-q', s,
                        capture_output=True, text=True).stdout.strip()]
    try:
        with tempfile.TemporaryDirectory(prefix='hefesto-backup-') as tmp:
            escenario = Path(tmp)
            for paso in KIT.get('pasos', []):
                tipo = paso[0]
                if tipo == 'stop':
                    dc('stop', *paso[1:])
                elif tipo == 'cmd':
                    dc(*paso[1])
                elif tipo == 'pieza':
                    nombre = paso[1]
                    with (escenario / nombre).open('wb') as salida:
                        dc(*comanda[nombre], stdout=salida)
            datos = destino / 'data.tar.gz'
            with tarfile.open(datos, 'w:gz') as tf:
                for nombre in piezas:
                    tf.add(escenario / nombre, arcname=nombre)
        digest = sha256_de(datos)
        (destino / 'SHA256SUMS').write_text(digest + '  data.tar.gz\n')
        receptor = os.environ.get('AGE_RECIPIENTE', '').strip()
        cifrado = False
        if receptor:
            if not shutil.which('age'):
                print('AGE_RECIPIENTE esta configurado pero age no esta instalado.',
                      file=sys.stderr)
                return 5
            subprocess.run(['age', '-r', receptor, '-o', str(destino / 'env.age'), str(env)],
                           check=True)
            cifrado = True
        (destino / 'env.vars').write_text('\n'.join(nombres_del_env(env)) + '\n')
        manifiesto = {
            'software': KIT['software'],
            'version': KIT['version'],
            'database': KIT['database'],
            'sha256': digest,
            'status': 'completed',
            'piezas': {n: sha256_de(destino / 'data.tar.gz') for n in []},
            'env_encriptado': cifrado,
            'env_vars': True,
            'fecha': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
        }
        (destino / 'manifest.json').write_text(json.dumps(manifiesto, indent=2))
        (destino / 'COMPLETED').write_text('completed\n')
    finally:
        for servicio in arrancados:
            dc('start', servicio)
    print('Respaldo: ' + str(destino))
    print('Piezas: ' + ', '.join(piezas))
    print('El .env NO viaja en claro. Cifrar, copiar fuera del VPS y verificar con '
          'scripts/check_backup.py.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
