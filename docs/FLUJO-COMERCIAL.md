# Atención inicial con chat web
1. Crear cuenta/espacio, agentes y equipos desde administración nativa. Definir acceso mínimo.
2. Crear bandeja de tipo Website y dominio autorizado.
3. Copiar el snippet generado por Chatwoot en el sitio de pruebas propio; no inventar tokens ni URLs.
4. Abrir sitio en sesión anónima, enviar mensaje ficticio y responder desde agente.
5. Probar asignación, etiqueta, nota interna, resolución y reapertura según funciones disponibles.
6. Probar un adjunto permitido y acceso tras reinicio/restauración. Documentar límites de tipo/tamaño y retención.
7. Configurar horario, mensaje fuera de horario y responsables de escalamiento.

El token público del widget no es una clave administrativa. Las claves API de agentes y contraseñas nunca se incorporan al frontend. La instalación no introduce Supabase Auth: cuentas y permisos son propios de Chatwoot.

## Canales adicionales
WhatsApp exige cuenta/proveedor habilitado, números, credenciales y pruebas del canal nativo; no se configura por recibir este ZIP. Correo entrante requiere mecanismo soportado y configuración separada. No hay mensajes enviados ni integraciones activadas por este paquete.

## Oferta Hefesto
Cobrar instalación, configuración de bandejas, inserción del widget, capacitación, respaldos y soporte. Definir agentes, bandejas, horas y canales dentro del alcance. Las cuotas comerciales no están implementadas por este paquete. No prometer IA, SSO, auditoría Enterprise o funciones pagas incluidas sin verificar licencia.

Una instancia por cliente facilita entrega. Si se comparten cuentas de varios clientes, revisar aislamiento y alcance de superadministración; este ZIP no implementa una plataforma SaaS de facturación/multitenencia propia.
