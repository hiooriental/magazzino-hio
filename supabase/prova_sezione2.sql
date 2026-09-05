-- ============================================================================
--  Collaudo della Sezione 2 — non lascia traccia
-- ============================================================================
--
--  Il giro completo di una giornata vera:
--
--    1. Rimanenze iniziali: riso, aceto, un loin di tonno da 8,4 kg
--    2. PRODUZIONE  — 5 kg di riso + 0,5 l di aceto → 8,7 kg di riso condito
--                     (il peso AUMENTA: il riso assorbe acqua)
--    3. DISASSEMBLAGGIO — 8,4 kg di tonno → 3,1 tagliata + 2,4 tartare
--                     + 1,6 sashimi, 1,3 di scarto. Resa 84,5%.
--    4. RICETTA     — Tagliata di tonno: 180 g di trancio + 50 g di riso
--    5. VENDITA     — due tagliate, scaricate dal magazzino
--
--  Il controllo più importante è il numero 4: la somma dei costi ripartiti
--  sui tagli deve fare ESATTAMENTE il costo del pezzo intero. Se ne perde
--  per strada, ogni piatto di pesce costa meno di quanto costa davvero.
--
--  Prima di eseguire, sostituire ID-UTENTE-QUI (select id, email from auth.users).
--  Tutto dentro BEGIN ... ROLLBACK.
-- ============================================================================

begin;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ID-UTENTE-QUI","role":"authenticated"}';


-- ════════════════════════════════════════════════════════════════════════════
--  1. Materie prime in casa
-- ════════════════════════════════════════════════════════════════════════════

insert into magazzino.ingrediente (id, organizzazione_id, nome, um_base, conservazione)
values
  ('a0000000-0000-4000-8000-000000000001','7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d','PROVA — Riso per sushi','g','ambiente'),
  ('a0000000-0000-4000-8000-000000000002','7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d','PROVA — Aceto di riso','ml','ambiente');

insert into magazzino.ingrediente (id, organizzazione_id, nome, um_base, conservazione, richiede_abbattimento, gestisci_lotti)
values
  ('a0000000-0000-4000-8000-000000000003','7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d','PROVA — Tonno loin intero','g','frigo',true,true);

-- I semilavorati: prodotti in casa, non comprati.
insert into magazzino.ingrediente (id, organizzazione_id, nome, um_base, conservazione, prodotto_internamente, gestisci_lotti)
values
  ('a0000000-0000-4000-8000-000000000010','7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d','PROVA — Riso condito','g','frigo',true,true),
  ('a0000000-0000-4000-8000-000000000011','7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d','PROVA — Tonno trancio tagliata','g','frigo',true,true),
  ('a0000000-0000-4000-8000-000000000012','7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d','PROVA — Tonno per tartare','g','frigo',true,true),
  ('a0000000-0000-4000-8000-000000000013','7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d','PROVA — Tonno per sashimi','g','frigo',true,true);

-- Rimanenze iniziali, con i loro costi.
insert into magazzino.movimento
  (organizzazione_id, ingrediente_id, deposito_id, causale_codice, quantita, costo_unitario, data_competenza)
select '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', x.ing,
       (select id from magazzino.deposito
         where organizzazione_id = '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d' and attivo
         order by ordinamento limit 1),
       'rimanenza_iniziale', x.qta, x.costo, current_date
from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 20000::numeric, 0.002::numeric),
  ('a0000000-0000-4000-8000-000000000002'::uuid,  5000::numeric, 0.004::numeric),
  ('a0000000-0000-4000-8000-000000000003'::uuid,  8400::numeric, 0.058::numeric)
) as x(ing, qta, costo);

select magazzino.aggiorna_costo_medio('a0000000-0000-4000-8000-000000000001', 20000, 0.002);
select magazzino.aggiorna_costo_medio('a0000000-0000-4000-8000-000000000002',  5000, 0.004);
select magazzino.aggiorna_costo_medio('a0000000-0000-4000-8000-000000000003',  8400, 0.058);


-- ════════════════════════════════════════════════════════════════════════════
--  2. PRODUZIONE — il riso condito
-- ════════════════════════════════════════════════════════════════════════════
--  5000 × 0,002 + 500 × 0,004 = 10,00 + 2,00 = 12,00 €
--  su 8700 g prodotti → 0,00137931 €/g

insert into magazzino.distinta
  (id, organizzazione_id, ingrediente_id, stato, quantita_prodotta)
values ('b0000000-0000-4000-8000-000000000001',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
        'a0000000-0000-4000-8000-000000000010', 'attiva', 8700);

insert into magazzino.distinta_componente (distinta_id, ingrediente_id, quantita)
values
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',5000),
  ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002', 500);

insert into magazzino.lavorazione (id, organizzazione_id, tipo, distinta_id)
values ('c0000000-0000-4000-8000-000000000001',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'produzione',
        'b0000000-0000-4000-8000-000000000001');

insert into magazzino.lavorazione_input (lavorazione_id, ingrediente_id, quantita)
values
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',5000),
  ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002', 500);

insert into magazzino.lavorazione_output (lavorazione_id, ingrediente_id, quantita)
values ('c0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000010',8700);

select magazzino.chiudi_lavorazione('c0000000-0000-4000-8000-000000000001');


-- ════════════════════════════════════════════════════════════════════════════
--  3. DISASSEMBLAGGIO — il loin di tonno
-- ════════════════════════════════════════════════════════════════════════════
--  Costo del pezzo: 8400 × 0,058 = 487,20 €
--  Ripartizione a valore — tagliata 3, tartare 2, sashimi 3:
--    base = 3100×3 + 2400×2 + 1600×3 = 18900
--    tagliata = 487,20 × 3 / 18900 = 0,0773333 €/g
--    tartare  = 487,20 × 2 / 18900 = 0,0515556 €/g
--  Scarto 1300 g: non è una riga di output, il suo costo si spalma sui tagli.

insert into magazzino.lavorazione (id, organizzazione_id, tipo, ripartizione)
values ('c0000000-0000-4000-8000-000000000002',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'disassemblaggio', 'valore');

insert into magazzino.lavorazione_input (lavorazione_id, ingrediente_id, quantita)
values ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000003',8400);

insert into magazzino.lavorazione_output (lavorazione_id, ingrediente_id, quantita, valore_relativo)
values
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000011',3100,3),
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000012',2400,2),
  ('c0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000013',1600,3);

select magazzino.chiudi_lavorazione('c0000000-0000-4000-8000-000000000002');


-- ════════════════════════════════════════════════════════════════════════════
--  4. RICETTA e VENDITA
-- ════════════════════════════════════════════════════════════════════════════

insert into magazzino.prodotto_venduto
  (id, organizzazione_id, codice_esterno, nome, categoria_menu, prezzo_vendita)
values ('d0000000-0000-4000-8000-000000000001',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'POS-901',
        'PROVA — Tagliata di tonno', 'SECONDI', 32.00);

insert into magazzino.distinta (id, organizzazione_id, prodotto_venduto_id, stato)
values ('b0000000-0000-4000-8000-000000000002',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
        'd0000000-0000-4000-8000-000000000001', 'attiva');

insert into magazzino.distinta_componente (distinta_id, ingrediente_id, quantita)
values
  ('b0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000011',180),
  ('b0000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000010', 50);

insert into magazzino.vendita
  (id, organizzazione_id, origine, codice_esterno, data_vendita, coperti, totale)
values ('e0000000-0000-4000-8000-000000000001',
        '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'ipratico', 'SC-PROVA-1',
        current_date, 2, 64.00);

-- Il codice arriva dalla cassa: il prodotto lo aggancia `risolvi_vendita`.
insert into magazzino.vendita_riga
  (vendita_id, codice_esterno, descrizione, quantita, prezzo_unitario, totale_riga)
values ('e0000000-0000-4000-8000-000000000001', 'POS-901',
        'Tagliata di tonno', 2, 32.00, 64.00);

select magazzino.risolvi_vendita('e0000000-0000-4000-8000-000000000001');
select magazzino.scarica_vendita('e0000000-0000-4000-8000-000000000001');


-- ════════════════════════════════════════════════════════════════════════════
--  VERIFICA
-- ════════════════════════════════════════════════════════════════════════════

with g as (
  select ingrediente_id, sum(quantita) as q from magazzino.giacenza group by 1
),
esiti as (

  select 1 as n, 'produzione — riso condito prodotto' as controllo,
    coalesce(round(q,0)::text,'0') || ' g' as valore,
    -- 8700 prodotti meno 100 usciti con la vendita
    case when round(q,0) = 8600 then 'OK' else 'ERRORE: attesi 8600 g' end as esito
  from g where ingrediente_id = 'a0000000-0000-4000-8000-000000000010'

  union all
  select 2, 'produzione — costo del riso condito',
    coalesce(round(costo_medio,8)::text,'-') || ' €/g',
    -- 12,00 € su 8700 g
    case when round(costo_medio, 6) = round(12.0/8700, 6)
         then 'OK' else 'ERRORE: attesi 0,001379 €/g' end
  from magazzino.ingrediente where id = 'a0000000-0000-4000-8000-000000000010'

  union all
  select 3, 'produzione — materie prime consumate',
    coalesce(round((select q from g where ingrediente_id='a0000000-0000-4000-8000-000000000001'),0)::text,'-')
      || ' g di riso rimasti',
    case when (select round(q,0) from g where ingrediente_id='a0000000-0000-4000-8000-000000000001') = 15000
         then 'OK' else 'ERRORE: attesi 15000 g' end

  union all
  -- IL CONTROLLO CHIAVE: nessun euro si perde nella ripartizione.
  select 4, 'disassemblaggio — il costo si conserva',
    coalesce(round(sum(o.quantita * o.costo_unitario), 2)::text,'-') || ' € ripartiti su 487,20 € entrati',
    case when round(sum(o.quantita * o.costo_unitario), 2) = 487.20
         then 'OK' else 'ERRORE: costo perso o inventato nella ripartizione' end
  from magazzino.lavorazione_output o
  where o.lavorazione_id = 'c0000000-0000-4000-8000-000000000002'

  union all
  select 5, 'disassemblaggio — costo della tagliata',
    coalesce(round(costo_unitario, 7)::text,'-') || ' €/g',
    case when round(costo_unitario, 6) = round(487.20*3/18900, 6)
         then 'OK' else 'ERRORE: attesi 0,077333 €/g' end
  from magazzino.lavorazione_output
  where lavorazione_id = 'c0000000-0000-4000-8000-000000000002'
    and ingrediente_id = 'a0000000-0000-4000-8000-000000000011'

  union all
  select 6, 'disassemblaggio — la tartare vale meno',
    coalesce(round(costo_unitario, 7)::text,'-') || ' €/g',
    case when round(costo_unitario, 6) = round(487.20*2/18900, 6)
         then 'OK' else 'ERRORE: attesi 0,051556 €/g' end
  from magazzino.lavorazione_output
  where lavorazione_id = 'c0000000-0000-4000-8000-000000000002'
    and ingrediente_id = 'a0000000-0000-4000-8000-000000000012'

  union all
  select 7, 'disassemblaggio — resa',
    coalesce(resa_percentuale::text,'-') || '%',
    -- 7100 su 8400
    case when resa_percentuale = 84.5 then 'OK' else 'ERRORE: attesa 84,5%' end
  from magazzino.resa_lavorazione
  where id = 'c0000000-0000-4000-8000-000000000002'

  union all
  select 8, 'disassemblaggio — il pezzo intero è uscito',
    coalesce(round(coalesce(q,0),0)::text,'0') || ' g',
    case when coalesce(q,0) = 0 then 'OK' else 'ERRORE: doveva azzerarsi' end
  from (select 1) z
  left join g on g.ingrediente_id = 'a0000000-0000-4000-8000-000000000003'

  union all
  select 9, 'tracciabilità — il trancio ricorda il tonno',
    case when l.lotto_origine_id is not null then 'lotto di origine collegato' else 'nessun collegamento' end,
    case when l.lotto_origine_id is not null then 'OK' else 'ERRORE: catena interrotta' end
  from magazzino.lotto l
  where l.ingrediente_id = 'a0000000-0000-4000-8000-000000000011'
  limit 1

  union all
  select 10, 'food cost — costo della tagliata',
    coalesce(round(costo, 4)::text,'-') || ' € su 32,00 € di prezzo',
    -- 180 × 0,0773333 + 50 × 0,00137931 = 13,92 + 0,069 = 13,989
    case when round(costo, 2) = 13.99 then 'OK' else 'ERRORE: attesi 13,99 €' end
  from magazzino.food_cost
  where prodotto_id = 'd0000000-0000-4000-8000-000000000001'

  union all
  select 11, 'food cost — incidenza',
    coalesce(incidenza_percentuale::text,'-') || '%',
    case when incidenza_percentuale between 43 and 44 then 'OK'
         else 'ERRORE: attesa intorno al 43,7%' end
  from magazzino.food_cost
  where prodotto_id = 'd0000000-0000-4000-8000-000000000001'

  union all
  select 12, 'vendita — scarico del trancio',
    coalesce(round(q,0)::text,'-') || ' g rimasti',
    -- 3100 prodotti meno 2 × 180
    case when round(q,0) = 2740 then 'OK' else 'ERRORE: attesi 2740 g' end
  from g where ingrediente_id = 'a0000000-0000-4000-8000-000000000011'

  union all
  select 13, 'vendita — prodotto riconosciuto dal codice cassa',
    coalesce(v.stato,'-'),
    case when v.stato = 'scaricata' then 'OK' else 'ERRORE' end
  from magazzino.vendita v where v.id = 'e0000000-0000-4000-8000-000000000001'

  union all
  select 14, 'niente resta da collegare',
    count(*)::text || ' prodotti senza ricetta',
    case when count(*) = 0 then 'OK' else 'ATTENZIONE: ci sono prodotti da collegare' end
  from magazzino.prodotti_da_collegare
  where descrizione like 'Tagliata%'

)
select n as "#", controllo, valore, esito from esiti order by n;

rollback;
