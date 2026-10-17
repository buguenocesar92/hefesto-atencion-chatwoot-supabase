# Copia completa del servicio
Se necesitan base de aplicación, adjuntos, Redis y configuración/secretos. El respaldo administrado de PostgreSQL no copia automáticamente los archivos locales del VPS.

Ejecutar `python3 scripts/backup.py` en contexto Compose real. Detiene web/worker, exporta esquema public usando cliente PostgreSQL17, fuerza Redis SAVE, detiene Redis y copia RDB + adjuntos; intenta reiniciar al terminar. Hay pausa de servicio. Revisar código de salida, manifest completed y salud de los tres servicios. Detener también integraciones externas que escriban directamente en la base durante la copia.

El dump contiene solo public, no esquemas internos de Supabase. Necesita las extensiones del SQL de preparación para restaurar. Guardar este ZIP/repositorio completo con el respaldo. Cifrar y copiar fuera del VPS: hay conversaciones, datos personales, tokens y secretos. No se configura cifrado remoto, retención ni cron automáticamente.

## Restauración
Usar proyecto Supabase nuevo y exclusivo y volúmenes nuevos, misma versión de Chatwoot. No arrancar web/worker ni ejecutar prepare antes de importar un respaldo existente.
1. Ejecutar preparación SQL en nuevo proyecto, asignar clave al rol y restaurar configuración .env (modo0600), conservando SECRET_KEY_BASE/REDIS_PASSWORD. Actualizar solo conexión/CA y nombres destino cuando corresponda.
2. Verificar manifest/checksums y origen confiable de archivos.
3. Restaurar base vacía:
   `python3 scripts/restore_db.py /ruta/respaldo`
   El script verifica checksum/base vacía y omite únicamente la creación del esquema public ya existente; no borra ese esquema. Si hay un error parcial, usar otro proyecto vacío y diagnosticar antes de repetir.
4. Restaurar archivos:
   `docker compose run --rm --no-deps -T --entrypoint tar web -xzf - -C /app/storage < /ruta/respaldo/storage.tar.gz`
5. Restaurar Redis vacío y detenido:
   `docker compose run --rm --no-deps -T --entrypoint tar redis -xzf - -C /data < /ruta/respaldo/redis.tar.gz`
6. Comprobar permisos de archivos y ejecutar preflight --ready con el servicio prepare sobrescribiendo su entrada:
   `docker compose run --rm --no-deps --entrypoint bundle prepare exec ruby /opt/hefesto/preflight.rb --ready`
7. En una copia de pruebas, bloquear salida externa y revisar colas antes de arrancar worker: puede haber notificaciones pendientes. No emitir mensajes duplicados a clientes. En restauración productiva, revisar entregas/colas y proveedor: no hay garantía exactly-once entre servicios externos.
8. Arrancar bootstrap/HTTPS cuando proceda y verificar login, conversaciones, adjuntos, widget y trabajo en segundo plano.

No usar --clean, DROP SCHEMA public ni db:reset sobre un proyecto existente. La restauración falla si hay objetos incompatibles: preparar otro destino vacío. Para actualizaciones, respaldar y ensayar antes; revertir imagen puede requerir restaurar también el esquema compatible.

## Traspaso
Transferir proyecto Supabase mediante mecanismo admitido o restauración planificada; no basta cambiar .env a otro proyecto vacío. Entregar DNS, Coolify, repo, imágenes/digests, CA, volúmenes, claves, acceso de agente/admin, SMTP, inventario de canales y backups probados. Secretos por gestor seguro, separados del repositorio. Retirar accesos temporales según acuerdo.
