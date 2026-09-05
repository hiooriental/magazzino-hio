-- ============================================================================
--  Collaudo del ciclo di apprendimento — non lascia traccia
-- ============================================================================
--
--  E' la prova piu' importante di tutta la Sezione 1, perche' verifica la
--  promessa su cui si regge il progetto: che il lavoro manuale si faccia UNA
--  VOLTA SOLA e poi sparisca.
--
--    Documento 1  → riga sconosciuta → l'operatore la abbina a mano
--    Documento 2  → stesso prodotto, scritto anche diversamente
--                 → riconosciuto da solo, senza AI e senza domande
--                 → confermato → la merce entra in magazzino
--
--  Usa i dati veri della fattura letta al collaudo precedente.
--  Tutto dentro BEGIN ... ROLLBACK.
-- ============================================================================

begin;

set local role authenticated;
-- Sostituire ID-UTENTE-QUI con il proprio identificativo, che si legge con:
--   select id, email from auth.users;
set local request.jwt.claims = '{"sub":"ID-UTENTE-QUI","role":"authenticated"}';


-- ════════════════════════════════════════════════════════════════════════════
--  DOCUMENTO 1 — il prodotto non l'ha mai visto nessuno
-- ════════════════════════════════════════════════════════════════════════════

insert into magazzino.documento_carico (
  id, organizzazione_id, tipo, origine, numero_documento,
  data_documento, data_consegna, totale_imponibile_testo, totale_documento_testo
)
values ('33333333-3333-4333-8333-333333333331',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
        'fattura', 'foto', 'PROVA-141/2026',
        current_date, current_date, '5.040,00', '6.148,80');

-- I numeri arrivano come stringhe, esattamente come li trascrive il modello.
insert into magazzino.documento_carico_riga (
  id, documento_id, numero_riga, descrizione_originale,
  codice_fornitore_originale, um_dichiarata,
  quantita_testo, prezzo_testo, totale_testo
)
values ('55555555-5555-4555-8555-555555555551',
        '33333333-3333-4333-8333-333333333331', 1,
        'CAPSULA COMPATIBILE NESPRESSO NERA', '01011316', 'PZ',
        '720.000,00', '0,007', '5.040,00');

-- Il fornitore non esiste: lo crea l'operatore confermando cio' che si legge.
select magazzino.crea_fornitore_da_documento(
  '33333333-3333-4333-8333-333333333331',
  'PROVA — Ideal Plastik Sud Srl',
  'IT99999999999'
);

-- L'unico gesto manuale di tutto il collaudo: "questo e' quell'ingrediente".
-- Nessun fattore di conversione: l'unita' e' PZ e l'ingrediente si misura in
-- pezzi, quindi converti_um() sa gia' rispondere da sola.
select magazzino.crea_ingrediente_da_riga(
  p_riga_id  => '55555555-5555-4555-8555-555555555551',
  p_nome     => 'PROVA — Capsula compatibile Nespresso nera',
  p_um_base  => 'pz'
);


-- ════════════════════════════════════════════════════════════════════════════
--  DOCUMENTO 2 — la volta dopo
-- ════════════════════════════════════════════════════════════════════════════

insert into magazzino.documento_carico (
  id, organizzazione_id, fornitore_id, tipo, origine, numero_documento,
  data_documento, data_consegna, totale_imponibile_testo
)
select '33333333-3333-4333-8333-333333333332',
       '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', f.id,
       'fattura', 'foto', 'PROVA-142/2026',
       current_date, current_date, '21,00'
from magazzino.fornitore f
where f.organizzazione_id = '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d'
  and f.partita_iva = '99999999999';

insert into magazzino.documento_carico_riga (
  documento_id, numero_riga, descrizione_originale,
  codice_fornitore_originale, um_dichiarata,
  quantita_testo, prezzo_testo, totale_testo
)
values
  -- Descrizione scritta in modo diverso, ma stesso codice fornitore.
  ('33333333-3333-4333-8333-333333333332', 1,
   'CAPS. COMPAT. NESPRESSO NERE', '01011316', 'PZ',
   '1.000,00', '0,007', '7,00'),

  -- Nessun codice, ma la descrizione e' identica a quella gia' confermata:
  -- deve riconoscerla tramite l'alias.
  ('33333333-3333-4333-8333-333333333332', 2,
   'CAPSULA COMPATIBILE NESPRESSO NERA', null, 'PZ',
   '2.000,00', '0,007', '14,00');

select magazzino.risolvi_documento('33333333-3333-4333-8333-333333333332');

-- Se il riconoscimento ha funzionato, questa passa senza intervento umano.
select magazzino.conferma_carico('33333333-3333-4333-8333-333333333332');


-- ════════════════════════════════════════════════════════════════════════════
--  VERIFICA
-- ════════════════════════════════════════════════════════════════════════════

with r1 as (
  select * from magazzino.documento_carico_riga
  where id = '55555555-5555-4555-8555-555555555551'
),
r2 as (
  select * from magazzino.documento_carico_riga
  where documento_id = '33333333-3333-4333-8333-333333333332'
),
esiti as (

  select 1 as n, 'fornitore creato' as controllo,
    coalesce(string_agg(denominazione, ', '), 'nessuno') as valore,
    case when count(*) = 1 then 'OK' else 'ERRORE' end as esito
  from magazzino.fornitore
  where partita_iva = '99999999999'

  union all
  -- La partita IVA letta come "IT99999999999" deve essere stata ripulita,
  -- altrimenti al prossimo documento nascerebbe un secondo fornitore.
  select 2, 'partita IVA normalizzata', partita_iva,
    case when partita_iva = '99999999999' then 'OK' else 'ERRORE: doveva perdere il prefisso IT' end
  from magazzino.fornitore where partita_iva = '99999999999'

  union all
  select 3, 'doc 1 — riga abbinata a mano',
    stato_match || ', metodo ' || coalesce(metodo_match, '-'),
    case when stato_match = 'confermato' and metodo_match = 'manuale'
         then 'OK' else 'ERRORE' end
  from r1

  union all
  select 4, 'doc 1 — quantita e costo',
    coalesce(quantita_base::text, '-') || ' pz a ' || coalesce(costo_unitario_base::text, '-'),
    case when quantita_base = 720000 and round(costo_unitario_base, 6) = 0.007000
         then 'OK' else 'ERRORE: attesi 720000 pz a 0,007' end
  from r1

  union all
  -- Il cuore della prova: descrizione diversa, riconosciuta dal codice.
  select 5, 'doc 2 riga 1 — riconosciuta dal codice',
    stato_match || ', metodo ' || coalesce(metodo_match, '-')
      || ', punteggio ' || coalesce(confidenza::text, '-'),
    case when stato_match = 'confermato' and metodo_match = 'codice_fornitore'
         then 'OK' else 'ERRORE: doveva bastare il codice' end
  from r2 where numero_riga = 1

  union all
  -- Nessun codice fornitore: deve riconoscerla dalla descrizione imparata
  -- col documento 1. Se la stringa e' identica vince `descrizione` (0,99),
  -- se differisce nella grafia vince `alias` (0,98): entrambe sono strade
  -- certe, e va bene qualunque delle due.
  select 6, 'doc 2 riga 2 — riconosciuta senza codice',
    stato_match || ', metodo ' || coalesce(metodo_match, '-')
      || ', punteggio ' || coalesce(confidenza::text, '-'),
    case when stato_match = 'confermato' and metodo_match in ('descrizione', 'alias')
         then 'OK' else 'ERRORE: doveva riconoscerla senza codice' end
  from r2 where numero_riga = 2

  union all
  select 7, 'doc 2 — confermato senza interventi', stato,
    case when stato = 'confermato' then 'OK' else 'ERRORE' end
  from magazzino.documento_carico
  where id = '33333333-3333-4333-8333-333333333332'

  union all
  -- 1000 + 2000 pezzi. Il documento 1 non e' stato confermato, quindi non
  -- deve aver mosso niente.
  select 8, 'giacenza dopo il carico',
    coalesce(sum(quantita)::text, '0') || ' pz',
    case when coalesce(sum(quantita), 0) = 3000 then 'OK'
         else 'ERRORE: attesi 3000 pz' end
  from magazzino.giacenza g
  join magazzino.ingrediente i on i.id = g.ingrediente_id
  where i.nome like 'PROVA — Capsula%'

  union all
  select 9, 'costo medio', coalesce(costo_medio::text, 'nullo') || ' €/pz',
    case when round(costo_medio, 6) = 0.007000 then 'OK' else 'ERRORE' end
  from magazzino.ingrediente where nome like 'PROVA — Capsula%'

  union all
  select 10, 'alias imparati', count(*)::text,
    case when count(*) = 2 then 'OK'
         else 'ATTENZIONE: attesi 2 (la grafia iniziale e quella del doc 2)' end
  from magazzino.alias_articolo a
  join magazzino.articolo_fornitore af on af.id = a.articolo_fornitore_id
  join magazzino.ingrediente i on i.id = af.ingrediente_id
  where i.nome like 'PROVA — Capsula%'

)
select n as "#", controllo, valore, esito from esiti order by n;

rollback;
