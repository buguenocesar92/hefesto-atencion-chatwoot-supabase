require 'pg'
abort 'Confirme proyecto Supabase exclusivo antes de continuar' unless ENV['SUPABASE_DEDICATED_CONFIRMED'] == 'true'
abort 'Desactive Data API y confirme la variable antes de continuar' unless ENV['SUPABASE_DATA_API_DISABLED'] == 'true'
abort 'Puerto debe ser 5432: conexion directa o pooler SESSION' unless ENV.fetch('POSTGRES_PORT','5432') == '5432'
ALLOWED_SSLMODES = %w[disable allow prefer require verify-ca verify-full].freeze
sslmode = ENV.fetch('DB_SSLMODE', ENV.fetch('PGSSLMODE', 'verify-full'))
abort "DB_SSLMODE invalido: #{sslmode.inspect}" unless ALLOWED_SSLMODES.include?(sslmode)
abort 'Falta certs/ca.crt de su proyecto Supabase' if sslmode == 'verify-full' && !File.file?(ENV.fetch('PGSSLROOTCERT'))
begin
  sslopts = sslmode == 'verify-full' ? { sslmode: sslmode, sslrootcert: ENV.fetch('PGSSLROOTCERT') } : { sslmode: sslmode }
  conn=PG.connect({ host: ENV.fetch('POSTGRES_HOST'), port: ENV.fetch('POSTGRES_PORT','5432'),
    dbname: ENV.fetch('POSTGRES_DATABASE'), user: ENV.fetch('POSTGRES_USERNAME'),
    password: ENV.fetch('POSTGRES_PASSWORD'), options: '-c search_path=public,extensions', connect_timeout: 15 }.merge(sslopts))
  major=conn.exec("SELECT current_setting('server_version_num')::int / 10000 AS major")[0]['major'].to_i
  abort 'Este paquete admite PostgreSQL16/17; validar otra version antes de usarla' unless [16,17].include?(major)
  role=conn.exec('SELECT current_user AS role')[0]['role']
  abort 'Usar rol dedicado chatwoot_app, no postgres' unless role == 'chatwoot_app'
  required=%w[pg_stat_statements pg_trgm pgcrypto plpgsql vector]
  present=conn.exec('SELECT extname FROM pg_extension').map{|r|r['extname']}
  abort "Faltan extensiones: #{(required-present).join(', ')}" unless (required-present).empty?
  abort 'El tipo vector no es visible en search_path' if conn.exec("SELECT to_regtype('vector')::text AS type")[0]['type'].nil?
  perms=conn.exec("SELECT has_schema_privilege(current_user,'public','USAGE') AND has_schema_privilege(current_user,'public','CREATE') AS ok")[0]['ok']
  abort 'Falta USAGE/CREATE en public' unless perms == 't'
  tables=conn.exec("SELECT tablename,tableowner FROM pg_tables WHERE schemaname='public'").to_a
  abort 'Hay tablas public de otro propietario: no migrar este proyecto' if tables.any?{|r|r['tableowner']!='chatwoot_app'}
  names=tables.map{|r|r['tablename']}
  if !names.empty? && !%w[ar_internal_metadata accounts installation_configs].all?{|t|names.include?(t)}
    abort 'Base public no vacia y sin marcadores completos Chatwoot; revise manualmente antes de migrar'
  end
  if ARGV.include?('--ready')
    abort 'Faltan tablas: ejecutar servicio prepare primero' unless %w[accounts users conversations ar_internal_metadata].all?{|t|names.include?(t)}
  end
  %w[anon authenticated].each do |api_role|
    exists=conn.exec_params('SELECT 1 FROM pg_roles WHERE rolname=$1',[api_role]).ntuples>0
    next unless exists
    exposed=conn.exec_params("SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') AND has_table_privilege($1,c.oid,'SELECT,INSERT,UPDATE,DELETE')",[api_role])
    abort "Rol #{api_role} tiene privilegios sobre tablas public; revisar grants" if exposed.ntuples>0
  end
  puts "Preflight OK: PostgreSQL #{major}, sslmode=#{sslmode}, rol/extensiones/permisos comprobados"
ensure
  conn&.close
end
