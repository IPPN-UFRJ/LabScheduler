-- Run in a NEW Supabase project SQL Editor. This migration does not seed real user data.
create extension if not exists btree_gist;
create table public.institutions(id uuid primary key default gen_random_uuid(),name text not null);
create table public.memberships(institution_id uuid not null references public.institutions(id),user_id uuid not null references auth.users(id),role text not null check(role in ('admin','lab_manager','financial_manager','researcher')),primary key(institution_id,user_id));
create table public.equipment(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),name text not null,lab text not null,active boolean not null default true);
create table public.projects(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),name text not null,scientific_lead text not null,financial_lead text not null,funding_source text not null);
create table public.project_members(project_id uuid not null references public.projects(id),user_id uuid not null references auth.users(id),primary key(project_id,user_id));
create table public.bookings(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),equipment_id uuid not null references public.equipment(id),project_id uuid not null references public.projects(id),created_by uuid not null references auth.users(id),start_at timestamptz not null,end_at timestamptz not null,check_in_at timestamptz,check_out_at timestamptz,status text not null default 'confirmed' check(status in ('confirmed','cancelled')),purpose text,funding_source_snapshot text not null,scientific_lead_snapshot text not null,financial_lead_snapshot text not null,created_at timestamptz not null default now(),check(end_at>start_at),check(check_out_at is null or check_in_at is not null));
-- Prevent concurrent overlaps in PostgreSQL, not only the browser.
alter table public.bookings add constraint no_equipment_overlap exclude using gist(equipment_id with =,tstzrange(start_at,end_at,'[)') with &&) where(status='confirmed');
create table public.funding_change_requests(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id),requested_by uuid not null references auth.users(id),old_source text not null,new_source text not null,reason text not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),decided_by uuid references auth.users(id),decided_at timestamptz,created_at timestamptz not null default now());
create table public.audit_log(id uuid primary key default gen_random_uuid(),institution_id uuid not null references public.institutions(id),actor uuid references auth.users(id),entity text not null,entity_id uuid not null,action text not null,details jsonb not null default '{}'::jsonb,created_at timestamptz not null default now());
create index on public.bookings(institution_id,start_at);create index on public.bookings(created_by);create index on public.project_members(user_id);
create or replace function public.has_role(p_institution uuid,p_roles text[]) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.memberships m where m.institution_id=p_institution and m.user_id=(select auth.uid()) and m.role=any(p_roles))$$;
create or replace function public.is_member(p_institution uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.memberships m where m.institution_id=p_institution and m.user_id=(select auth.uid()))$$;
create or replace function public.is_project_member(p_project uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.project_members pm where pm.project_id=p_project and pm.user_id=(select auth.uid()))$$;
-- Trigger forces all booking-derived values to match authoritative server-side records.
-- Allow controlled updates only from trusted SECURITY DEFINER functions.
create or replace function public.validate_booking() returns trigger language plpgsql security definer set search_path='' as $$declare e public.equipment%rowtype;p public.projects%rowtype;begin
 if tg_op='UPDATE' then
  if current_setting('app.booking_action',true)<>'allowed' then raise exception 'Atualização direta de reserva proibida';end if;
  if (new.institution_id,new.equipment_id,new.project_id,new.created_by,new.start_at,new.end_at,new.scientific_lead_snapshot,new.financial_lead_snapshot,new.purpose) is distinct from (old.institution_id,old.equipment_id,old.project_id,old.created_by,old.start_at,old.end_at,old.scientific_lead_snapshot,old.financial_lead_snapshot,old.purpose) then raise exception 'Campos protegidos não podem ser alterados';end if;
  return new;
 end if;
 select * into e from public.equipment where id=new.equipment_id;select * into p from public.projects where id=new.project_id;
 if e.id is null or p.id is null or not e.active or e.institution_id<>p.institution_id then raise exception 'Equipamento/projeto incompatível ou indisponível';end if;
 if not public.is_member(e.institution_id) or (not public.is_project_member(p.id) and not public.has_role(e.institution_id,array['admin','lab_manager'])) then raise exception 'Sem autorização para este projeto';end if;
 new.created_by=auth.uid();new.institution_id=e.institution_id;new.funding_source_snapshot=p.funding_source;new.scientific_lead_snapshot=p.scientific_lead;new.financial_lead_snapshot=p.financial_lead;new.status='confirmed';new.check_in_at=null;new.check_out_at=null;return new;end$$;
create or replace function public.booking_action(p_booking_id uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$declare b public.bookings%rowtype;begin
 select * into b from public.bookings where id=p_booking_id for update;
 if b.id is null or not (b.created_by=auth.uid() or public.has_role(b.institution_id,array['admin','lab_manager'])) then raise exception 'Sem permissão';end if;
 perform set_config('app.booking_action','allowed',true);
 if p_action='checkin' and b.status='confirmed' and b.check_in_at is null then update public.bookings set check_in_at=now() where id=b.id;
 elsif p_action='checkout' and b.status='confirmed' and b.check_in_at is not null and b.check_out_at is null then update public.bookings set check_out_at=now() where id=b.id;
 elsif p_action='cancel' and b.status='confirmed' and b.check_in_at is null then update public.bookings set status='cancelled' where id=b.id;
 else raise exception 'Ação ou estado inválido';end if;
 insert into public.audit_log(institution_id,actor,entity,entity_id,action)values(b.institution_id,auth.uid(),'booking',b.id,p_action);
 end$$;
create or replace function public.validate_funding_request() returns trigger language plpgsql security definer set search_path='' as $$declare b public.bookings%rowtype;begin
 if tg_op<>'INSERT' then raise exception 'Edição direta proibida';end if;
 select * into b from public.bookings where id=new.booking_id;
 if b.id is null or not(b.created_by=auth.uid() or public.has_role(b.institution_id,array['admin','lab_manager'])) then raise exception 'Sem autorização';end if;
 if length(trim(new.reason))<5 or length(trim(new.new_source))<2 or new.new_source=b.funding_source_snapshot then raise exception 'Solicitação inválida';end if;
 new.requested_by=auth.uid();new.old_source=b.funding_source_snapshot;new.status='pending';new.decided_by=null;new.decided_at=null;return new;end$$;
create trigger funding_guard before insert or update on public.funding_change_requests for each row execute function public.validate_funding_request();
create or replace function public.decide_funding_change(p_request_id uuid,p_decision text) returns void language plpgsql security definer set search_path='' as $$declare r public.funding_change_requests%rowtype;b public.bookings%rowtype;begin
 if p_decision not in ('approved','rejected') then raise exception 'Decisão inválida';end if;
 select * into r from public.funding_change_requests where id=p_request_id for update;select * into b from public.bookings where id=r.booking_id for update;
 if r.id is null or r.status<>'pending' or r.requested_by=auth.uid() or not public.has_role(b.institution_id,array['admin','financial_manager']) then raise exception 'Não autorizado ou solicitação já decidida';end if;
 perform set_config('app.booking_action','allowed',true);perform set_config('app.funding_decision','allowed',true);
 update public.funding_change_requests set status=p_decision,decided_by=auth.uid(),decided_at=now() where id=r.id;
 if p_decision='approved' then update public.bookings set funding_source_snapshot=r.new_source where id=b.id;end if;
 insert into public.audit_log(institution_id,actor,entity,entity_id,action,details)values(b.institution_id,auth.uid(),'funding_change',r.id,p_decision,jsonb_build_object('old',r.old_source,'new',r.new_source));end$$;
-- Permit controlled funding decision updates in trigger.
create or replace function public.validate_funding_request() returns trigger language plpgsql security definer set search_path='' as $$declare b public.bookings%rowtype;begin
 if tg_op='UPDATE' then if current_setting('app.funding_decision',true)<>'allowed' then raise exception 'Edição direta proibida';end if;return new;end if;
 select * into b from public.bookings where id=new.booking_id;
 if b.id is null or not(b.created_by=auth.uid() or public.has_role(b.institution_id,array['admin','lab_manager'])) then raise exception 'Sem autorização';end if;
 if length(trim(new.reason))<5 or length(trim(new.new_source))<2 or new.new_source=b.funding_source_snapshot then raise exception 'Solicitação inválida';end if;
 new.requested_by=auth.uid();new.old_source=b.funding_source_snapshot;new.status='pending';new.decided_by=null;new.decided_at=null;return new;end$$;
create trigger bookings_guard before insert or update on public.bookings for each row execute function public.validate_booking();
create trigger funding_guard before insert or update on public.funding_change_requests for each row execute function public.validate_funding_request();
-- Do not grant direct table updates; only functions can change controlled fields.
alter table public.institutions enable row level security;alter table public.memberships enable row level security;alter table public.equipment enable row level security;alter table public.projects enable row level security;alter table public.project_members enable row level security;alter table public.bookings enable row level security;alter table public.funding_change_requests enable row level security;alter table public.audit_log enable row level security;
create policy institutions_read on public.institutions for select to authenticated using(public.is_member(id));
create policy memberships_read on public.memberships for select to authenticated using(user_id=auth.uid() or public.has_role(institution_id,array['admin']));
create policy equipment_read on public.equipment for select to authenticated using(public.is_member(institution_id));
create policy projects_read on public.projects for select to authenticated using(public.is_project_member(id) or public.has_role(institution_id,array['admin','lab_manager','financial_manager']));
create policy project_members_read on public.project_members for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.projects p where p.id=project_id and public.has_role(p.institution_id,array['admin','lab_manager'])));
create policy bookings_read on public.bookings for select to authenticated using(public.is_member(institution_id));
create policy bookings_insert on public.bookings for insert to authenticated with check(created_by=auth.uid() and public.is_member(institution_id));
create policy funding_read on public.funding_change_requests for select to authenticated using(requested_by=auth.uid() or exists(select 1 from public.bookings b where b.id=booking_id and public.has_role(b.institution_id,array['admin','financial_manager'])));
create policy funding_insert on public.funding_change_requests for insert to authenticated with check(requested_by=auth.uid());
create policy audit_read on public.audit_log for select to authenticated using(public.has_role(institution_id,array['admin','lab_manager','financial_manager']));
revoke all on public.institutions,public.memberships,public.equipment,public.projects,public.project_members,public.bookings,public.funding_change_requests,public.audit_log from anon;
grant select on public.institutions,public.memberships,public.equipment,public.projects,public.project_members,public.bookings,public.funding_change_requests,public.audit_log to authenticated;
grant insert on public.bookings,public.funding_change_requests to authenticated;
revoke all on function public.booking_action(uuid,text),public.decide_funding_change(uuid,text) from public,anon;
grant execute on function public.booking_action(uuid,text),public.decide_funding_change(uuid,text) to authenticated;
