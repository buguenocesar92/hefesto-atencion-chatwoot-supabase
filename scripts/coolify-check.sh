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

# Overrides opcionales (solo para probar el propio chequeo):
#   bash scripts/coolify-check.sh /tmp/x/override.yaml
compose_args=(-f "$compose")
for extra in "$@"; do
  [[ -f "$extra" ]] || { echo "ERROR: no existe $extra" >&2; exit 2; }
  compose_args+=(-f "$extra")
done

tmp_env="$(mktemp)"
err="$(mktemp)"
trap 'rm -f "$tmp_env" "$err"' EXIT

# .env temporal con valores ficticios no secretos (nadie los va a leer;
# solo necesitamos que docker compose config renderice). Las variables
# se extraen del compose para no olvidarse de las obligatorias con :?
# (p.ej. COMPOSE_PROJECT_NAME, STORAGE_VOLUME, REDIS_VOLUME).
: > "$tmp_env"
while IFS= read -r var; do
  [[ -z "$var" ]] && continue
  if [[ "$var" == *HOST* || "$var" == *URL* ]]; then
    val="https://ejemplo.invalid"
  else
    val="x123abc"
  fi
  printf '%s=%s\n' "$var" "$val" >> "$tmp_env"
done < <(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*' "$compose" | sed 's/^\${//' | sort -u)

# Supabase compartido: DB_NAME/DB_SSLMODE deben verse en el render del
# servicio web (contrato punto 3).
printf 'DB_SSLMODE=disable\nDB_NAME=mvp_prueba\n' >> "$tmp_env"

# docker compose config debe renderizar sin error. stderr (warnings del
# daemon, p.ej. ~/.docker/config.json) no debe contaminar el JSON.
if ! render_json="$(docker compose --project-directory "$repo_root" "${compose_args[@]}" --env-file "$tmp_env" config --format json 2>"$err")"; then
  echo "compose no se pudo renderizar:" >&2
  cat "$err" >&2
  exit 1
fi

# Para el punto 2 (nombres explícitos en el YAML), --no-normalize deja
# los name: declarados como strings y los calculados por Compose como null.
if ! raw_json="$(docker compose --project-directory "$repo_root" "${compose_args[@]}" --env-file "$tmp_env" config --format json --no-normalize 2>"$err")"; then
  echo "compose no se pudo renderizar (--no-normalize):" >&2
  cat "$err" >&2
  exit 1
fi

fail=0

# Punto 1 del contrato: para cada servicio sin profiles no debe haber nada
# que se salte Traefik ni dé poder sobre el host.
for svc in $(printf '%s' "$render_json" | jq -r '.services | keys[]'); do
  profiles_len=$(printf '%s' "$render_json" | jq -r ".services[\"$svc\"].profiles // [] | length")
  [[ "$profiles_len" != "0" ]] && continue
  j=".services[\"$svc\"]"
  msg=""
  # Binds del servicio. El filtro va entre comillas simples y recibe el
  # servicio con --arg: NO interpolar variables de shell dentro del filtro.
  # Sin 2>/dev/null: si jq falla, set -e corta el script.
  bind_msg=$(printf '%s' "$render_json" | jq -r --arg svc "$svc" --arg repo_root "$repo_root" '
    [(.services[$svc].volumes // [])[]
      | select(type == "object" and .type == "bind")
      | .source
      | select(. != null)
      | select(contains("docker.sock") or (. != $repo_root and (startswith($repo_root + "/") | not)))
    ] | .[0] // empty
  ')
  if printf '%s' "$render_json" | jq -e "($j.ports // []) | length > 0" >/dev/null 2>&1; then
    msg="$svc: expone ports (Traefik debe enrutar el dominio)"
  elif printf '%s' "$render_json" | jq -e "$j.container_name != null" >/dev/null 2>&1; then
    msg="$svc: usa container_name fijo"
  elif printf '%s' "$render_json" | jq -e "$j.privileged == true" >/dev/null 2>&1; then
    msg="$svc: privileged=true"
  elif printf '%s' "$render_json" | jq -e "(($j.cap_add // []) | length > 0) or (($j.devices // []) | length > 0)" >/dev/null 2>&1; then
    msg="$svc: cap_add o devices activos"
  elif printf '%s' "$render_json" | jq -e "$j.network_mode == \"host\" or $j.pid == \"host\" or $j.ipc == \"host\"" >/dev/null 2>&1; then
    msg="$svc: network_mode/pid/ipc=host"
  elif printf '%s' "$render_json" | jq -e "($j.security_opt // []) | any(.[]; test(\"unconfined\"))" >/dev/null 2>&1; then
    msg="$svc: security_opt unconfined"
  elif [[ -n "$bind_msg" ]]; then
    if [[ "$bind_msg" == *docker.sock* ]]; then
      msg="$svc: monta docker.sock"
    else
      msg="$svc: bind fuera del repo $bind_msg"
    fi
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

# supabase-pg: DB_NAME y DB_SSLMODE del .env deben verse en el servicio web
# (DSN via POSTGRES_DATABASE/PGSSLMODE), no basta con que aparezcan en cualquier
# parte del render.
if ! printf '%s' "$render_json" | jq -e '.services.web.environment.POSTGRES_DATABASE == "mvp_prueba" and .services.web.environment.PGSSLMODE == "disable"' >/dev/null 2>&1; then
  echo "web: DB_NAME/DB_SSLMODE no propagados"; fail=1
fi

if [[ $fail -ne 0 ]]; then
  exit 1
fi

echo "coolify-check OK"