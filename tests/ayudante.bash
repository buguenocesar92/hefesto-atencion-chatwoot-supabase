#!/usr/bin/env bash
# Ayuda comun de la suite del kit.
# Aislamiento total: el daemon de Docker se sustituye por tests/stubs/docker
# y el .env es sintetico. Ninguna prueba toca una base ni un volumen real.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
export RAIZ
export PATH="$RAIZ/tests/stubs:$PATH"

# Variable de entorno sintetica: NUNCA contiene valores reales.
genera_env_sintetico() {
  local destino="$1"
  cat > "$destino" <<'ENVEOF'
COMPOSE_PROJECT_NAME=hefesto-kit-prueba
PUBLIC_URL=https://prueba.example.invalid
APP_URL=https://prueba.example.invalid
APP_HOST=prueba.example.invalid
POSTGRES_HOST=db.prueba.example.invalid
POSTGRES_USERNAME=rol_app_prueba
POSTGRES_PASSWORD=clave-sintetica-de-prueba-0000000000000000
DB_HOST=db.prueba.example.invalid
DB_NAME=postgres
DB_USER=rol_app_prueba
DB_PASSWORD=clave-sintetica-de-prueba-0000000000000000
DB_SSLMODE=require
JWT_SECRET=secreto-sintetico-de-prueba-0000000000000000
SECRET_PASSWORD=secreto-sintetico-de-prueba-0000000000000000
REDIS_PASSWORD=secreto-sintetico-de-prueba-0000000000000000
SECRET_KEY_BASE=secreto-sintetico-de-prueba-0000000000000000
MB_ENCRYPTION_SECRET_KEY=secreto-sintetico-de-prueba-0000000000000000
ADMIN_PASSWORD=secreto-sintetico-de-prueba-0000000000000000
INITIAL_ADMIN_EMAIL=admin@example.invalid
ALLOWED_EMAILS=operador@example.invalid
SUPPORT_EMAIL=soporte@example.invalid
NOREPLY_EMAIL=no-reply@example.invalid
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
SMTP_READY=false
SMTP_HOST=
SMTP_USERNAME=
SMTP_PASSWORD=
INITIAL_SETUP_COMPLETE=false
ENVEOF
}

# Copia lo minimo del kit a un arbol temporal con un .env sintetico.
repo_temporal() {
  local destino="$1"
  mkdir -p "$destino/scripts" "$destino/tests"
  copia_si_existe() {
    if [ -e "$1" ]; then cp -R "$1" "$2"; fi
  }
  copia_si_existe "$RAIZ/scripts/." "$destino/scripts/"
  copia_si_existe "$RAIZ/ops" "$destino/ops"
  copia_si_existe "$RAIZ/certs" "$destino/certs"
  copia_si_existe "$RAIZ/compose.yaml" "$destino/compose.yaml"
  copia_si_existe "$RAIZ/compose.bootstrap.yaml" "$destino/compose.bootstrap.yaml"
  copia_si_existe "$RAIZ/.env.example" "$destino/.env.example"
  genera_env_sintetico "$destino/.env"
  printf '%s\n' "$destino"
}

# Respaldo sintetico completo, sin tocar Docker ni ninguna base.
respaldo_sintetico() {
  local raiz="$1"
  local salida="$2"
  ( cd "$raiz" && python3 scripts/backup.py ) >/dev/null || return 1
  local mas_reciente
  mapfile -t respaldos < <(find "$raiz/backups" -mindepth 1 -maxdepth 1 -type d | sort -r)
  mas_reciente="${respaldos[0]:-}"
  [ -n "$mas_reciente" ] || return 1
  if [ -n "$salida" ]; then
    cp -R "$mas_reciente" "$salida"
    printf '%s\n' "$salida"
  else
    printf '%s\n' "$mas_reciente"
  fi
}
