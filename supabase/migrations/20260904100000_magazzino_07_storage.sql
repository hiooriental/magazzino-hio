-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 7: archivio dei documenti fotografati
-- ============================================================================
--
--  Un solo bucket privato, con i file organizzati per organizzazione:
--
--      {organizzazione_id}/{documento_id}/{pagina}.jpg
--
--  La prima cartella non e' un dettaglio estetico: e' cio' su cui lavorano le
--  policy. Un utente puo' leggere e scrivere solo dentro le cartelle delle
--  organizzazioni di cui e' membro. Un bucket per cliente sarebbe stato
--  ingestibile a dieci clienti; una cartella per cliente si controlla con una
--  riga di policy.
--
--  Le foto non si cancellano quando si annulla un carico: il documento resta
--  come prova di cio' che e' stato registrato e poi stornato.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  Il bucket
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documenti-magazzino',
  'documenti-magazzino',
  false,                    -- privato: si accede solo con un token firmato
  15728640,                 -- 15 MB: una foto da telefono sta fra 2 e 8 MB
  array[
    'image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp',
    'application/pdf',
    'application/xml', 'text/xml'   -- per gli XML che arriveranno da Arca
  ]
)
on conflict (id) do update
set public             = excluded.public,
    file_size_limit    = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;


-- ----------------------------------------------------------------------------
--  Funzioni di percorso
-- ----------------------------------------------------------------------------

-- Estrae l'organizzazione dalla prima cartella del percorso.
-- Restituisce NULL se non e' un UUID valido, invece di far fallire la policy:
-- un file caricato con un nome storto deve risultare invisibile, non mandare
-- in errore la lettura di tutti gli altri.
create or replace function magazzino.org_da_percorso(p_percorso text)
returns uuid
language sql
immutable
as $$
  select case
    when split_part(coalesce(p_percorso, ''), '/', 1)
         ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then split_part(p_percorso, '/', 1)::uuid
  end;
$$;

-- Costruisce il percorso. Esiste perche' app Flutter ed edge function devono
-- usare la stessa convenzione senza doversi mettere d'accordo a parole.
create or replace function magazzino.percorso_allegato(
  p_organizzazione_id uuid,
  p_documento_id      uuid,
  p_pagina            smallint,
  p_estensione        text default 'jpg'
)
returns text
language sql
immutable
as $$
  select p_organizzazione_id::text || '/' ||
         p_documento_id::text || '/' ||
         lpad(p_pagina::text, 2, '0') || '.' ||
         lower(regexp_replace(coalesce(p_estensione, 'jpg'), '[^A-Za-z0-9]', '', 'g'));
$$;


-- ----------------------------------------------------------------------------
--  Policy sui file
-- ----------------------------------------------------------------------------
--  Se una di queste CREATE POLICY fallisce per permessi, si creano le stesse
--  regole dall'interfaccia Storage → Policies: il contenuto e' identico.

drop policy if exists "magazzino documenti lettura"      on storage.objects;
drop policy if exists "magazzino documenti caricamento"  on storage.objects;
drop policy if exists "magazzino documenti sostituzione" on storage.objects;
drop policy if exists "magazzino documenti rimozione"    on storage.objects;

create policy "magazzino documenti lettura"
on storage.objects for select to authenticated
using (
  bucket_id = 'documenti-magazzino'
  and magazzino.org_da_percorso(name) in (select magazzino.organizzazioni_utente())
);

-- Caricare puo' chiunque sia membro: e' il gesto quotidiano dell'operatore
-- che fotografa il DDT mentre scarica il furgone.
create policy "magazzino documenti caricamento"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'documenti-magazzino'
  and magazzino.org_da_percorso(name) in (select magazzino.organizzazioni_utente())
);

create policy "magazzino documenti sostituzione"
on storage.objects for update to authenticated
using (
  bucket_id = 'documenti-magazzino'
  and magazzino.org_da_percorso(name) in (select magazzino.organizzazioni_utente())
)
with check (
  bucket_id = 'documenti-magazzino'
  and magazzino.org_da_percorso(name) in (select magazzino.organizzazioni_utente())
);

-- Cancellare no: un documento fotografato e' la prova di cio' che e' stato
-- caricato in magazzino, e chi ha sbagliato non deve poter far sparire
-- l'originale. Solo titolare e gestore.
create policy "magazzino documenti rimozione"
on storage.objects for delete to authenticated
using (
  bucket_id = 'documenti-magazzino'
  and magazzino.ha_ruolo(magazzino.org_da_percorso(name), array['titolare','gestore'])
);


grant execute on function magazzino.org_da_percorso(text) to authenticated;
grant execute on function magazzino.percorso_allegato(uuid, uuid, smallint, text) to authenticated;
