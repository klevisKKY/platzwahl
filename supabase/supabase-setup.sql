-- =====================================================================
-- Platzwahl: Rückwerbung, Datenbank für Supabase
-- Einmal komplett in Supabase unter "SQL Editor" einfügen und auf "Run"
-- klicken. Fragt Supabase wegen "destructive operations" nach, bestätige
-- mit "Run this query". Am Ende steht "Success. No rows returned".
-- Du kannst das Skript später gefahrlos noch einmal ausführen.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tabellen
-- ---------------------------------------------------------------------

-- Betriebe, die Gespräche anbieten
create table if not exists public.betriebe (
  id              uuid primary key default gen_random_uuid(),
  owner           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name            text not null check (char_length(name) between 2 and 80),
  bereich         text not null check (char_length(bereich) between 2 and 40),
  land            text not null check (land in ('BW','BY','BE','BB','HB','HH','HE','MV','NI','NW','RP','SL','SN','ST','SH','TH')),
  ort             text not null check (char_length(ort) between 2 and 60),
  berufe          text[] not null check (cardinality(berufe) between 1 and 8),
  erwachsene      boolean not null default false,
  kanaele         text[] not null check (cardinality(kanaele) between 1 and 3 and kanaele <@ array['video','telefon','vorort']),
  person          text not null check (char_length(person) between 2 and 60),
  vorstellung     text not null default '' check (char_length(vorstellung) <= 280),
  -- Wie das Gespräch läuft (Video-Link, Telefonnummer oder Adresse).
  -- Sichtbar nur für Menschen, die einen Termin gebucht haben.
  gespraechsinfo  text not null default '' check (char_length(gespraechsinfo) <= 300),
  -- Für die Prüfung: z. B. Handelsregister-Nummer oder Kammer-Mitgliedsnummer
  nachweis        text not null default '' check (char_length(nachweis) <= 200),
  -- Erst wenn du hier "true" setzt, ist der Betrieb öffentlich sichtbar
  geprueft        boolean not null default false,
  erstellt        timestamptz not null default now()
);

-- Freie 10-Minuten-Termine der Betriebe
create table if not exists public.termine (
  id          uuid primary key default gen_random_uuid(),
  betrieb_id  uuid not null references public.betriebe (id) on delete cascade,
  beginn      timestamptz not null,
  unique (betrieb_id, beginn)
);

-- Buchungen (persönliche Daten: nur der Betrieb sieht sie)
create table if not exists public.buchungen (
  id                    uuid primary key default gen_random_uuid(),
  termin_id             uuid not null unique references public.termine (id) on delete cascade,
  vorname               text not null check (char_length(vorname) between 1 and 40),
  kontakt               text not null check (char_length(kontakt) between 5 and 80),
  rolle                 text not null check (rolle in ('schule','arbeitsuchend','umstieg')),
  kanal                 text not null check (kanal in ('video','telefon','vorort')),
  unter16               boolean not null default false,
  eltern_einverstanden  boolean not null default false,
  frage                 text not null default '' check (char_length(frage) <= 300),
  token                 uuid not null unique default gen_random_uuid(),
  erstellt              timestamptz not null default now()
);

create index if not exists termine_beginn_idx on public.termine (beginn);
create index if not exists termine_betrieb_idx on public.termine (betrieb_id);
create index if not exists buchungen_kontakt_idx on public.buchungen (lower(kontakt));

-- ---------------------------------------------------------------------
-- 2. Zugriffsrechte und Row Level Security
--    Niemand darf die Tabellen direkt lesen, außer Betriebe ihre eigenen
--    Einträge. Alles Öffentliche läuft über die Funktionen in Abschnitt 4.
-- ---------------------------------------------------------------------

-- Hilfsfunktionen in einem eigenen Schema, das nicht über die API erreichbar ist
create schema if not exists intern;
revoke all on schema intern from public;
grant usage on schema intern to authenticated;

create or replace function intern.ist_eigener_betrieb(p_betrieb uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.betriebe b where b.id = p_betrieb and b.owner = (select auth.uid()));
$$;
create or replace function intern.ist_eigener_termin(p_termin uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.termine t join public.betriebe b on b.id = t.betrieb_id
                 where t.id = p_termin and b.owner = (select auth.uid()));
$$;
create or replace function intern.termin_ist_gebucht(p_termin uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.buchungen x where x.termin_id = p_termin);
$$;
revoke all on function intern.ist_eigener_betrieb(uuid), intern.ist_eigener_termin(uuid), intern.termin_ist_gebucht(uuid) from public;
grant execute on function intern.ist_eigener_betrieb(uuid), intern.ist_eigener_termin(uuid), intern.termin_ist_gebucht(uuid) to authenticated;

alter table public.betriebe  enable row level security;
alter table public.termine   enable row level security;
alter table public.buchungen enable row level security;

revoke all on public.betriebe, public.termine, public.buchungen from anon, authenticated;

-- Betriebe: angemeldete Inhaber lesen, ändern und löschen nur ihre eigenen
grant select, delete on public.betriebe to authenticated;
grant insert (name, bereich, land, ort, berufe, erwachsene, kanaele, person, vorstellung, gespraechsinfo, nachweis) on public.betriebe to authenticated;
grant update (name, bereich, land, ort, berufe, erwachsene, kanaele, person, vorstellung, gespraechsinfo, nachweis) on public.betriebe to authenticated;

drop policy if exists "betriebe: eigene lesen" on public.betriebe;
drop policy if exists "betriebe: eigene anlegen" on public.betriebe;
drop policy if exists "betriebe: eigene ändern" on public.betriebe;
drop policy if exists "betriebe: eigene löschen" on public.betriebe;
create policy "betriebe: eigene lesen"   on public.betriebe for select to authenticated using (owner = (select auth.uid()));
create policy "betriebe: eigene anlegen" on public.betriebe for insert to authenticated with check (owner = (select auth.uid()));
create policy "betriebe: eigene ändern"  on public.betriebe for update to authenticated using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy "betriebe: eigene löschen" on public.betriebe for delete to authenticated using (owner = (select auth.uid()));

-- Termine: Inhaber legen Termine an, sehen sie und löschen freie Termine
grant select, delete on public.termine to authenticated;
grant insert (betrieb_id, beginn) on public.termine to authenticated;

drop policy if exists "termine: eigene lesen" on public.termine;
drop policy if exists "termine: eigene anlegen" on public.termine;
drop policy if exists "termine: freie eigene löschen" on public.termine;
create policy "termine: eigene lesen" on public.termine for select to authenticated
  using (intern.ist_eigener_betrieb(termine.betrieb_id));
create policy "termine: eigene anlegen" on public.termine for insert to authenticated
  with check (intern.ist_eigener_betrieb(termine.betrieb_id));
create policy "termine: freie eigene löschen" on public.termine for delete to authenticated
  using (intern.ist_eigener_betrieb(termine.betrieb_id) and not intern.termin_ist_gebucht(termine.id));

-- Buchungen: nur der Betrieb, dem der Termin gehört, sieht sie und kann absagen.
-- Die Spalte "token" bekommt der Betrieb bewusst nicht zu sehen.
grant select (id, termin_id, vorname, kontakt, rolle, kanal, unter16, eltern_einverstanden, frage, erstellt) on public.buchungen to authenticated;
grant delete on public.buchungen to authenticated;

drop policy if exists "buchungen: eigene lesen" on public.buchungen;
drop policy if exists "buchungen: eigene absagen" on public.buchungen;
create policy "buchungen: eigene lesen" on public.buchungen for select to authenticated
  using (intern.ist_eigener_termin(buchungen.termin_id));
create policy "buchungen: eigene absagen" on public.buchungen for delete to authenticated
  using (intern.ist_eigener_termin(buchungen.termin_id));

-- ---------------------------------------------------------------------
-- 3. Schutzregeln (Trigger)
-- ---------------------------------------------------------------------

-- Höchstens drei Betriebe pro Konto
create or replace function intern.pw_betrieb_limit() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (select count(*) from public.betriebe b where b.owner = new.owner) >= 3 then
    raise exception 'zu_viele_betriebe';
  end if;
  return new;
end;
$$;
drop trigger if exists pw_betrieb_limit on public.betriebe;
create trigger pw_betrieb_limit before insert on public.betriebe
  for each row execute function intern.pw_betrieb_limit();

-- Ändert ein Betrieb seine öffentlichen Angaben, wird er erneut geprüft
create or replace function intern.pw_betrieb_neu_pruefen() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.geprueft := old.geprueft;
    if (new.name, new.bereich, new.land, new.ort, new.berufe, new.person, new.vorstellung, new.gespraechsinfo)
       is distinct from
       (old.name, old.bereich, old.land, old.ort, old.berufe, old.person, old.vorstellung, old.gespraechsinfo) then
      new.geprueft := false;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists pw_betrieb_neu_pruefen on public.betriebe;
create trigger pw_betrieb_neu_pruefen before update on public.betriebe
  for each row execute function intern.pw_betrieb_neu_pruefen();

-- Termine nur in der Zukunft (höchstens 60 Tage) und höchstens 120 offene pro Betrieb
create or replace function intern.pw_termin_pruefen() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.beginn <= now() or new.beginn > now() + interval '60 days' then
    raise exception 'termin_zeitraum';
  end if;
  if (select count(*) from public.termine t where t.betrieb_id = new.betrieb_id and t.beginn > now()) >= 120 then
    raise exception 'zu_viele_termine';
  end if;
  return new;
end;
$$;
drop trigger if exists pw_termin_pruefen on public.termine;
create trigger pw_termin_pruefen before insert on public.termine
  for each row execute function intern.pw_termin_pruefen();

-- ---------------------------------------------------------------------
-- 4. Öffentliche Funktionen (für die Webseite)
-- ---------------------------------------------------------------------

-- Alle geprüften Betriebe (ohne Kontaktdaten und Nachweise)
create or replace function public.betriebe_oeffentlich()
returns table (id uuid, name text, bereich text, land text, ort text, berufe text[],
               erwachsene boolean, kanaele text[], person text, vorstellung text)
language sql stable security definer set search_path = '' as $$
  select b.id, b.name, b.bereich, b.land, b.ort, b.berufe, b.erwachsene, b.kanaele, b.person, b.vorstellung
  from public.betriebe b
  where b.geprueft
  order by b.erstellt;
$$;

-- Termine der nächsten 30 Tage, nur ob frei oder vergeben (keine Namen).
-- Räumt nebenbei alte Termine und Buchungen auf (14 Tage nach dem Termin).
create or replace function public.termine_oeffentlich()
returns table (id uuid, betrieb_id uuid, beginn timestamptz, gebucht boolean)
language plpgsql volatile security definer set search_path = '' as $$
begin
  delete from public.termine t where t.beginn < now() - interval '14 days';
  return query
    select t.id, t.betrieb_id, t.beginn,
           exists (select 1 from public.buchungen x where x.termin_id = t.id)
    from public.termine t
    join public.betriebe b on b.id = t.betrieb_id
    where b.geprueft and t.beginn > now() and t.beginn < now() + interval '30 days'
    order by t.beginn;
end;
$$;

-- Einen Termin buchen. Gibt einen geheimen Schlüssel (token) zurück,
-- mit dem die Person ihren Termin ansehen oder absagen kann.
create or replace function public.termin_buchen(
  p_termin uuid, p_vorname text, p_kontakt text, p_rolle text, p_kanal text,
  p_unter16 boolean, p_eltern_ok boolean, p_frage text, p_einwilligung boolean)
returns json
language plpgsql volatile security definer set search_path = '' as $$
declare
  r        record;
  v_token  uuid;
  v_aktiv  int;
begin
  if not coalesce(p_einwilligung, false) then raise exception 'einwilligung_fehlt'; end if;
  if coalesce(p_unter16, false) and not coalesce(p_eltern_ok, false) then raise exception 'eltern_fehlt'; end if;
  p_vorname := btrim(coalesce(p_vorname, ''));
  p_kontakt := btrim(coalesce(p_kontakt, ''));
  p_frage   := left(btrim(coalesce(p_frage, '')), 300);
  if char_length(p_vorname) not between 1 and 40 then raise exception 'vorname_ungueltig'; end if;
  if char_length(p_kontakt) not between 5 and 80 then raise exception 'kontakt_ungueltig'; end if;
  if coalesce(p_rolle, '') not in ('schule', 'arbeitsuchend', 'umstieg') then raise exception 'rolle_ungueltig'; end if;

  select t.id, t.beginn, b.name, b.kanaele, b.gespraechsinfo, b.geprueft
    into r
    from public.termine t
    join public.betriebe b on b.id = t.betrieb_id
   where t.id = p_termin
     for update of t;
  if not found or not r.geprueft then raise exception 'termin_unbekannt'; end if;
  if r.beginn <= now() then raise exception 'termin_vorbei'; end if;
  if p_kanal is null or not (p_kanal = any (r.kanaele)) then raise exception 'kanal_ungueltig'; end if;

  select count(*) into v_aktiv
    from public.buchungen x
    join public.termine y on y.id = x.termin_id
   where lower(x.kontakt) = lower(p_kontakt) and y.beginn > now();
  if v_aktiv >= 3 then raise exception 'zu_viele_buchungen'; end if;

  begin
    insert into public.buchungen (termin_id, vorname, kontakt, rolle, kanal, unter16, eltern_einverstanden, frage)
    values (p_termin, p_vorname, p_kontakt, p_rolle, p_kanal,
            coalesce(p_unter16, false), coalesce(p_unter16, false) and coalesce(p_eltern_ok, false), p_frage)
    returning token into v_token;
  exception when unique_violation then
    raise exception 'termin_vergeben';
  end;

  return json_build_object('token', v_token, 'termin_id', p_termin, 'betrieb', r.name, 'beginn', r.beginn,
                           'kanal', p_kanal, 'gespraechsinfo', r.gespraechsinfo);
end;
$$;

-- Eigene Termine ansehen (nur mit dem geheimen Schlüssel)
drop function if exists public.buchungen_ansehen(uuid[]);
create or replace function public.buchungen_ansehen(p_tokens uuid[])
returns table (token uuid, termin_id uuid, betrieb text, beginn timestamptz, kanal text, gespraechsinfo text)
language sql stable security definer set search_path = '' as $$
  select x.token, x.termin_id, b.name, t.beginn, x.kanal, b.gespraechsinfo
  from public.buchungen x
  join public.termine t on t.id = x.termin_id
  join public.betriebe b on b.id = t.betrieb_id
  where x.token = any (coalesce(p_tokens[1:20], '{}'::uuid[]))
  order by t.beginn;
$$;

-- Einen eigenen Termin absagen (nur mit dem geheimen Schlüssel)
create or replace function public.buchung_absagen(p_token uuid)
returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare
  n int;
begin
  delete from public.buchungen x
   using public.termine t
   where t.id = x.termin_id and x.token = p_token and t.beginn > now();
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

revoke all on function public.betriebe_oeffentlich() from public;
revoke all on function public.termine_oeffentlich() from public;
revoke all on function public.termin_buchen(uuid, text, text, text, text, boolean, boolean, text, boolean) from public;
revoke all on function public.buchungen_ansehen(uuid[]) from public;
revoke all on function public.buchung_absagen(uuid) from public;
revoke all on function intern.pw_betrieb_limit(), intern.pw_betrieb_neu_pruefen(), intern.pw_termin_pruefen() from public;

grant execute on function public.betriebe_oeffentlich() to anon, authenticated;
grant execute on function public.termine_oeffentlich() to anon, authenticated;
grant execute on function public.termin_buchen(uuid, text, text, text, text, boolean, boolean, text, boolean) to anon, authenticated;
grant execute on function public.buchungen_ansehen(uuid[]) to anon, authenticated;
grant execute on function public.buchung_absagen(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Jede Nacht automatisch aufräumen (Termine und Buchungen, die älter
--    als 14 Tage sind). Klappt das nicht, erscheint unten nur ein Hinweis.
--    Aufgeräumt wird dann trotzdem, sobald jemand die Seite öffnet.
-- ---------------------------------------------------------------------
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('platzwahl-aufraeumen', '17 3 * * *',
    $job$delete from public.termine where beginn < now() - interval '14 days'$job$);
exception when others then
  raise notice 'Nächtliches Aufräumen nicht eingerichtet: %', sqlerrm;
end
$$;

-- ---------------------------------------------------------------------
-- 6. Für dich als Betreiber (nicht ausführen, nur bei Bedarf kopieren):
--
-- Neue Betriebe ansehen, die auf Prüfung warten:
--   select name, ort, land, nachweis, erstellt from public.betriebe where not geprueft;
--
-- Einen Betrieb freischalten:
--   update public.betriebe set geprueft = true where name = 'Name des Betriebs';
--
-- Oder ganz ohne SQL: Table Editor > betriebe > Spalte "geprueft" auf true setzen.
-- ---------------------------------------------------------------------
