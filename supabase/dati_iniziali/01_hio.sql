-- ============================================================================
--  Dati iniziali — HIO Oriental
-- ============================================================================
--
--  NON e' una migrazione: sono dati, non struttura. Sta qui e non in
--  `migrations/` apposta, con la stessa logica della cartella
--  `supabase/manutenzione/` di restaurant-booking. Si esegue a mano, una volta,
--  dopo le quattro migrazioni. Un secondo cliente avra' il suo file, non
--  questo.
--
--  Idempotente: si puo' rieseguire senza fare danni.
-- ============================================================================

set search_path = magazzino, public;

-- ----------------------------------------------------------------------------
--  L'organizzazione
-- ----------------------------------------------------------------------------
insert into magazzino.organizzazione (id, nome, ragione_sociale)
values ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'HIO Oriental', null)
on conflict (id) do nothing;


-- ----------------------------------------------------------------------------
--  Il magazzino
-- ----------------------------------------------------------------------------
--  Uno solo, per scelta: la merce si organizza per categoria di prodotto, non
--  per luogo fisico. La tabella `deposito` resta comunque nello schema e ogni
--  movimento la referenzia: il giorno in cui servisse separare il bar dalla
--  cucina bastera' aggiungere una riga, senza toccare ne' le tabelle ne' le
--  query gia' scritte.
insert into magazzino.deposito
  (organizzazione_id, codice, nome, tipo, ordinamento)
values
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'principale', 'Magazzino', 'ambiente', 0)
on conflict (organizzazione_id, codice) do nothing;


-- ----------------------------------------------------------------------------
--  Categorie di partenza
-- ----------------------------------------------------------------------------
--  Tagliate sul menu reale: le prime cinque coprono il crudo e il costoso,
--  le ultime quattro il bar, che da voi e' quasi due terzi delle referenze.
insert into magazzino.categoria_ingrediente (organizzazione_id, nome, ordinamento)
values
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Pesce per crudo',        10),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Pesce e crostacei',      20),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Carne',                  30),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Riso e cereali',         40),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Verdura e frutta',       50),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Latticini e uova',       60),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Salse e condimenti',     70),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Dispensa e secchi',      80),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Surgelati',              90),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Distillati',            100),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Vini e spumanti',       110),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Birre e bevande',       120),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bitter, sciroppi, mixer',130),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Dessert e pasticceria', 140),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Materiale di consumo',  150)
on conflict (organizzazione_id, nome) do nothing;


-- ----------------------------------------------------------------------------
--  Il primo utente
-- ----------------------------------------------------------------------------
--  Da eseguire dopo esserti registrato nell'app (o riusando l'utenza che gia'
--  usi per le prenotazioni: e' lo stesso auth.users).
--  Sostituisci l'indirizzo e togli il commento.
--
--  Senza questa riga NON VEDI NIENTE, nemmeno da titolare: la RLS filtra su
--  `utente_organizzazione`, e finche' e' vuota ogni query torna zero righe.
--  Non e' un errore, e' il comportamento voluto.
--
-- insert into magazzino.utente_organizzazione (utente_id, organizzazione_id, ruolo)
-- select u.id, '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'titolare'
-- from auth.users u
-- where u.email = 'tua@email.it'
-- on conflict (utente_id, organizzazione_id) do update set ruolo = 'titolare', attivo = true;
