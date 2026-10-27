#!/usr/bin/env bash
# Sonda de salud SOLO LECTURA del kit hefesto-atencion.
# No reinicia, no modifica, no imprime valores de secretos.
# Codigos: 0 sano, 1 no sano, 2 no desplegado (o docker no disponible).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

SERVICIO="web"
URL_PUBLICA="https://atencion.tu-dominio.cl"

err=0

if ! command -v docker >/dev/null 2>&1; then
  echo "docker no esta disponible en esta maquina"
  exit 2
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose no esta disponible"
  exit 2
fi

if [ ! -f .env ]; then
  echo "No hay .env: el kit no esta desplegado en este contexto"
  exit 2
fi

ids="$(docker compose ps --status running -q "$SERVICIO" 2>/dev/null)"
if [ -z "$ids" ]; then
  echo "El servicio $SERVICIO no esta corriendo"
  exit 1
fi

salud="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$ids" 2>/dev/null | head -1)"
if [ -z "$salud" ]; then
  echo "No se pudo consultar el estado de $SERVICIO"
  exit 1
fi
if [ "$salud" != "healthy" ] && [ "$salud" != "running" ]; then
  echo "El servicio $SERVICIO esta en estado $salud"
  err=1
else
  echo "El servicio $SERVICIO esta en estado $salud"
fi

if [ -n "$URL_PUBLICA" ]; then
  codigo="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 10 "$URL_PUBLICA" 2>/dev/null)"
  if [ "$codigo" = "200" ]; then
    echo "El endpoint publico responde 200"
  else
    echo "El endpoint publico no responde 200 (codigo: ${codigo:-sin respuesta})"
    err=1
  fi
else
  echo "Sin URL publica configurada: no se sondea el endpoint externo"
fi

exit "$err"
