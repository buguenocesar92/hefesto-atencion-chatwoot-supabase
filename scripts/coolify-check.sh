#!/usr/bin/env bash
# Verifica que compose.yaml cumple el contrato de Coolify para este repo.
# - Servicios sin profiles: nada que se salte Traefik ni dé poder sobre el host.
# - Supabase compartido: DB_NAME (default mvp_prueba) y DB_SSLMODE aparecen
#   en el render cuando se pasan por .env.
#
# Salida 0 si pasa; en cada falla imprime "<servicio|seccion>: <motivo>"
# y termina con exit 1.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compose="$repo_root/compose.yaml"

[[ -f "$compose" ]] || { echo "ERROR: no existe $compose" >&2; exit 2; }

tmp_env="$(mktemp)"
trap 'rm -f "$tmp_env"' EXIT

# .env temporal con valores ficticios no secretos (nadie los va a leer;
# solo necesitamos que docker compose config renderice). Para supabase-pg
# se agregan DB_SSLMODE y DB_NAME del contrato.
cat > "$tmp_env" <<'EOF'
CHAT_HOST=ejemplo.invalid
SECRET_KEY_BASE=x12345abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123
POSTGRES_HOST=db.ejemplo.invalid
POSTGRES_USERNAME=chatwoot_app
POSTGRES_PASSWORD=x12345abcde
SUPABASE_DEDICATED_CONFIRMED=true
SUPABASE_DATA_API_DISABLED=true
MAILER_SENDER_EMAIL=soporte@ejemplo.invalid
SMTP_DOMAIN=ejemplo.invalid
SMTP_ADDRESS=smtp.ejemplo.invalid
SMTP_PORT=587
SMTP_USERNAME=x12345
SMTP_PASSWORD=x12345abcde
SMTP_AUTHENTICATION=plain
REDIS_PASSWORD=x12345abcdef0123456789abcdef01
DB_SSLMODE=disable
DB_NAME=mvp_prueba
EOF

# docker compose config debe renderizar sin error. stderr (warnings del
# daemon, p.ej. ~/.docker/config.json) no debe contaminar el JSON.
if ! render_json="$(docker compose --project-directory "$repo_root" -f "$compose" --env-file "$tmp_env" config --format json 2>render.err)"; then
  echo "compose no se pudo renderizar:" >&2
  cat render.err >&2
  rm -f render.err
  exit 1
fi
rm -f render.err

# Para el punto 2 (nombres explícitos en el YAML), --no-normalize deja
# los name: declarados como strings y los calculados por Compose como null.
if ! raw_json="$(docker compose --project-directory "$repo_root" -f "$compose" --env-file "$tmp_env" config --format json --no-normalize 2>render.err)"; then
  echo "compose no se pudo renderizar (--no-normalize):" >&2
  cat render.err >&2
  rm -f render.err
  exit 1
fi
rm -f render.err

fail=0

# Punto 1 del contrato: para cada servicio sin profiles no debe haber nada
# que se salte Traefik ni dé poder sobre el host.
for svc in $(printf '%s' "$render_json" | jq -r '.services | keys[]'); do
  profiles_len=$(printf '%s' "$render_json" | jq -r ".services[\"$svc\"].profiles // [] | length")
  [[ "$profiles_len" != "0" ]] && continue
  j=".services[\"$svc\"]"
  msg=""
  if printf '%s' "$render_json" | jq -e "($j.ports // []) | length > 0" >/dev/null 2>&1; then
    msg="$svc: expone ports (Traefik debe enrutar el dominio)"
  elif printf '%s' "$render_json" | jq -e "$j.container_name != null" >/dev/null 2>&1; then
    msg="$svc: usa container_name fijo"
  elif printf '%s' "$render_json" | jq -e "$j.privileged == true" >/dev/null 2>&1; then
    msg="$svc: privileged=true"
  elif printf '%s' "$render_json" | jq -e "($j.cap_add // []) | length > 0 or ($j.devices // []) | length > 0" >/dev/null 2>&1; then
    msg="$svc: cap_add o devices activos"
  elif printf '%s' "$render_json" | jq -e "$j.network_mode == \"host\" or $j.pid == \"host\" or $j.ipc == \"host\"" >/dev/null 2>&1; then
    msg="$svc: network_mode/pid/ipc=host"
  elif printf '%s' "$render_json" | jq -e "($j.security_opt // []) | any(. == \"seccomp=unconfined\" or . == \"apparmor=unconfined\")" >/dev/null 2>&1; then
    msg="$svc: security_opt unconfined"
  elif printf '%s' "$render_json" | jq -e "[$j.volumes // [] | .[] | select(type==\"string\")] | map(select(test(\"docker.sock\"))) | length > 0" >/dev/null 2>&1; then
    msg="$svc: monta docker.sock"
  fi
  if [[ -n "$msg" ]]; then
    echo "$msg"
    fail=1
  fi
done

# Punto 2 del contrato: nombres estables sin forzar. Se verifica contra el
# render sin normalizar: si el YAML declara name: queda como string; si no,
# Compose lo deja null.
# - raiz: el render sin normalizar siempre calcula un nombre (del dir o
#   de COMPOSE_PROJECT_NAME); revisamos el YAML para detectar la declaración.
if grep -qE '^name:' "$compose"; then
  echo "raiz: usa name fijo (Coolify pone el nombre de proyecto)"; fail=1
fi
for net in $(printf '%s' "$raw_json" | jq -r '.networks | keys[]'); do
  if printf '%s' "$raw_json" | jq -e ".networks[\"$net\"].name != null" >/dev/null 2>&1; then
    echo "red $net: name fijo (Coolify pone el nombre de proyecto)"; fail=1
  fi
done
for vol in $(printf '%s' "$raw_json" | jq -r '.volumes | keys[]'); do
  vname=$(printf '%s' "$raw_json" | jq -r ".volumes[\"$vol\"].name // empty")
  if [[ -n "$vname" ]]; then
    echo "volumen $vol: name fijo '$vname'"; fail=1
  fi
done

# supabase-pg: DB_NAME y DB_SSLMODE del .env deben verse en el render
# (DSN o env del servicio web).
if ! printf '%s' "$render_json" | grep -q 'mvp_prueba'; then
  echo "Falta DB_NAME=mvp_prueba en el render (DSN o env del servicio web)"; fail=1
fi
if ! printf '%s' "$render_json" | grep -q 'disable'; then
  echo "Falta DB_SSLMODE=disable en el render (DSN o env del servicio web)"; fail=1
fi

if [[ $fail -ne 0 ]]; then
  exit 1
fi

echo "coolify-check OK"