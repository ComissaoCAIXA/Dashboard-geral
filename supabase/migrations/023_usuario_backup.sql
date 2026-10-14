-- Usuário só de leitura para o backup diário (repositório privado ComissaoCAIXA/Dashboard-backup).
-- Lê todas as tabelas do esquema public (inclusive as protegidas por RLS), mas não altera nada.
-- A senha NÃO fica aqui: um administrador define no SQL Editor do Supabase com
--   alter role backup_leitura password '...';
-- e a mesma senha vai só para o segredo SUPABASE_DB_URL do repositório de backup.
create role backup_leitura login bypassrls;
alter role backup_leitura set default_transaction_read_only = on;
grant usage on schema public to backup_leitura;
grant select on all tables in schema public to backup_leitura;
grant select on all sequences in schema public to backup_leitura;
alter default privileges in schema public grant select on tables to backup_leitura;
alter default privileges in schema public grant select on sequences to backup_leitura;
