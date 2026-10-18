-- Execute após 001_init.sql; mantém histórico de reservas.
alter table public.equipment add column if not exists code text;
alter table public.equipment add column if not exists manufacturer text;
alter table public.equipment add column if not exists model text;
alter table public.equipment add column if not exists kind text not null default 'instrument' check(kind in ('instrument','accessory'));
alter table public.equipment add column if not exists operational_status text not null default 'operational' check(operational_status in ('operational','maintenance','unavailable','retired'));
alter table public.equipment add column if not exists notice jsonb not null default '{}'::jsonb;
alter table public.equipment add column if not exists pnipe_url text;
alter table public.equipment add column if not exists depends_on text;
create unique index if not exists equipment_institution_code_unique on public.equipment(institution_id,code);
-- Mantém os dois critérios independentes e protege reservas diretamente no servidor.
create or replace function public.validate_booking() returns trigger language plpgsql security definer set search_path='' as $$declare e public.equipment%rowtype;p public.projects%rowtype;begin
 if tg_op='UPDATE' then
  if current_setting('app.booking_action',true)<>'allowed' then raise exception 'Atualização direta de reserva proibida';end if;
  if (new.institution_id,new.equipment_id,new.project_id,new.created_by,new.start_at,new.end_at,new.scientific_lead_snapshot,new.financial_lead_snapshot,new.purpose) is distinct from (old.institution_id,old.equipment_id,old.project_id,old.created_by,old.start_at,old.end_at,old.scientific_lead_snapshot,old.financial_lead_snapshot,old.purpose) then raise exception 'Campos protegidos não podem ser alterados';end if;
  return new;
 end if;
 select * into e from public.equipment where id=new.equipment_id;select * into p from public.projects where id=new.project_id;
 if e.id is null or p.id is null or not e.active or e.kind<>'instrument' or e.operational_status<>'operational' or e.institution_id<>p.institution_id then raise exception 'Equipamento/projeto incompatível ou indisponível';end if;
 if e.depends_on is not null and exists(select 1 from public.equipment dep where dep.institution_id=e.institution_id and dep.code=e.depends_on and (dep.operational_status<>'operational' or not dep.active)) then raise exception 'Acessório vinculado indisponível';end if;
 if not public.is_member(e.institution_id) or (not public.is_project_member(p.id) and not public.has_role(e.institution_id,array['admin','lab_manager'])) then raise exception 'Sem autorização para este projeto';end if;
 new.created_by=auth.uid();new.institution_id=e.institution_id;new.funding_source_snapshot=p.funding_source;new.scientific_lead_snapshot=p.scientific_lead;new.financial_lead_snapshot=p.financial_lead;new.status='confirmed';new.check_in_at=null;new.check_out_at=null;return new;end$$;
