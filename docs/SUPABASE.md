# Preparar Supabase
## Proyecto exclusivo
Crear un proyecto nuevo dedicado a Chatwoot, preferentemente cerca del VPS. No reutilizar la base de Moodle, Nextcloud, OpenProject ni otra aplicación. Este paquete utiliza tablas en public: los esquemas administrados auth/storage permanecen intactos y no se respaldan como parte de Chatwoot.

Confirmar PostgreSQL16/17 y capacidad/conexiones disponibles. El preflight rechaza otras versiones hasta validarlas. Elegir una capacidad que soporte uso continuo; evaluar políticas de pausa y límites del plan antes de vender disponibilidad.

## Extensiones y usuario
Ejecutar sql/01-supabase.sql en SQL Editor con postgres SOLO antes de crear tablas Chatwoot. Comprueba que public no tenga tablas, habilita pg_stat_statements, pg_trgm, pgcrypto y vector, y crea chatwoot_app sin clave predeterminada. plpgsql ya debe existir.

Asignar contraseña larga y única a chatwoot_app desde una sesión psql administrativa usando `\password chatwoot_app` (solicita la clave sin incluirla en el comando). Utilizar credenciales administrativas solo para preparación, nunca como usuario de ejecución de la app. Guardar clave elegida en POSTGRES_PASSWORD mediante gestor seguro.

La aplicación usa search_path=public,extensions; las extensiones pueden estar en extensions o preexistir en public, pero vector debe ser visible. No mover extensiones de un proyecto compartido para acomodar este paquete.

## Evitar exposición por API
Deshabilitar Data API en los ajustes del proyecto según la interfaz vigente. Revisar también que las tablas no sean accesibles a anon/authenticated. El SQL quita permisos de esquema y futuros permisos públicos del rol de aplicación; el preflight revisa grants de tablas. Las variables de confirmación son una declaración del operador, no una consulta a la API de administración de Supabase.

No aplicar políticas RLS de otra app a tablas Chatwoot: la autorización la gestiona Chatwoot. Mantener base inaccesible mediante API pública y restringir acceso de red cuando sea posible. Nunca enviar una contraseña DB o service_role al navegador/widget.

## Conexión
Desde Connect del proyecto elegir conexión directa a puerto5432. Usuario: chatwoot_app; base: postgres; host obtenido del proyecto. Direct suele requerir IPv6 o la opción IPv4 correspondiente.

Si el VPS solo tiene IPv4, usar Shared Pooler SESSION5432; el usuario suele ser chatwoot_app.PROJECT_REF. Confirmar el formato de rol personalizado indicado por Supabase. No utilizar Transaction6543 ni el nombre postgres como usuario runtime. La consulta current_user debe devolver chatwoot_app.

Guardar la CA correspondiente al hostname en certs/ca.crt (ver certs/README.md: el pooler puede usar una cadena distinta de la conexión directa). PGSSLMODE=verify-full verifica cifrado/certificado/hostname. No desactivar validación para resolver un error de certificado. El preflight valida conexión con esas mismas propiedades y permisos.

## Límites y migraciones
Valores iniciales web1proceso×3threads y Sidekiq3; reservar margen para otras conexiones, preparación, herramientas y servicios Supabase. No equivalen a un máximo global garantizado. Ajustar en base a uso/plan y monitorear errores de conexión.

Ejecutar prepare en una ventana de mantenimiento al actualizar. Usa db:chatwoot_prepare, no reset. Si hay instalación parcial y preflight se detiene, revisar logs y respaldo; no eliminar tablas ni saltar comprobaciones a ciegas. Puede requerir intervención para recuperar una migración fallida.
