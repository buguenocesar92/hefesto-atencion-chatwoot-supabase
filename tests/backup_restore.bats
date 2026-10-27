#!/usr/bin/env bats
# Ciclo de respaldo -> verificacion -> restauracion con datos SINTETICOS.
# Nunca toca el daemon de Docker ni una base real.

load ayudante

setup() {
  TMP_REPO="$(mktemp -d)"
  repo_temporal "$TMP_REPO" >/dev/null
  TMP_REPO="$(cd "$TMP_REPO" && pwd)"
}

teardown() {
  if [ -n "${TMP_REPO:-}" ] && [ -d "$TMP_REPO" ]; then
    chmod -R u+w "$TMP_REPO" 2>/dev/null
    rm -rf "$TMP_REPO"
  fi
}

@test "backup produce data.tar.gz, SHA256SUMS, manifest y marca COMPLETED" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  [ -f "$dir/data.tar.gz" ]
  [ -f "$dir/SHA256SUMS" ]
  [ -f "$dir/manifest.json" ]
  [ -f "$dir/COMPLETED" ]
  [ -f "$dir/env.vars" ]
  run python3 -c "import json,sys;m=json.load(open(sys.argv[1]));sys.exit(0 if all(k in m for k in ('software','version','database','sha256','status')) and m['status']=='completed' else 1)" "$dir/manifest.json"
  [ "$status" -eq 0 ]
}

@test "el manifiesto declara las variables sin sus valores" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  run grep -F "clave-sintetica-de-prueba" "$dir/env.vars"
  [ "$status" -ne 0 ]
  run grep -F "POSTGRES_PASSWORD" "$dir/env.vars"
  [ "$status" -eq 0 ]
}

@test "el .env no queda en claro dentro del respaldo" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  run grep -rF "clave-sintetica-de-prueba" "$dir"
  [ "$status" -ne 0 ]
  run bash -c "tar -tzf '$dir/data.tar.gz' | grep -E '(^|/)\.env$'"
  [ "$status" -ne 0 ]
}

@test "check_backup.py acepta un respaldo integro" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  run python3 "$TMP_REPO/scripts/check_backup.py" "$dir"
  [ "$status" -eq 0 ]
}

@test "check_backup.py rechaza un hash alterado con codigo 2" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  printf 'X' >> "$dir/data.tar.gz"
  run python3 "$TMP_REPO/scripts/check_backup.py" "$dir"
  [ "$status" -eq 2 ]
}

@test "check_backup.py rechaza un secreto en claro con codigo 4" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  cp "$TMP_REPO/.env" "$dir/.env"
  run python3 "$TMP_REPO/scripts/check_backup.py" "$dir"
  [ "$status" -eq 4 ]
}

@test "check_backup.py rechaza un manifiesto sin las cinco claves" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  python3 - "$dir/manifest.json" <<'PYEOF'
import json,sys
ruta=sys.argv[1]
m=json.load(open(ruta))
m.pop('database',None)
json.dump(m,open(ruta,'w'))
PYEOF
  run python3 "$TMP_REPO/scripts/check_backup.py" "$dir"
  [ "$status" -eq 2 ]
}

@test "restore_db.py en modo ensayo no escribe nada y sale 0" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  antes="$(ls -1 "$TMP_REPO" | sort | tr '\n' ' ')"
  run python3 "$TMP_REPO/scripts/restore_db.py" "$dir" --dry-run
  [ "$status" -eq 0 ]
  despues="$(ls -1 "$TMP_REPO" | sort | tr '\n' ' ')"
  [ "$antes" = "$despues" ]
  [ ! -f "$TMP_REPO/restore-report.json" ]
}

@test "restore_db.py sin --confirmar no escribe nada" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  dir="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  run python3 "$TMP_REPO/scripts/restore_db.py" "$dir"
  [ "$status" -ne 0 ]
  [ ! -f "$TMP_REPO/restore-report.json" ]
}

@test "el ciclo de respaldo es idempotente: dos corridas no se pisan" {
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  primero="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  run bash -c "cd '$TMP_REPO' && python3 scripts/backup.py"
  [ "$status" -eq 0 ]
  segundo="$(find "$TMP_REPO/backups" -mindepth 1 -maxdepth 1 -type d | sort -r | sed -n 1p)"
  [ "$primero" != "$segundo" ]
  run python3 "$TMP_REPO/scripts/check_backup.py" "$segundo"
  [ "$status" -eq 0 ]
}
