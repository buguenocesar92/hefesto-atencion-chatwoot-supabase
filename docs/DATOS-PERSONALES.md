# Datos personales — Atencion (Chatwoot)

Contrato del kit `hefesto-atencion-chatwoot-supabase` bajo la **Ley 21.719** (Proteccion de Datos
Personales, Chile). Este documento es normativo para el kit: el despliegue no
se considera completo sin el.

## 1. Inventario de datos

Chatwoot es un buzon de atencion: guarda **conversaciones**, nombre, correo, telefono y adjuntos de quien contacta, historial del agente, etiquetas y estado de satisfaccion. La IP y el user-agent quedan en los logs de acceso. El kit NO administra los datos de los clientes de la organizacion, ni nominas, ni datos de salud.

## 2. Control de acceso y roles

Chatwoot separa por roles internos: agente, supervisor y administrador, y por bandeja: las conversaciones de un canal no se mezclan con las de otro. El rol de base `POSTGRES_USERNAME` (`chatwoot_app`) es de aplicacion. La autorizacion la gestiona Chatwoot, no el kit.

## 3. Minimizacion

El kit no registra datos personales en sus propios logs. El `storage.tar.gz` del respaldo contiene **adjuntos**, que son datos personales en claro: se marca como material cifrado y de acceso restringido. El `redis.tar.gz` contiene colas, que pueden llevar fragmentos de mensajes.

## 4. Retencion

Retencion propuesta: **24 meses** para conversaciones y adjuntos, **3 meses** para logs de acceso y **7 dias** para el respaldo verificado. Conversaciones y adjuntos tienen plazos distintos porque el adjunto puede tener una relacion comercial que dura mas.

## 5. Supresion, rectificacion y acceso del titular

La supresion la ejecuta el cliente dentro de Chatwoot: se eliminan o anonimizan las conversaciones y los adjuntos de esa persona, y se documenta la solicitud. El kit no borra datos por su cuenta: deja el procedimiento y garantiza que el respaldo se verifique antes de restaurar.

## 6. Acceso al respaldo, auditoria y transito

`SECRET_KEY_BASE` firma las sesiones de Chatwoot: se guarda en el gestor de secretos y nunca en el repositorio. El respaldo sale cifrado cuando hay receptor age, `backups/` queda en 0700 y cada restauracion deja auditoria en `logs/restore-audit.log`.

### Acceso al respaldo y transito

`DB_SSLMODE` por defecto `verify-full` con CA de Supabase. Redis es interno a la red `backend` y exige `requirepass`. TLS de la publicacion, en Coolify/Traefik.

## 7. Que NO decide el kit

Los plazos definitivos, la base legal y la incorporacion de los titulares al
registro de actividades de tratamiento son decisiones **del cliente**, no del
kit. Este documento deja la propuesta escrita y verificable; su validacion es
una tarea pendiente de coordinacion.

## 8. Verificacion

```bash
bats tests/                              # ciclo de respaldo con datos sinteticos
python3 scripts/check-env.py --modo real # contrato del .env, sin imprimir valores
python3 scripts/check_backup.py <respaldo>
```
