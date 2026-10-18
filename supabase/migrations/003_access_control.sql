-- Run after 001_init.sql and 002_equipment_catalog.sql.
create table if not exists public.equipment_authorizations(
 equipment_id uuid not null references public.equipment(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 granted_by uuid references auth.users(id),
 granted_at timestamptz not null default now(),
 primary key(equipment_id,user_id)
);
alter table public.equipment_authorizations enable row level security;
create policy equipment_auth_read on public.equipment_authorizations for select to authenticated
 using(user_id=auth.uid() or exists(select 1 from public.equipment e where e.id=equipment_id and public.has_role(e.institution_id,array['admin','lab_manager'])));
grant select on public.equipment_authorizations to authenticated;
-- No direct insert/update/delete to authenticated. Managed by privileged Edge Function.
create or replace function public.validate_booking() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.equipment%rowtype;p public.projects%rowtype;
begin
 if tg_op='UPDATE' then
  if current_setting('app.booking_action',true)<>'allowed' then raise exception 'Atualização direta de reserva proibida';end if;
  if (new.institution_id,new.equipment_id,new.project_id,new.created_by,new.start_at,new.end_at,new.scientific_lead_snapshot,new.financial_lead_snapshot,new.purpose) is distinct from (old.institution_id,old.equipment_id,old.project_id,old.created_by,old.start_at,old.end_at,old.scientific_lead_snapshot,old.financial_lead_snapshot,old.purpose) then raise exception 'Campos protegidos não podem ser alterados';end if;
  return new;
 end if;
 select * into e from public.equipment where id=new.equipment_id;
 select * into p from public.projects where id=new.project_id;
 if e.id is null or p.id is null or not e.active or e.institution_id<>p.institution_id then raise exception 'Equipamento/projeto incompatível ou indisponível';end if;
 if not public.is_member(e.institution_id) then raise exception 'Usuário não pertence à instituição';end if;
 if not public.has_role(e.institution_id,array['admin']) and not exists(select 1 from public.equipment_authorizations ea where ea.equipment_id=e.id and ea.user_id=auth.uid()) then raise exception 'Usuário não autorizado para o instrumento';end if;
 if not public.is_project_member(p.id) and not public.has_role(e.institution_id,array['admin','lab_manager']) then raise exception 'Sem autorização para este projeto';end if;
 new.created_by=auth.uid();new.institution_id=e.institution_id;new.funding_source_snapshot=p.funding_source;new.scientific_lead_snapshot=p.scientific_lead;new.financial_lead_snapshot=p.financial_lead;new.status='confirmed';new.check_in_at=null;new.check_out_at=null;return new;
end$$;
-- Only return time intervals, never the identity, purpose, or project of another user.
create or replace function public.equipment_busy_intervals(p_equipment_id uuid,p_from timestamptz,p_to timestamptz)
returns table(start_at timestamptz,end_at timestamptz) language plpgsql stable security definer set search_path='' as $$
declare inst uuid;
begin
 select institution_id into inst from public.equipment where id=p_equipment_id;
 if auth.uid() is null or inst is null or not public.is_member(inst) then raise exception 'Not authorized';end if;
 if p_to<=p_from or p_to>p_from+interval '32 days' then raise exception 'Invalid interval';end if;
 return query select b.start_at,b.end_at from public.bookings b where b.equipment_id=p_equipment_id and b.status='confirmed' and b.start_at<p_to and b.end_at>p_from;
end$$;
revoke all on function public.equipment_busy_intervals(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.equipment_busy_intervals(uuid,timestamptz,timestamptz) to authenticated;
