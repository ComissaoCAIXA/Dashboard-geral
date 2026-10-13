-- Limite de tentativas sem guardar IP.
-- O IP do visitante só é usado na hora, para calcular um código irreversível (SHA-256 do IP com um
-- "tempero" secreto e aleatório). O tempero muda a cada hora e é apagado logo depois; os registros de
-- tentativas também (017). Assim o banco nunca guarda o IP, e ninguém consegue voltar do código ao IP
-- depois que o tempero é apagado. O limite por visitante continua funcionando igual.

create table public._sal (
  hora timestamptz primary key,
  sal  text not null
);
alter table public._sal enable row level security;
revoke all on public._sal from public, anon, authenticated;
comment on table public._sal is 'Tempero secreto do código do limite de tentativas; troca a cada hora e é apagado em seguida.';

create or replace function public._ip() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare ip text; h timestamptz := date_trunc('hour', now()); s text;
begin
  ip := coalesce(nullif(trim(split_part(
          nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ',', 1)), ''), 'desconhecido');
  insert into public._sal (hora, sal)
  values (h, md5(gen_random_uuid()::text || clock_timestamp()::text) || md5(gen_random_uuid()::text))
  on conflict (hora) do nothing;
  select sal into s from public._sal where hora = h;
  return encode(sha256(convert_to(ip || '|' || s, 'UTF8')), 'hex');
end $$;
revoke execute on function public._ip() from public, anon, authenticated;

-- Limpeza a cada 10 minutos: tentativas com mais de 1 hora e temperos que não estão mais em uso
create or replace function public._limpar_limites() returns void
language sql security definer set search_path = '' as $$
  delete from public.limites where em < now() - interval '1 hour';
  delete from public._sal where hora < date_trunc('hour', now());
$$;
revoke execute on function public._limpar_limites() from public, anon, authenticated;

-- Os registros antigos ainda têm IP: apagar
delete from public.limites;
