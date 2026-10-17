# Hefesto Atención · Chatwoot Community4.18.0 + Supabase
Paquete de despliegue para bandeja de atención con chat web, agentes, equipos y conversaciones. Base PostgreSQL de Supabase; Chatwoot web, Sidekiq, Redis y adjuntos en tu VPS/Coolify.

## Qué está validado y qué falta
Revisados requisitos oficiales, configuración y esquema de Chatwoot4.18.0 y compatibilidad documental de Supabase con PostgreSQL/pgvector. Archivos y scripts revisados estáticamente. No hay conexión a tu Supabase, migraciones ejecutadas, despliegue ni prueba de mensajes. Ruby/Docker no están disponibles en el entorno de generación; el preflight y flujos deben probarse en destino.

## Stack
- Imagen oficial Community v4.18.0-ce fijada por digest; no presupone funciones Enterprise.
- Supabase exclusivo para esta instalación: PostgreSQL16 o17, rol chatwoot_app y extensiones nativas necesarias.
- Conexión5432 directa preferida; pooler SESSION si se requiere IPv4. No usar transaction/6543.
- TLS verify-full con CA del proyecto; Data API deshabilitada para este proyecto.
- Redis7.4 privado con contraseña y RDB persistente; worker separado.
- Adjuntos locales persistentes /app/storage. No se conectó Supabase Storage/Auth/Realtime.

## Arranque
1. Preparar proyecto Supabase y rol siguiendo docs/SUPABASE.md.
2. `python3 scripts/configure.py cliente-demo atencion.tudominio.cl`
3. Completar .env con host/usuario/clave de Supabase y SMTP; colocar certs/ca.crt.
4. Confirmar aislamiento y Data API deshabilitada cambiando ambas variables de confirmación a true.
5. `docker compose --profile setup run --rm prepare` ejecuta preflight y tarea nativa db:chatwoot_prepare. No usar db:reset ni db:setup sobre Supabase.
6. Bootstrap privado y creación de cuenta: docs/COOLIFY.md.
7. Publicar con registro cerrado, configurar bandeja/widget y completar docs/ACEPTACION.md.

Se requiere Docker Compose v2 y Python3.11+ para scripts. Ajustar CPU/RAM según requisitos oficiales y carga; como punto inicial conservador del VPS considerar4vCPU/8GB RAM y espacio para adjuntos/respaldo, midiendo el uso real. Supabase tiene sus propios límites y costos.

## Contenido y límites
SQL inicial sin borrado, Compose, scripts de preflight/arranque/respaldo, guía de recuperación y traspaso, configuración funcional y plantillas operativas. El ZIP contiene configuración, no binarios ni base de datos real.

No incluye WhatsApp conectado, correo entrante, OAuth, IA/Captain, n8n ni pagos. SMTP saliente debe configurarse; el valor inicial127.0.0.1:2525 no entrega correo. Confirmación de cuenta, invitaciones y restablecimientos no estarán operativos hasta hacerlo.

## Licencia
Usa la edición Community y conserva licencias/atribuciones de Chatwoot y componentes. No incluye licencia Enterprise. Hefesto comercializa implementación, alojamiento y soporte. Verificar alcance de cada función en la edición instalada.
