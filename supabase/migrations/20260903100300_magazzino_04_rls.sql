-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 4 di 4: sicurezza a livello di riga
-- ============================================================================
--
--  Modello in una frase: si vede solo cio' che appartiene alle organizzazioni
--  di cui si e' membri attivi, e alcune azioni sono riservate ai ruoli alti.
--
--  Chi puo' fare cosa:
--
--    lettura              tutti i membri attivi
--    scrittura corrente   tutti i membri attivi
--    confermare un carico titolare, gestore   (l'operatore compila, non conferma)
--    chiudere inventario  titolare, gestore
--    cancellare           titolare, gestore
--    gestire i membri     titolare
--
--  `anon` non riceve nessun permesso: il magazzino non ha una faccia pubblica,
--  a differenza del modulo prenotazioni.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  Accesso allo schema
-- ----------------------------------------------------------------------------
grant usage on schema magazzino to authenticated, service_role;

grant select, insert, update, delete on all tables in schema magazzino to authenticated;
grant all on all tables in schema magazzino to service_role;
grant usage, select on all sequences in schema magazzino to authenticated, service_role;
grant execute on all functions in schema magazzino to authenticated, service_role;

-- Perche' valga anche per cio' che si creera' nelle migrazioni successive.
alter default privileges in schema magazzino
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema magazzino
  grant all on tables to service_role;
alter default privileges in schema magazzino
  grant usage, select on sequences to authenticated, service_role;
alter default privileges in schema magazzino
  grant execute on functions to authenticated, service_role;


-- ----------------------------------------------------------------------------
--  RLS attiva ovunque
-- ----------------------------------------------------------------------------
alter table magazzino.organizzazione         enable row level security;
alter table magazzino.utente_organizzazione  enable row level security;
alter table magazzino.deposito               enable row level security;
alter table magazzino.fornitore              enable row level security;
alter table magazzino.categoria_ingrediente  enable row level security;
alter table magazzino.allergene              enable row level security;
alter table magazzino.ingrediente            enable row level security;
alter table magazzino.ingrediente_allergene  enable row level security;
alter table magazzino.articolo_fornitore     enable row level security;
alter table magazzino.alias_articolo         enable row level security;
alter table magazzino.documento_carico       enable row level security;
alter table magazzino.documento_carico_riga  enable row level security;
alter table magazzino.allegato               enable row level security;
alter table magazzino.estrazione_ai          enable row level security;
alter table magazzino.causale                enable row level security;
alter table magazzino.lotto                  enable row level security;
alter table magazzino.movimento              enable row level security;
alter table magazzino.inventario             enable row level security;
alter table magazzino.inventario_riga        enable row level security;
alter table magazzino.storico_prezzo         enable row level security;


-- ----------------------------------------------------------------------------
--  Tabelle di sistema: lettura per tutti gli utenti collegati, scrittura solo
--  tramite migrazione (nessuna policy di scrittura = negata a chiunque non sia
--  service_role).
-- ----------------------------------------------------------------------------
create policy allergene_lettura on magazzino.allergene
  for select to authenticated using (true);

create policy causale_lettura on magazzino.causale
  for select to authenticated using (true);


-- ----------------------------------------------------------------------------
--  organizzazione e appartenenze
-- ----------------------------------------------------------------------------
create policy organizzazione_lettura on magazzino.organizzazione
  for select to authenticated
  using (id in (select magazzino.organizzazioni_utente()));

create policy organizzazione_modifica on magazzino.organizzazione
  for update to authenticated
  using (magazzino.ha_ruolo(id, array['titolare']))
  with check (magazzino.ha_ruolo(id, array['titolare']));

-- Ognuno vede le proprie appartenenze; il titolare vede quelle di tutti
-- nella sua organizzazione.
create policy utente_organizzazione_lettura on magazzino.utente_organizzazione
  for select to authenticated
  using (
    utente_id = auth.uid()
    or magazzino.ha_ruolo(organizzazione_id, array['titolare'])
  );

create policy utente_organizzazione_gestione on magazzino.utente_organizzazione
  for all to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare']))
  with check (magazzino.ha_ruolo(organizzazione_id, array['titolare']));


-- ----------------------------------------------------------------------------
--  Anagrafiche: lettura e scrittura ai membri, cancellazione ai ruoli alti
-- ----------------------------------------------------------------------------
--  Ripetitivo di proposito. Si potrebbe generare con un DO ... LOOP, ma
--  policy scritte a mano sono policy che si possono leggere una per una
--  quando si tratta di capire chi vede cosa.

-- deposito
create policy deposito_lettura on magazzino.deposito
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy deposito_inserimento on magazzino.deposito
  for insert to authenticated
  with check (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));
create policy deposito_modifica on magazzino.deposito
  for update to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']))
  with check (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));
create policy deposito_cancellazione on magazzino.deposito
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));

-- fornitore
create policy fornitore_lettura on magazzino.fornitore
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy fornitore_scrittura on magazzino.fornitore
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy fornitore_modifica on magazzino.fornitore
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy fornitore_cancellazione on magazzino.fornitore
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));

-- categoria_ingrediente
create policy categoria_lettura on magazzino.categoria_ingrediente
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy categoria_scrittura on magazzino.categoria_ingrediente
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy categoria_modifica on magazzino.categoria_ingrediente
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy categoria_cancellazione on magazzino.categoria_ingrediente
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));

-- ingrediente
create policy ingrediente_lettura on magazzino.ingrediente
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy ingrediente_scrittura on magazzino.ingrediente
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy ingrediente_modifica on magazzino.ingrediente
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy ingrediente_cancellazione on magazzino.ingrediente
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));

-- ingrediente_allergene: non ha organizzazione_id propria, la eredita
-- dall'ingrediente a cui appartiene.
create policy ingrediente_allergene_lettura on magazzino.ingrediente_allergene
  for select to authenticated
  using (exists (
    select 1 from magazzino.ingrediente i
    where i.id = ingrediente_id
      and i.organizzazione_id in (select magazzino.organizzazioni_utente())
  ));
create policy ingrediente_allergene_scrittura on magazzino.ingrediente_allergene
  for all to authenticated
  using (exists (
    select 1 from magazzino.ingrediente i
    where i.id = ingrediente_id
      and i.organizzazione_id in (select magazzino.organizzazioni_utente())
  ))
  with check (exists (
    select 1 from magazzino.ingrediente i
    where i.id = ingrediente_id
      and i.organizzazione_id in (select magazzino.organizzazioni_utente())
  ));

-- articolo_fornitore
create policy articolo_fornitore_lettura on magazzino.articolo_fornitore
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy articolo_fornitore_scrittura on magazzino.articolo_fornitore
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy articolo_fornitore_modifica on magazzino.articolo_fornitore
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy articolo_fornitore_cancellazione on magazzino.articolo_fornitore
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));

-- alias_articolo
create policy alias_lettura on magazzino.alias_articolo
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy alias_scrittura on magazzino.alias_articolo
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy alias_modifica on magazzino.alias_articolo
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy alias_cancellazione on magazzino.alias_articolo
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));


-- ----------------------------------------------------------------------------
--  Documenti di carico
-- ----------------------------------------------------------------------------
create policy documento_lettura on magazzino.documento_carico
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));

create policy documento_scrittura on magazzino.documento_carico
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));

-- Il passaggio a 'confermato' e' l'atto che muove il magazzino, e non e' di
-- chiunque. L'operatore puo' lavorare la bozza quanto vuole; per chiuderla
-- serve un gestore. Il WITH CHECK guarda la riga NUOVA, quindi blocca solo
-- l'ingresso in quello stato.
create policy documento_modifica on magazzino.documento_carico
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (
    organizzazione_id in (select magazzino.organizzazioni_utente())
    and (
      stato <> 'confermato'
      or magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore'])
    )
  );

create policy documento_cancellazione on magazzino.documento_carico
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));

-- documento_carico_riga
create policy documento_riga_lettura on magazzino.documento_carico_riga
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy documento_riga_scrittura on magazzino.documento_carico_riga
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy documento_riga_modifica on magazzino.documento_carico_riga
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy documento_riga_cancellazione on magazzino.documento_carico_riga
  for delete to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));

-- allegato
create policy allegato_lettura on magazzino.allegato
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy allegato_scrittura on magazzino.allegato
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy allegato_cancellazione on magazzino.allegato
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));

-- estrazione_ai: si legge e si inserisce. Modifica e cancellazione non hanno
-- policy, e in piu' c'e' il trigger: doppia serratura, voluta.
create policy estrazione_lettura on magazzino.estrazione_ai
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy estrazione_scrittura on magazzino.estrazione_ai
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));


-- ----------------------------------------------------------------------------
--  Lotti e movimenti
-- ----------------------------------------------------------------------------
create policy lotto_lettura on magazzino.lotto
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy lotto_scrittura on magazzino.lotto
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy lotto_modifica on magazzino.lotto
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));

-- Nessuna policy di UPDATE o DELETE sui movimenti: il libro mastro e' a sola
-- aggiunta anche dal punto di vista dei permessi, non solo del trigger.
create policy movimento_lettura on magazzino.movimento
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy movimento_scrittura on magazzino.movimento
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));


-- ----------------------------------------------------------------------------
--  Inventari
-- ----------------------------------------------------------------------------
create policy inventario_lettura on magazzino.inventario
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy inventario_scrittura on magazzino.inventario
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));

-- Come per i documenti: contare lo puo' fare chiunque, chiudere no.
-- La chiusura genera le rettifiche, quindi muove il magazzino.
create policy inventario_modifica on magazzino.inventario
  for update to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (
    organizzazione_id in (select magazzino.organizzazioni_utente())
    and (
      stato <> 'chiuso'
      or magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore'])
    )
  );

create policy inventario_cancellazione on magazzino.inventario
  for delete to authenticated
  using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));

create policy inventario_riga_lettura on magazzino.inventario_riga
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy inventario_riga_scrittura on magazzino.inventario_riga
  for all to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()))
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));


-- ----------------------------------------------------------------------------
--  Storico prezzi: si legge e si aggiunge, non si riscrive
-- ----------------------------------------------------------------------------
create policy storico_prezzo_lettura on magazzino.storico_prezzo
  for select to authenticated
  using (organizzazione_id in (select magazzino.organizzazioni_utente()));
create policy storico_prezzo_scrittura on magazzino.storico_prezzo
  for insert to authenticated
  with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
