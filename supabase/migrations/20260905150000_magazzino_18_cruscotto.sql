-- ============================================================================
--  MAGAZZINO HIO — Sezione 2, file 18: inventario, scorte e cruscotto
-- ============================================================================
--
--  Chiude il cerchio: il magazzino sa cosa è entrato (carichi), cosa si è
--  trasformato (lavorazioni) e cosa è uscito (vendite). Manca il confronto
--  con la realtà — l'inventario — e i numeri che servono a decidere stasera:
--  cosa sta finendo, cosa scade, cosa è rincarato.
--
--  Sulle scorte: la soglia fissa («meno di 2 kg → ordina») è il modo più
--  comune e il meno utile. Due chili di riso sono una settimana, due chili
--  di salmone sono un servizio. Qui la soglia c'è, ma accanto compaiono i
--  GIORNI DI COPERTURA, calcolati sul consumo vero delle ultime settimane:
--  è quello il numero che dice se c'è un problema.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  apri_inventario
-- ----------------------------------------------------------------------------
--  Crea il conteggio e ci mette dentro la giacenza calcolata di ogni
--  ingrediente. La fotografia va scattata all'apertura: se la si prendesse
--  alla chiusura, tutto ciò che si muove mentre si conta finirebbe nella
--  differenza come se fosse un ammanco.
create or replace function magazzino.apri_inventario(
  p_organizzazione_id uuid,
  p_deposito_id       uuid default null,
  p_descrizione       text default null,
  p_categoria_id      uuid default null
)
returns uuid
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_deposito uuid;
  v_id       uuid;
begin
  v_deposito := coalesce(p_deposito_id, (
    select id from magazzino.deposito
    where organizzazione_id = p_organizzazione_id and attivo
    order by ordinamento, codice limit 1));

  if v_deposito is null then
    raise exception 'Nessun magazzino attivo.';
  end if;

  insert into magazzino.inventario (organizzazione_id, deposito_id, descrizione, creato_da)
  values (p_organizzazione_id, v_deposito, p_descrizione, auth.uid())
  returning id into v_id;

  -- Tutti gli ingredienti attivi, anche quelli a zero: un prodotto che il
  -- sistema crede finito e che invece è lì va scoperto proprio adesso.
  insert into magazzino.inventario_riga (
    inventario_id, ingrediente_id, quantita_teorica, costo_unitario)
  select v_id, i.id,
         coalesce((select sum(m.quantita) from magazzino.movimento m
                    where m.ingrediente_id = i.id and m.deposito_id = v_deposito), 0),
         i.costo_medio
  from magazzino.ingrediente i
  where i.organizzazione_id = p_organizzazione_id
    and i.attivo
    and (p_categoria_id is null or i.categoria_id = p_categoria_id);

  return v_id;
end;
$$;


-- ----------------------------------------------------------------------------
--  chiudi_inventario
-- ----------------------------------------------------------------------------
--  Trasforma le differenze in movimenti di rettifica.
--
--  Le righe non contate si saltano: «non l'ho contato» e «ce n'è zero» sono
--  cose diverse, e confonderle azzererebbe mezzo magazzino per distrazione.
create or replace function magazzino.chiudi_inventario(p_inventario_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_inv     magazzino.inventario%rowtype;
  v_r       record;
  v_n       integer := 0;
  v_contate integer := 0;
  v_valore  numeric := 0;
begin
  select * into v_inv from magazzino.inventario where id = p_inventario_id for update;
  if not found then
    raise exception 'Inventario % inesistente o non visibile.', p_inventario_id;
  end if;
  if v_inv.stato <> 'aperto' then
    raise exception 'L''inventario è già %.', v_inv.stato;
  end if;
  if not magazzino.ha_ruolo(v_inv.organizzazione_id, array['titolare','gestore']) then
    raise exception 'Solo titolare o gestore possono chiudere un inventario.';
  end if;

  for v_r in
    select r.*, i.costo_medio
    from magazzino.inventario_riga r
    join magazzino.ingrediente i on i.id = r.ingrediente_id
    where r.inventario_id = p_inventario_id
      and r.quantita_contata is not null
  loop
    v_contate := v_contate + 1;
    continue when v_r.differenza = 0;

    insert into magazzino.movimento (
      organizzazione_id, ingrediente_id, deposito_id, lotto_id,
      causale_codice, quantita, costo_unitario, data_competenza,
      riferimento_tipo, riferimento_id, creato_da, note
    ) values (
      v_inv.organizzazione_id, v_r.ingrediente_id, v_inv.deposito_id, v_r.lotto_id,
      'rettifica_inventario', v_r.differenza,
      coalesce(v_r.costo_unitario, v_r.costo_medio), v_inv.data_inventario,
      'inventario', p_inventario_id, auth.uid(),
      'Inventario del ' || to_char(v_inv.data_inventario, 'DD/MM/YYYY')
    );

    v_n := v_n + 1;
    v_valore := v_valore + v_r.differenza * coalesce(v_r.costo_unitario, v_r.costo_medio, 0);
  end loop;

  update magazzino.inventario
  set stato = 'chiuso', chiuso_da = auth.uid(), chiuso_il = now()
  where id = p_inventario_id;

  return jsonb_build_object(
    'inventario_id', p_inventario_id,
    'righe_contate', v_contate,
    'rettifiche',    v_n,
    -- Negativo significa che manca merce rispetto a quanto il sistema
    -- credeva: cali, sprechi, errori di ricetta o ammanchi veri.
    'valore_differenza', round(v_valore, 2)
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  Consumo medio giornaliero
-- ----------------------------------------------------------------------------
--  Sulle ultime quattro settimane, contando solo le uscite per vendita e
--  produzione: rettifiche e scarti non sono consumo, sono errori o perdite,
--  e includerli gonfierebbe la previsione.
create or replace view magazzino.consumo_giornaliero
with (security_invoker = true)
as
select
  m.organizzazione_id,
  m.ingrediente_id,
  round(sum(-m.quantita) / 28.0, 4)          as consumo_medio_giorno,
  round(sum(-m.quantita), 3)                 as consumo_28_giorni,
  count(distinct m.data_competenza)          as giorni_con_consumo
from magazzino.movimento m
where m.causale_codice in ('scarico_vendita', 'scarico_produzione')
  and m.data_competenza >= current_date - 28
  and m.quantita < 0
group by m.organizzazione_id, m.ingrediente_id;


-- ----------------------------------------------------------------------------
--  Stato delle scorte
-- ----------------------------------------------------------------------------
--  Il sensore vero e proprio. Quattro stati, in ordine di urgenza:
--
--    esaurito → giacenza a zero o sotto (sotto significa che qualcosa non
--               torna: si è venduto più di quanto risulti caricato)
--    critico  → meno di due giorni di copertura, oppure sotto la scorta minima
--    basso    → meno di cinque giorni
--    ok       → il resto
--
--  I giorni di copertura valgono più della soglia fissa: due chili di riso
--  sono una settimana, due chili di salmone sono un servizio.
create or replace view magazzino.stato_scorte
with (security_invoker = true)
as
select
  i.organizzazione_id,
  i.id                                  as ingrediente_id,
  i.nome                                as ingrediente,
  i.um_base,
  c.nome                                as categoria,
  coalesce(g.quantita, 0)               as giacenza,
  i.scorta_minima,
  i.scorta_ideale,
  i.costo_medio,
  round(coalesce(g.quantita, 0) * coalesce(i.costo_medio, 0), 2) as valore,
  coalesce(cg.consumo_medio_giorno, 0)  as consumo_giorno,

  case when coalesce(cg.consumo_medio_giorno, 0) > 0
       then round(coalesce(g.quantita, 0) / cg.consumo_medio_giorno, 1)
  end                                   as giorni_copertura,

  case
    when coalesce(g.quantita, 0) <= 0 then 'esaurito'
    when i.scorta_minima is not null and g.quantita < i.scorta_minima then 'critico'
    when cg.consumo_medio_giorno > 0
         and g.quantita / cg.consumo_medio_giorno < 2 then 'critico'
    when cg.consumo_medio_giorno > 0
         and g.quantita / cg.consumo_medio_giorno < 5 then 'basso'
    else 'ok'
  end                                   as stato,

  -- Quanto ordinare per tornare alla scorta ideale, o per coprire due
  -- settimane di consumo se la scorta ideale non è stata impostata.
  greatest(0, round(
    coalesce(i.scorta_ideale, coalesce(cg.consumo_medio_giorno, 0) * 14)
    - coalesce(g.quantita, 0), 3))      as da_ordinare

from magazzino.ingrediente i
left join magazzino.categoria_ingrediente c on c.id = i.categoria_id
left join (select organizzazione_id, ingrediente_id, sum(quantita) as quantita
             from magazzino.giacenza group by 1, 2) g
       on g.ingrediente_id = i.id
left join magazzino.consumo_giornaliero cg on cg.ingrediente_id = i.id
where i.attivo;

comment on view magazzino.stato_scorte is
  'Un sensore per ingrediente. I giorni di copertura contano più della soglia fissa: dicono quanto manca alla rottura di stock, non quanto resta in valore assoluto.';


-- ----------------------------------------------------------------------------
--  Scadenze
-- ----------------------------------------------------------------------------
create or replace view magazzino.scadenze
with (security_invoker = true)
as
select
  l.organizzazione_id,
  l.id                              as lotto_id,
  l.codice,
  i.nome                            as ingrediente,
  i.um_base,
  gl.quantita,
  l.data_scadenza,
  (l.data_scadenza - current_date)  as giorni,
  l.abbattuto,
  i.richiede_abbattimento,
  round(gl.quantita * coalesce(l.costo_unitario, i.costo_medio, 0), 2) as valore,
  case
    when l.data_scadenza < current_date then 'scaduto'
    when l.data_scadenza <= current_date + 2 then 'urgente'
    else 'in scadenza'
  end                               as stato
from magazzino.lotto l
join magazzino.ingrediente i on i.id = l.ingrediente_id
join (select lotto_id, sum(quantita) as quantita
        from magazzino.giacenza_lotto group by lotto_id) gl on gl.lotto_id = l.id
where l.stato = 'attivo'
  and l.data_scadenza is not null
  and l.data_scadenza <= current_date + 7
  and gl.quantita > 0;


-- ----------------------------------------------------------------------------
--  Pesce crudo in attesa di abbattimento
-- ----------------------------------------------------------------------------
--  Obbligo di legge, non comodità: pesce destinato al consumo crudo, entrato
--  e non ancora abbattuto. Deve essere visibile in cima al cruscotto.
create or replace view magazzino.da_abbattere
with (security_invoker = true)
as
select
  l.organizzazione_id,
  l.id            as lotto_id,
  l.codice,
  i.nome          as ingrediente,
  gl.quantita,
  i.um_base,
  l.data_carico,
  (current_date - l.data_carico) as giorni_in_casa
from magazzino.lotto l
join magazzino.ingrediente i on i.id = l.ingrediente_id
join (select lotto_id, sum(quantita) as quantita
        from magazzino.giacenza_lotto group by lotto_id) gl on gl.lotto_id = l.id
where i.richiede_abbattimento
  and not l.abbattuto
  and l.stato = 'attivo'
  and gl.quantita > 0;


-- ----------------------------------------------------------------------------
--  Rincari
-- ----------------------------------------------------------------------------
--  Confronta l'ultimo prezzo pagato con la media dei novanta giorni
--  precedenti. Un rincaro sotto il 5% è rumore; sopra il 10% cambia il food
--  cost di un piatto e va saputo.
create or replace view magazzino.rincari
with (security_invoker = true)
as
with ultimo as (
  select distinct on (organizzazione_id, ingrediente_id)
         organizzazione_id, ingrediente_id, prezzo_um_base, data, fornitore_id
  from magazzino.storico_prezzo
  order by organizzazione_id, ingrediente_id, data desc
),
precedente as (
  select s.organizzazione_id, s.ingrediente_id, avg(s.prezzo_um_base) as media
  from magazzino.storico_prezzo s
  join ultimo u on u.ingrediente_id = s.ingrediente_id
  where s.data < u.data and s.data >= u.data - 90
  group by s.organizzazione_id, s.ingrediente_id
)
select
  u.organizzazione_id,
  u.ingrediente_id,
  i.nome                        as ingrediente,
  i.um_base,
  u.prezzo_um_base              as prezzo_attuale,
  round(p.media, 6)             as prezzo_precedente,
  round(100 * (u.prezzo_um_base - p.media) / nullif(p.media, 0), 1) as variazione_percentuale,
  u.data                        as data_ultimo_acquisto,
  f.denominazione               as fornitore
from ultimo u
join precedente p on p.ingrediente_id = u.ingrediente_id
join magazzino.ingrediente i on i.id = u.ingrediente_id
left join magazzino.fornitore f on f.id = u.fornitore_id
where p.media > 0
  and abs(100 * (u.prezzo_um_base - p.media) / p.media) >= 5;


-- ----------------------------------------------------------------------------
--  Il cruscotto
-- ----------------------------------------------------------------------------
--  Una riga sola, tutti i numeri della prima schermata. Una query invece di
--  dodici: la schermata d'apertura si vede decine di volte al giorno, e
--  dodici chiamate in parallelo su un piano gratuito si sentono.
create or replace view magazzino.cruscotto
with (security_invoker = true)
as
select
  o.id as organizzazione_id,

  -- ── Lavoro da fare ────────────────────────────────────────────────────
  (select count(*) from magazzino.documento_carico d
    where d.organizzazione_id = o.id and d.stato in ('bozza','in_revisione'))
                                                          as documenti_aperti,
  (select count(*) from magazzino.documento_carico_riga r
     join magazzino.documento_carico d on d.id = r.documento_id
    where d.organizzazione_id = o.id and d.stato in ('bozza','in_revisione')
      and r.stato_match = 'da_risolvere')                 as righe_da_abbinare,
  (select count(*) from magazzino.lavorazione l
    where l.organizzazione_id = o.id and l.stato = 'aperta')
                                                          as lavorazioni_aperte,
  (select count(*) from magazzino.inventario iv
    where iv.organizzazione_id = o.id and iv.stato = 'aperto')
                                                          as inventari_aperti,
  (select count(*) from magazzino.prodotti_da_collegare pc
    where pc.organizzazione_id = o.id)                    as prodotti_da_collegare,

  -- ── Allarmi ───────────────────────────────────────────────────────────
  (select count(*) from magazzino.da_abbattere ab
    where ab.organizzazione_id = o.id)                    as da_abbattere,
  (select count(*) from magazzino.scadenze s
    where s.organizzazione_id = o.id and s.stato = 'scaduto')
                                                          as lotti_scaduti,
  (select count(*) from magazzino.scadenze s
    where s.organizzazione_id = o.id and s.stato <> 'scaduto')
                                                          as lotti_in_scadenza,
  (select count(*) from magazzino.stato_scorte s
    where s.organizzazione_id = o.id and s.stato = 'esaurito')
                                                          as esauriti,
  (select count(*) from magazzino.stato_scorte s
    where s.organizzazione_id = o.id and s.stato = 'critico')
                                                          as critici,
  (select count(*) from magazzino.stato_scorte s
    where s.organizzazione_id = o.id and s.stato = 'basso')
                                                          as bassi,
  (select count(*) from magazzino.rincari r
    where r.organizzazione_id = o.id and r.variazione_percentuale >= 10)
                                                          as rincari_forti,

  -- ── Numeri ────────────────────────────────────────────────────────────
  (select round(sum(g.quantita * coalesce(i.costo_medio, 0)), 2)
     from magazzino.giacenza g
     join magazzino.ingrediente i on i.id = g.ingrediente_id
    where g.organizzazione_id = o.id)                     as valore_magazzino,
  (select count(*) from magazzino.ingrediente i
    where i.organizzazione_id = o.id and i.attivo)        as ingredienti,
  (select count(*) from magazzino.prodotto_venduto p
    where p.organizzazione_id = o.id and p.attivo)        as prodotti,
  (select count(*) from magazzino.food_cost fc
    where fc.organizzazione_id = o.id)                    as prodotti_con_ricetta,

  -- ── Acquisti del mese ─────────────────────────────────────────────────
  (select round(sum(m.quantita * coalesce(m.costo_unitario, 0)), 2)
     from magazzino.movimento m
    where m.organizzazione_id = o.id
      and m.causale_codice = 'carico_acquisto'
      and m.data_competenza >= date_trunc('month', current_date))
                                                          as acquisti_mese,
  (select round(sum(-m.quantita * coalesce(m.costo_unitario, 0)), 2)
     from magazzino.movimento m
    where m.organizzazione_id = o.id
      and m.causale_codice = 'scarico_vendita'
      and m.data_competenza >= date_trunc('month', current_date))
                                                          as consumo_mese

from magazzino.organizzazione o;


grant execute on function magazzino.apri_inventario(uuid, uuid, text, uuid) to authenticated;
grant execute on function magazzino.chiudi_inventario(uuid) to authenticated;
