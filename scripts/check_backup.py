#!/usr/bin/env python3
"""Verificador de respaldos segun docs/CONTRATO-RESPALDO.md.

Codigos de salida:
  0  respaldo integro
  1  uso incorrecto
  2  manifiesto inconsistente, hash alterado, marca COMPLETED ausente o
     ruta no admitida dentro del tar
  4  hay un secreto en claro dentro del respaldo

No imprime ningun valor de secreto: solo nombres de archivo y motivos.
"""
import hashlib
import json
import os
import re
import sys
import tarfile
from pathlib import Path

CLAVES = ('software', 'version', 'database', 'sha256', 'status')
SECRETOS = (
    re.compile(r'(^|/)\.env$'),
    re.compile(r'(^|/)[^/]*\.env$'),
    re.compile(r'(^|/)[^/]*\.(pem|key|p12|pfx)$'),
    re.compile(r'(^|/)id_rsa$'),
)


def es_secreto(nombre):
    """True si el nombre del archivo corresponde a un secreto sin cifrar."""
    return any(p.search(nombre) for p in SECRETOS) and not nombre.endswith('.age')


def salir(codigo, mensaje):
    print(mensaje, file=sys.stderr)
    sys.exit(codigo)


def sha256_de(ruta):
    digest = hashlib.sha256()
    with open(ruta, 'rb') as f:
        for bloque in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(bloque)
    return digest.hexdigest()


def valida_tar(ruta_tar):
    """Regla 6: nada absoluto, nada con .., solo archivos y directorios."""
    with tarfile.open(ruta_tar, 'r:gz') as tf:
        for miembro in tf:
            nombre = miembro.name
            if nombre.startswith('/') or os.path.isabs(nombre):
                salir(2, 'Ruta no admitida (absoluta): ' + nombre)
            partes = Path(nombre).parts
            if '..' in partes:
                salir(2, 'Ruta no admitida (salto): ' + nombre)
            if not (miembro.isfile() or miembro.isdir()):
                salir(2, 'Tipo de entrada no admitido: ' + nombre)
            if es_secreto(nombre):
                salir(4, 'Secreto en claro dentro del respaldo: ' + nombre)


def verifica(ruta, software_esperado=None):
    src = Path(ruta).resolve()
    if not src.is_dir():
        salir(1, 'No existe el directorio de respaldo: ' + str(src))
    manifiesto = src / 'manifest.json'
    if not manifiesto.is_file():
        salir(2, 'Falta manifest.json')
    try:
        m = json.loads(manifiesto.read_text())
    except ValueError:
        salir(2, 'manifest.json no es JSON valido')
    if not isinstance(m, dict):
        salir(2, 'manifest.json no es un objeto')
    for clave in CLAVES:
        if clave not in m:
            salir(2, 'manifest.json sin la clave obligatoria: ' + clave)
    if m.get('status') != 'completed':
        salir(2, 'El respaldo no esta completo (status=' + str(m.get('status')) + ')')
    if not isinstance(m.get('sha256'), str) or len(m['sha256']) != 64:
        salir(2, 'manifest.json con sha256 invalido')
    if software_esperado and m.get('software') != software_esperado:
        salir(2, 'Producto incorrecto: ' + str(m.get('software')))
    marca = src / 'COMPLETED'
    if not marca.is_file():
        salir(2, 'Falta la marca COMPLETED: el respaldo no termino')
    datos = src / 'data.tar.gz'
    if not datos.is_file():
        salir(2, 'Falta data.tar.gz')
    digest = sha256_de(datos)
    if digest != m['sha256']:
        salir(2, 'Checksum incorrecto: data.tar.gz')
    sumas = src / 'SHA256SUMS'
    if not sumas.is_file():
        salir(2, 'Falta SHA256SUMS')
    lineas = [l.strip() for l in sumas.read_text().splitlines() if l.strip()]
    esperado = digest + '  data.tar.gz'
    if esperado not in lineas:
        salir(2, 'SHA256SUMS no coincide con data.tar.gz')
    valida_tar(datos)
    # Regla 5: el .env nunca viaja en claro. Ni en la raiz ni dentro del tar.
    for hijo in sorted(src.rglob('*')):
        if hijo.is_file() and es_secreto(hijo.relative_to(src).as_posix()):
            salir(4, 'Secreto en claro dentro del respaldo: ' + hijo.relative_to(src).as_posix())
    return src


def main(argv):
    if len(argv) < 2 or len(argv) > 4:
        print('Uso: python3 scripts/check_backup.py /ruta/respaldo [--software NOMBRE]',
              file=sys.stderr)
        return 1
    esperado = None
    if len(argv) == 4:
        if argv[2] != '--software':
            print('Uso: python3 scripts/check_backup.py /ruta/respaldo [--software NOMBRE]',
                  file=sys.stderr)
            return 1
        esperado = argv[3]
    verifica(argv[1], esperado)
    print('Respaldo integro: manifiesto, checksum, rutas y ausencia de secretos en claro.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
