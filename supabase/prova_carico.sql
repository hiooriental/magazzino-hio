-- ============================================================================
--  Collaudo di conferma_carico — non lascia traccia
-- ============================================================================
--
--  Simula il carico di un loin di tonno da 8,4 kg a 58 €/kg e verifica che
--  tutta la catena si sia mossa: movimento, lotto, giacenza, costo medio,
--  storico prezzi, stato del documento.
--
--  Tutto dentro BEGIN ... ROLLBACK: alla fine il database e' esattamente
--  com'era. Necessario perche' il libro mastro e' a sola aggiunta e i
--  movimenti di prova non si potrebbero cancellare dopo.
--
--  `set local role` + `request.jwt.claims` servono a farsi passare per
--  l'utente admin: senza, auth.uid() sarebbe nullo e la funzione rifiuterebbe
--  giustamente di confermare.
--
--  Si esegue tutto insieme. Ultima riga attesa: 6 controlli, tutti OK.
-- ============================================================================

begin;

set local role authenticated;
-- Sostituire ID-UTENTE-QUI con il proprio identificativo, che si legge con:
--   select id, email from auth.users;
set local request.jwt.claims = '{"sub":"ID-UTENTE-QUI","role":"authenticated"}';


-- ── Dati finti ──────────────────────────────────────────────────────────────

insert into magazzino.fornitore (id, organizzazione_id, denominazione, partita_iva)
values (
  '11111111-1111-4111-8111-111111111111',
  '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
  'PROVA — Ittica', '99999999999'
);

-- richiede_abbattimento = true, quindi la conferma deve generare un lotto.
insert into magazzino.ingrediente (
  id, organizzazione_id, nome, um_base, conservazione, richiede_abbattimento
)
values (
  '22222222-2222-4222-8222-222222222222',
  '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
  'PROVA — Tonno rosso loin', 'g', 'frigo', true
);

insert into magazzino.documento_carico (
  id, organizzazione_id, fornitore_id, tipo, origine,
  numero_documento, data_documento, data_consegna, totale_dichiarato
)
values (
  '33333333-3333-4333-8333-333333333333',
  '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
  '11111111-1111-4111-8111-111111111111',
  'ddt', 'manuale', 'PROVA-1', current_date, current_date, 487.20
);

-- 8,4 kg = 8400 g. 487,20 / 8400 = 0,058 €/g, cioe' 58 €/kg.
insert into magazzino.documento_carico_riga (
  documento_id, numero_riga, descrizione_originale,
  quantita_dichiarata, um_dichiarata, prezzo_unitario, totale_riga,
  ingrediente_id, quantita_base, costo_unitario_base,
  stato_match, metodo_match, confidenza
)
values (
  '33333333-3333-4333-8333-333333333333', 1, 'TONNO ROSSO LOIN KG 8,4',
  8.4, 'KG', 58.00, 487.20,
  '22222222-2222-4222-8222-222222222222', 8400, 0.058,
  'suggerito', 'ai', 0.95
);


-- ── La conferma ─────────────────────────────────────────────────────────────

select magazzino.conferma_carico('33333333-3333-4333-8333-333333333333');


-- ── Verifica ────────────────────────────────────────────────────────────────

with esiti as (

  select 1 as n, 'documento confermato' as controllo,
    stato as valore,
    case when stato = 'confermato' then 'OK' else 'ERRORE' end as esito
  from magazzino.documento_carico
  where id = '33333333-3333-4333-8333-333333333333'

  union all
  select 2, 'movimento creato',
    coalesce(sum(quantita)::text, 'nessuno'),
    case when coalesce(sum(quantita), 0) = 8400 then 'OK'
         else 'ERRORE: attesi 8400 g' end
  from magazzino.movimento
  where ingrediente_id = '22222222-2222-4222-8222-222222222222'

  union all
  -- richiede_abbattimento: il lotto deve esserci, e nascere non abbattuto.
  -- L'abbattimento e' un gesto successivo alla consegna, non una condizione
  -- per accettare la merce.
  select 3, 'lotto generato',
    coalesce(string_agg(codice || ' (abbattuto: ' || abbattuto || ')', ', '), 'nessuno'),
    case when count(*) = 1 then 'OK' else 'ERRORE: atteso 1 lotto' end
  from magazzino.lotto
  where ingrediente_id = '22222222-2222-4222-8222-222222222222'

  union all
  select 4, 'giacenza',
    coalesce(sum(quantita)::text, '0') || ' g',
    case when coalesce(sum(quantita), 0) = 8400 then 'OK' else 'ERRORE' end
  from magazzino.giacenza
  where ingrediente_id = '22222222-2222-4222-8222-222222222222'

  union all
  select 5, 'costo medio',
    coalesce(costo_medio::text, 'nullo') || ' €/g',
    case when round(costo_medio, 6) = 0.058000 then 'OK'
         else 'ERRORE: attesi 0,058 €/g' end
  from magazzino.ingrediente
  where id = '22222222-2222-4222-8222-222222222222'

  union all
  select 6, 'storico prezzo',
    coalesce(count(*)::text, '0') || ' rilevazioni',
    case when count(*) = 1 then 'OK' else 'ERRORE: attesa 1' end
  from magazzino.storico_prezzo
  where ingrediente_id = '22222222-2222-4222-8222-222222222222'

)
select n as "#", controllo, valore, esito from esiti order by n;


-- Nulla di tutto questo resta nel database.
rollback;
