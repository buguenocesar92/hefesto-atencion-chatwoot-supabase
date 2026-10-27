#!/usr/bin/env bats
# El .env.example es el contrato auditable de variables del kit.

load ayudante

@test "existe .env.example" {
  [ -f "$RAIZ/.env.example" ]
}

@test "todo placeholder del compose aparece en .env.example" {
  for var in $(grep -hoE '\$\{[A-Z_0-9]+' "$RAIZ/compose.yaml" "$RAIZ/compose.bootstrap.yaml" 2>/dev/null | sed 's/\${//' | sort -u); do
    run grep -qE "^${var}=" "$RAIZ/.env.example"
    [ "$status" -eq 0 ] || { echo "Falta $var en .env.example"; return 1; }
  done
}

@test "check-env.py en modo ejemplo aprueba el .env.example" {
  run python3 "$RAIZ/scripts/check-env.py" --modo ejemplo
  [ "$status" -eq 0 ]
}

@test "ningun valor del ejemplo parece una credencial real" {
  run grep -nE '^[A-Z_0-9]*(PASSWORD|SECRET|KEY|TOKEN)[A-Z_0-9]*=(sk-|re_|ghp_|-----BEGIN|eyJ)' "$RAIZ/.env.example"
  [ -z "$output" ] || { echo "Valor con forma de credencial en .env.example"; return 1; }
}

@test "ningun valor del ejemplo es una palabra debil" {
  run grep -nE '(PASSWORD|SECRET|KEY)=(changeme|change_me|password|secret|admin|root|123456|qwerty)$' "$RAIZ/.env.example"
  [ -z "$output" ] || { echo "Valor debil en .env.example"; return 1; }
}

@test "las claves sensibles del kit usan marcadores, no valores" {
  run python3 "$RAIZ/scripts/check-env.py" --modo ejemplo
  [ "$status" -eq 0 ]
}
