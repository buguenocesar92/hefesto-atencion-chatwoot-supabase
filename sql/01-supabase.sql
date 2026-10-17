-- Ejecutar SOLO en un proyecto Supabase nuevo, exclusivo para Chatwoot,
-- desde el SQL Editor con el rol administrativo postgres.
-- No elimina tablas, esquemas, roles ni datos.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public') THEN
    RAISE EXCEPTION 'public debe estar vacio para esta preparacion inicial';
  END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='chatwoot_app') THEN
    CREATE ROLE chatwoot_app LOGIN;
  END IF;
END $$;
GRANT CONNECT ON DATABASE postgres TO chatwoot_app;
GRANT USAGE, CREATE ON SCHEMA public TO chatwoot_app;
GRANT USAGE ON SCHEMA extensions TO chatwoot_app;
ALTER ROLE chatwoot_app IN DATABASE postgres SET search_path = public, extensions;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE chatwoot_app IN SCHEMA public
  REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE chatwoot_app IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE chatwoot_app IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
-- Asignar clave al rol por sesion psql administrativa con: \password chatwoot_app
-- Conservarla en POSTGRES_PASSWORD. No guardar la clave real en este archivo.
