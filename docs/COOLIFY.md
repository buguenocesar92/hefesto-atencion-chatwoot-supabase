# Primer acceso y publicación
## Bootstrap
Con Supabase preparado, CA/.env válidos y SMTP operativo:
1. `docker compose --profile setup run --rm prepare`
2. `docker compose -f compose.yaml -f compose.bootstrap.yaml up -d web worker redis`
3. Desde tu computador: `ssh -L 3000:127.0.0.1:3000 usuario@IP_DEL_VPS`
4. Abrir http://127.0.0.1:3000; crear la cuenta administradora mediante onboarding nativo, verificar correo si lo solicita y probar login. Solo este override permite registro.
5. No enviar invitaciones a otros usuarios desde bootstrap: los enlaces usan localhost. No asignar todavía dominio público.
6. Detener con `docker compose -f compose.yaml -f compose.bootstrap.yaml down` SIN -v.

## Coolify
Crear recurso Docker Compose desde repositorio privado, archivo compose.yaml y raíz del paquete. No versionar .env ni backups. Configurar variables en su editor seguro, manteniendo SECRET_KEY_BASE, REDIS_PASSWORD, nombres de volúmenes y conexión Supabase.

El montaje certs/ca.crt debe existir en el servidor/contexto del recurso; la CA no es una clave privada, puede incluirse en tu repositorio privado si se decide conscientemente. Los archivos ops/ deben estar presentes.

Asignar https://atencion.cliente.cl solo a web, puerto3000. Mantener worker/redis sin puertos o dominios. No desplegar el override bootstrap. ENABLE_ACCOUNT_SIGNUP=false en producción; verificar rechazo de registro nuevo. Proxy debe soportar WebSockets y preservar Host/protocolo HTTPS.

El servicio prepare está bajo perfil setup: no se ejecuta automáticamente al desplegar el recurso. Debe ejecutarse antes en el MISMO contexto/configuración del recurso o antes del bootstrap como se indica arriba. No arrancar web/worker sobre base no preparada.

## SMTP
Usar proveedor/remitente autorizados. Completar SMTP_ADDRESS, PORT, DOMAIN, USERNAME, PASSWORD y MAILER_SENDER_EMAIL. La configuración base usa STARTTLS y validación peer; validar parámetros específicos con tu proveedor. No hay servidor de correo incluido.

El correo entrante es un canal aparte: configurar SMTP no crea recepción ni MX. Probar recuperación/invitación después de publicar HTTPS. Revisar cola de Sidekiq y fallos, no solo respuesta HTTP.

## Operación
Web healthy valida HTTP. La prueba de worker requiere mensaje/evento que produzca trabajo y revisar procesamiento. Redis guarda RDB; una caída abrupta puede perder cambios desde el último snapshot. El respaldo coordinado fuerza SAVE. Para una política de durabilidad distinta, diseñar y validar AOF junto con recuperación antes de activarlo.
