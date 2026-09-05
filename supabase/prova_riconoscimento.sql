-- ============================================================================
--  Collaudo del riconoscimento articoli — non lascia traccia
-- ============================================================================
--
--  Crea un articolo di prova (mazzancolle in cartoni da 5 kg) e gli sottopone
--  quattro righe scritte in modi diversi, per vedere quale strada prende il
--  riconoscimento e che numeri produce.
--
--  Alcuni controlli sono INFO e non OK/ERRORE: servono a leggere i punteggi
--  reali della somiglianza testuale, che dipendono da come sono scritte le
--  descrizioni e non si possono decidere a tavolino. Da quei numeri si capisce
--  se le soglie 0,90 / 0,55 sono tarate bene o vanno mosse.
--
--  Tutto dentro BEGIN ... ROLLBACK.
-- ============================================================================

begin;

set local role authenticated;
-- Sostituire ID-UTENTE-QUI con il proprio identificativo, che si legge con:
--   select id, email from auth.users;
set local request.jwt.claims = '{"sub":"ID-UTENTE-QUI","role":"authenticated"}';


-- ── Anagrafica di prova ─────────────────────────────────────────────────────

insert into magazzino.fornitore (id, organizzazione_id, denominazione)
values ('11111111-1111-4111-8111-111111111111',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'PROVA — Ittica');

insert into magazzino.ingrediente (id, organizzazione_id, nome, um_base, conservazione)
values ('22222222-2222-4222-8222-222222222222',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
        'PROVA — Mazzancolle giganti', 'g', 'frigo');

-- Un cartone contiene 5 kg = 5000 g.
insert into magazzino.articolo_fornitore (
  id, organizzazione_id, fornitore_id, ingrediente_id,
  codice_fornitore, descrizione_originale, um_acquisto, fattore_conversione
)
values ('44444444-4444-4444-8444-444444444444',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
        'MAZ001', 'MAZZANCOLLE GIGANTI CARTONE 5 KG', 'CT', 5000);


-- ── Un documento con quattro righe scritte in modi diversi ──────────────────

insert into magazzino.documento_carico (
  id, organizzazione_id, fornitore_id, tipo, origine,
  numero_documento, data_documento, data_consegna
)
values ('33333333-3333-4333-8333-333333333333',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
        '11111111-1111-4111-8111-111111111111',
        'ddt', 'foto', 'PROVA-2', current_date, current_date);

insert into magazzino.documento_carico_riga (
  documento_id, numero_riga, descrizione_originale, codice_fornitore_originale,
  quantita_dichiarata, um_dichiarata, totale_riga
)
values
  -- 1. Descrizione illeggibile ma codice esatto: deve vincere il codice.
  ('33333333-3333-4333-8333-333333333333', 1,
   'MAZZANC. GIG. CT/5', 'MAZ001', 2, 'CT', 180.00),

  -- 2. Nessun codice, descrizione simile ma non identica: solo somiglianza.
  ('33333333-3333-4333-8333-333333333333', 2,
   'MAZZANCOLLE GIGANTI CT 5KG', null, 1, 'CT', 92.00),

  -- 3. Prodotto mai visto: non deve inventarsi niente.
  ('33333333-3333-4333-8333-333333333333', 3,
   'GAMBERI ROSSI DI MAZARA', null, 1, 'CT', 145.00),

  -- 4. Codice esatto ma venduto a peso: l'unita' del documento (KG) deve
  --    prevalere sul fattore del cartone, altrimenti caricherebbe 17,5 tonnellate.
  ('33333333-3333-4333-8333-333333333333', 4,
   'MAZZANCOLLE SFUSE', 'MAZ001', 3.5, 'KG', 210.00);


-- ── Il riconoscimento ───────────────────────────────────────────────────────

select magazzino.risolvi_documento('33333333-3333-4333-8333-333333333333');


-- ── Verifica ────────────────────────────────────────────────────────────────

with r as (
  select * from magazzino.documento_carico_riga
  where documento_id = '33333333-3333-4333-8333-333333333333'
),
esiti as (

  select 1 as n, 'riga 1 — codice esatto' as controllo,
    coalesce(metodo_match, 'nessuno') || ', punteggio ' || coalesce(confidenza::text, '-') as valore,
    case when metodo_match = 'codice_fornitore' and confidenza = 1
         then 'OK' else 'ERRORE: doveva vincere il codice' end as esito
  from r where numero_riga = 1

  union all
  select 2, 'riga 1 — quantita e costo',
    coalesce(quantita_base::text, '-') || ' g a ' || coalesce(costo_unitario_base::text, '-') || ' €/g',
    case when quantita_base = 10000 and round(costo_unitario_base, 6) = 0.018000
         then 'OK' else 'ERRORE: attesi 10000 g a 0,018 €/g' end
  from r where numero_riga = 1

  union all
  -- Quanto vale davvero la somiglianza fra due scritture diverse dello stesso
  -- prodotto. Se questo numero e' sotto 0,55 la riga finisce fra quelle da
  -- risolvere a mano, ed e' li' che entrera' l'AI.
  select 3, 'riga 2 — solo somiglianza',
    coalesce(metodo_match, 'nessuno') || ', punteggio ' || coalesce(confidenza::text, '-')
      || ', stato ' || stato_match,
    'INFO: leggere il punteggio per tarare le soglie'
  from r where numero_riga = 2

  union all
  select 4, 'riga 3 — prodotto sconosciuto',
    stato_match || ', punteggio ' || coalesce(confidenza::text, '-'),
    case when stato_match = 'da_risolvere' and ingrediente_id is null
         then 'OK' else 'ERRORE: non doveva abbinare niente' end
  from r where numero_riga = 3

  union all
  select 5, 'riga 4 — KG batte il cartone',
    'fattore ' || coalesce(fattore_conversione_applicato::text, '-')
      || ' → ' || coalesce(quantita_base::text, '-') || ' g',
    case when fattore_conversione_applicato = 1000 and quantita_base = 3500
         then 'OK' else 'ERRORE: attesi 3500 g con fattore 1000' end
  from r where numero_riga = 4

  union all
  select 6, 'copertura automatica',
    count(*) filter (where stato_match = 'confermato')::text || ' su ' || count(*)::text || ' righe',
    'INFO: e'' il numero che deve salire col tempo'
  from r

)
select n as "#", controllo, valore, esito from esiti order by n;

rollback;
