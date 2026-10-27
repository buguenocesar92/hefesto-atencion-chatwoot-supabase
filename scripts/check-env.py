#!/usr/bin/env python3
"""Valida el entorno del kit segun docs/CONTRATO-RESPALDO.md.

  --modo ejemplo  (por defecto): valida .env.example. Exige que exista, que
                   no contenga ningun valor real y que cubra TODAS las
                   variables que el compose interpola (drift-check).
  --modo real: valida el .env real. Exige presencia, longitud minima de las
                   claves y coherencia entre banderas. NO imprime ningun
                   valor: solo nombre de variable, longitud y veredicto.

Codigos: 0 correcto, 1 uso incorrecto, 3 violacion del contrato.
"""
import json
import os
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]

# Formas que delatan un valor real pegado en el ejemplo.
PELIGROSAS = (
    re.compile(r'^sk[-_]'),
    re.compile(r'^re[-_]'),
    re.compile(r'^ghp_'),
    re.compile(r'^github_pat_'),
    re.compile(r'^xox[abprs]-'),
    re.compile(r'^AKIA[0-9A-Z]{16}$'),
    re.compile(r'^-----BEGIN'),
    re.compile(r'^eyJ[A-Za-z0-9_-]{10,}\.'),
    re.compile(r'^(postgres|postgresql)://[^:]*:[^@]*@'),
    re.compile(r'^[A-Za-z0-9+/]{40,}={0,2}$'),
)

# Marcadores admitidos en un .env.example (no son valores reales).
MARCADORES = (
    'GENERAR', 'CONFIGURAR', 'REEMPLAZAR', 'CAMBIAR', 'PENDIENTE',
    'EJEMPLO', 'PLACEHOLDER', 'X-O', 'TODO',
)

# Palabras que no pueden ser el valor de una clave sensible.
DEBILES = {
    'changeme', 'change_me', 'change-me', 'password', 'passwd', 'secret',
    'admin', 'root', '123456', '12345678', 'qwerty', 'example', 'test',
    'postgres', 'moodle', 'fider', 'listmonk', 'rallly', 'memos', 'shlink',
}


def leer_env(ruta):
    """Devuelve (diccionario, lista_de_nombres) sin tocar los valores en las
   variables que no se piden explicitamente."""
    datos = {}
    nombres = []
    if not ruta.is_file():
        return datos, nombres
    for linea in ruta.read_text().splitlines():
        linea = linea.strip()
        if not linea or linea.startswith('#'):
            continue
        if linea.startswith('export '):
            linea = linea[len('export '):].strip()
        if '=' not in linea:
            continue
        clave, _, valor = linea.partition('=')
        clave = clave.strip()
        valor = valor.strip().strip('"').strip("'")
        datos[clave] = valor
        nombres.append(clave)
    return datos, nombres


def variables_del_compose(raiz):
    """Todas las variables ${VAR...} que el compose interpola."""
    encontradas = set()
    for nombre in ('compose.yaml', 'compose.bootstrap.yaml', 'compose.yml'):
        ruta = raiz / nombre
        if not ruta.is_file():
            continue
        for match in re.finditer(r'\$\{([A-Za-z_][A-Za-z0-9_]*)', ruta.read_text()):
            encontradas.add(match.group(1))
    return encontradas


def es_marcador(valor):
    return any(m in valor.upper() for m in MARCADORES)


def modo_ejemplo(raiz, kit):
    errores = []
    ejemplo = raiz / '.env.example'
    if not ejemplo.is_file():
        print('Falta .env.example')
        return 3
    datos, nombres = leer_env(ejemplo)
    if not datos:
        errores.append('.env.example no declara ninguna variable')
    # Regla: ninguna variable del compose puede faltar en el ejemplo.
    exigidas = variables_del_compose(raiz)
    for var in sorted(exigidas):
        if var not in datos:
            errores.append('falta ' + var + ' (la usa el compose)')
    # Regla: ningun valor real en el ejemplo.
    for clave in sorted(datos):
        valor = datos[clave]
        if valor == '':
            continue
        if es_marcador(valor):
            continue
        for patron in PELIGROSAS:
            if patron.search(valor):
                errores.append('valor real en ' + clave + ' (no es un marcador)')
                break
        else:
            if valor.strip().lower() in DEBILES and clave in kit.get('env_secretas', []):
                errores.append('valor debil en ' + clave)
    # Las claves sensibles del kit deben existir y usar marcador.
    for clave in kit.get('env_secretas', []):
        if clave not in datos:
            errores.append('falta la clave sensible ' + clave)
            continue
        valor = datos[clave]
        if valor and not es_marcador(valor) and not valor.startswith('${'):
            errores.append('la clave sensible ' + clave + ' deberia usar un marcador')
    if errores:
        for e in errores:
            print('VIOLACION: ' + e)
        return 3
    print('.env.example cumple: cubre el compose y no contiene valores reales.')
    return 0


def modo_real(raiz, kit):
    errores = []
    real = raiz / '.env'
    if not real.is_file():
        print('VIOLACION: falta el .env real')
        return 3
    datos, nombres = leer_env(real)
    minimo = int(kit.get('env_min_len', 32))
    for clave in kit.get('env_requeridas', []):
        if clave not in datos:
            errores.append('falta ' + clave)
    for clave in kit.get('env_secretas', []):
        valor = datos.get(clave)
        if valor is None:
            continue
        if len(valor) < minimo:
            errores.append(clave + ' es demasiado corta (minimo ' + str(minimo) + ')')
    # Ninguna clave sensible puede valer lo mismo que otra.
    secretas = [c for c in kit.get('env_secretas', []) if c in datos]
    for i, a in enumerate(secretas):
        for b in secretas[i + 1:]:
            if datos[a] and datos[a] == datos[b]:
                errores.append(a + ' y ' + b + ' tienen el mismo valor')
    # SMTP_READY=true exige credenciales de correo.
    if datos.get('SMTP_READY', '').lower() == 'true':
        for clave in ('SMTP_HOST', 'SMTP_USERNAME', 'SMTP_PASSWORD'):
            if not datos.get(clave):
                errores.append('SMTP_READY=true pero falta ' + clave)
    # Coherencias especificas por kit.
    for regla in kit.get('env_reglas', []):
        nombre = regla.get('nombre')
        if nombre not in datos:
            continue
        valor = datos[nombre].strip()
        if regla.get('no_vacio') and not valor:
            errores.append(nombre + ' no puede estar vacia')
        if regla.get('sin_comodin') and ('*' in valor or valor == ''):
            errores.append(nombre + ' no admite comodines: el acceso debe ser nominal')
        if regla.get('sin_dominio') and '@' in valor:
            dominio = valor.rsplit('@', 1)[-1]
            if dominio in ('example.com', 'example.invalid', '*'):
                errores.append(nombre + ' no admite un patron de dominio')
        if regla.get('incluida_en'):
            lista = [x.strip() for x in datos.get(regla['incluida_en'], '').split(',') if x.strip()]
            if valor and valor not in lista:
                errores.append(nombre + ' debe estar incluida en ' + regla['incluida_en'])
    # Veredicto sin valores: solo nombre, longitud y estado.
    for clave in sorted(datos):
        if clave in kit.get('env_secretas', []):
            estado = 'ok' if len(datos[clave]) >= minimo else 'corta'
            print(clave + ': longitud=' + str(len(datos[clave])) + ' veredicto=' + estado)
    if errores:
        for e in errores:
            print('VIOLACION: ' + e)
        return 3
    print('.env real cumple el contrato. No se mostro ningun valor.')
    return 0


def main(argv):
    modo = 'ejemplo'
    args = list(argv[1:])
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == '--modo':
            if i + 1 >= len(args):
                print('Uso: python3 scripts/check-env.py [--modo ejemplo|--modo real]',
                      file=sys.stderr)
                return 1
            modo = args[i + 1]
            i += 2
            continue
        if arg in ('--modo ejemplo', '--modo real'):
            modo = arg.split(' ', 1)[1]
            i += 1
            continue
        print('Uso: python3 scripts/check-env.py [--modo ejemplo|--modo real]', file=sys.stderr)
        return 1
    if modo not in ('ejemplo', 'real'):
        print('Uso: python3 scripts/check-env.py [--modo ejemplo|--modo real]', file=sys.stderr)
        return 1
    kit = json.loads((RAIZ / 'scripts' / 'kit.json').read_text())
    if modo == 'real':
        return modo_real(RAIZ, kit)
    return modo_ejemplo(RAIZ, kit)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
