-- ============================================================================
--  MAGAZZINO HIO — Sezione 2, file 16: lavorazioni
-- ============================================================================
--
--  Due gesti diversi che il sistema tratta con la stessa tabella.
--
--  PRODUZIONE — molti ingredienti, un prodotto.
--    5 kg di riso + aceto + zucchero → 8,7 kg di riso condito.
--    Il peso può AUMENTARE: il riso assorbe acqua. Nessun vincolo sul totale.
--
--  DISASSEMBLAGGIO — un pezzo intero, molti pezzi ottenuti.
--    Un loin di tonno da 8,4 kg → 3,1 kg per la tagliata, 2,4 kg per la
--    tartare, 1,6 kg per il sashimi, 1,3 kg di scarto.
--    Il peso NON può aumentare: da otto chili non ne escono dieci.
--
--  Il secondo è il caso che nessun gestionale generico sa fare, ed è dove
--  stanno i soldi di questo locale. Il costo della tagliata di tonno non è
--  il prezzo al chilo del tonno: dipende da come si ripartisce il costo del
--  pezzo intero sui tagli ottenuti, e da quanto ha reso quel pezzo quel
--  giorno. Con lo storico si scopre che un fornitore rende il 62% e un altro
--  il 71%, e che a parità di prezzo al chilo il secondo costa meno.
--
--  Per questo i pesi si registrano davvero invece di usare rese standard:
--  una resa stimata è un numero che si copia da un manuale, una resa
--  misurata è un numero che si può contestare al fornitore.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  Tracciabilità attraverso la lavorazione
-- ----------------------------------------------------------------------------
--  I tranci ricavati da un tonno devono ricordare da quale tonno vengono.
--  Senza questo, la catena si spezza proprio nel punto in cui il pesce viene
--  trasformato, cioè dove serve di più.
alter table magazzino.lotto
  add column if not exists lotto_origine_id uuid references magazzino.lotto(id) on delete set null;

comment on column magazzino.lotto.lotto_origine_id is
  'Il lotto da cui questo deriva per lavorazione. Permette di risalire dal trancio nel piatto alla cassa di pesce e al suo DDT.';

create index if not exists lotto_per_origine
  on magazzino.lotto (lotto_origine_id) where lotto_origine_id is not null;


-- ----------------------------------------------------------------------------
--  aggiorna_costo_medio
-- ----------------------------------------------------------------------------
--  Media ponderata mobile su una singola entrata.
--
--  NOTA: `conferma_carico` (file 05) applica la stessa formula scritta in
--  linea. Se la regola cambia va cambiata in entrambi i posti. Non l'ho
--  unificata subito per non riscrivere una funzione già collaudata su dati
--  veri; è un debito piccolo ma reale.
create or replace function magazzino.aggiorna_costo_medio(
  p_ingrediente_id uuid,
  p_quantita       numeric,
  p_costo_unitario numeric
)
returns numeric
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_giacenza numeric;
  v_medio    numeric;
  v_nuovo    numeric;
begin
  if p_costo_unitario is null or p_quantita is null or p_quantita <= 0 then
    return null;
  end if;

  select costo_medio into v_medio
  from magazzino.ingrediente where id = p_ingrediente_id;

  -- Giacenza PRIMA di questa entrata: il movimento è già stato scritto,
  -- quindi va sottratto.
  select coalesce(sum(quantita), 0) - p_quantita into v_giacenza
  from magazzino.movimento
  where ingrediente_id = p_ingrediente_id;

  if v_giacenza > 0 and v_medio is not null then
    v_nuovo := (v_giacenza * v_medio + p_quantita * p_costo_unitario)
               / (v_giacenza + p_quantita);
  else
    -- Nessuna storia su cui appoggiarsi: vale il costo di adesso.
    v_nuovo := p_costo_unitario;
  end if;

  update magazzino.ingrediente
  set costo_medio = v_nuovo,
      ultimo_costo = p_costo_unitario,
      costo_aggiornato_il = now()
  where id = p_ingrediente_id;

  return v_nuovo;
end;
$$;


-- ----------------------------------------------------------------------------
--  lavorazione
-- ----------------------------------------------------------------------------
create table magazzino.lavorazione (
  id                 uuid primary key default gen_random_uuid(),
  organizzazione_id  uuid not null references magazzino.organizzazione(id) on delete cascade,

  tipo               text not null check (tipo in ('produzione', 'disassemblaggio')),
  data_lavorazione   date not null default current_date,
  deposito_id        uuid references magazzino.deposito(id) on delete restrict,

  -- Solo per le produzioni fatte seguendo una ricetta: serve a precompilare
  -- gli ingredienti e a confrontare il consumo previsto con quello vero.
  distinta_id        uuid references magazzino.distinta(id) on delete set null,

  -- Come si spartisce il costo del pezzo intero fra i tagli ottenuti.
  --   peso   → tutti allo stesso costo al grammo. Semplice e sbagliato:
  --            farebbe costare lo scarto quanto il filetto.
  --   valore → in proporzione al pregio di ciascun taglio. È il metodo
  --            corretto per il pesce e la carne, ed è il default.
  ripartizione       text not null default 'valore'
                       check (ripartizione in ('peso', 'valore')),

  stato              text not null default 'aperta'
                       check (stato in ('aperta', 'chiusa', 'annullata')),

  note               text,
  creato_da          uuid references auth.users(id) on delete set null,
  creato_il          timestamptz not null default now(),
  chiuso_da          uuid references auth.users(id) on delete set null,
  chiuso_il          timestamptz,
  aggiornato_il      timestamptz not null default now()
);

create index lavorazione_aperte
  on magazzino.lavorazione (organizzazione_id, data_lavorazione desc)
  where stato = 'aperta';

create index lavorazione_cronologia
  on magazzino.lavorazione (organizzazione_id, data_lavorazione desc);


-- ----------------------------------------------------------------------------
--  lavorazione_input — cosa è entrato
-- ----------------------------------------------------------------------------
create table magazzino.lavorazione_input (
  id                 uuid primary key default gen_random_uuid(),
  lavorazione_id     uuid not null references magazzino.lavorazione(id) on delete cascade,
  organizzazione_id  uuid not null references magazzino.organizzazione(id) on delete cascade,
  ingrediente_id     uuid not null references magazzino.ingrediente(id) on delete restrict,
  lotto_id           uuid references magazzino.lotto(id) on delete restrict,

  -- Il peso vero messo sulla bilancia, non quello previsto dalla ricetta.
  quantita           numeric(14,3) not null check (quantita > 0),

  -- Fotografato alla chiusura: il costo medio cambia coi carichi successivi,
  -- e il costo di questa lavorazione non deve cambiare a posteriori.
  costo_unitario     numeric(14,6),

  note               text,
  creato_il          timestamptz not null default now()
);

create index lavorazione_input_per_lavorazione
  on magazzino.lavorazione_input (lavorazione_id);


-- ----------------------------------------------------------------------------
--  lavorazione_output — cosa è uscito
-- ----------------------------------------------------------------------------
create table magazzino.lavorazione_output (
  id                 uuid primary key default gen_random_uuid(),
  lavorazione_id     uuid not null references magazzino.lavorazione(id) on delete cascade,
  organizzazione_id  uuid not null references magazzino.organizzazione(id) on delete cascade,
  ingrediente_id     uuid not null references magazzino.ingrediente(id) on delete restrict,

  quantita           numeric(14,3) not null check (quantita > 0),

  -- Quanto vale questo taglio rispetto agli altri, con la ripartizione «valore».
  -- Non serve un prezzo esatto: contano le proporzioni. Se il filetto vale il
  -- doppio dei ritagli, 2 e 1 bastano.
  valore_relativo    numeric(10,4) not null default 1 check (valore_relativo > 0),

  -- Calcolati alla chiusura.
  costo_unitario     numeric(14,6),
  lotto_id           uuid references magazzino.lotto(id) on delete set null,

  note               text,
  creato_il          timestamptz not null default now()
);

create index lavorazione_output_per_lavorazione
  on magazzino.lavorazione_output (lavorazione_id);

comment on column magazzino.lavorazione_output.valore_relativo is
  'Pregio del taglio rispetto agli altri della stessa lavorazione. Contano solo le proporzioni: filetto 3, tartare 2, ritagli 1.';


-- ----------------------------------------------------------------------------
--  Lo scarto
-- ----------------------------------------------------------------------------
--  Non è una riga di output: è la differenza fra ciò che è entrato e ciò che
--  è uscito. Registrarlo come output vorrebbe dire attribuirgli un costo e
--  farlo entrare in magazzino, e lo scarto non è merce.
--
--  Il suo costo esiste comunque, ma va spalmato sui tagli buoni: è
--  esattamente ciò che fa la ripartizione. Se da 8,4 kg di tonno ne escono
--  7,1 buoni, quei 7,1 si portano il costo di tutti e 8,4.


-- ----------------------------------------------------------------------------
--  chiudi_lavorazione
-- ----------------------------------------------------------------------------
create or replace function magazzino.chiudi_lavorazione(p_lavorazione_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  v_lav          magazzino.lavorazione%rowtype;
  v_deposito     uuid;
  v_in           record;
  v_out          record;
  v_ing          magazzino.ingrediente%rowtype;
  v_costo_totale numeric := 0;
  v_peso_in      numeric := 0;
  v_peso_out     numeric := 0;
  v_base         numeric := 0;   -- denominatore della ripartizione
  v_costo_unit   numeric;
  v_lotto        uuid;
  v_lotto_orig   uuid;
  v_n_out        integer := 0;
begin
  select * into v_lav from magazzino.lavorazione
  where id = p_lavorazione_id for update;

  if not found then
    raise exception 'Lavorazione % inesistente o non visibile.', p_lavorazione_id;
  end if;
  if v_lav.stato <> 'aperta' then
    raise exception 'La lavorazione è già %.', v_lav.stato;
  end if;
  if not magazzino.ha_ruolo(v_lav.organizzazione_id, array['titolare','gestore']) then
    raise exception 'Solo titolare o gestore possono chiudere una lavorazione.';
  end if;

  if not exists (select 1 from magazzino.lavorazione_input where lavorazione_id = p_lavorazione_id) then
    raise exception 'Nessun ingrediente in entrata: non c''è niente da lavorare.';
  end if;
  if not exists (select 1 from magazzino.lavorazione_output where lavorazione_id = p_lavorazione_id) then
    raise exception 'Nessun prodotto in uscita: indicare cosa è stato ottenuto.';
  end if;

  select id into v_deposito
  from magazzino.deposito
  where organizzazione_id = v_lav.organizzazione_id and attivo
  order by ordinamento, codice limit 1;
  v_deposito := coalesce(v_lav.deposito_id, v_deposito);

  -- ── Entrate: costo fotografato adesso, poi scarico ──────────────────────
  for v_in in
    select * from magazzino.lavorazione_input where lavorazione_id = p_lavorazione_id
  loop
    select * into v_ing from magazzino.ingrediente where id = v_in.ingrediente_id;

    v_costo_unit := coalesce(v_in.costo_unitario, v_ing.costo_medio);

    update magazzino.lavorazione_input
    set costo_unitario = v_costo_unit where id = v_in.id;

    v_costo_totale := v_costo_totale + v_in.quantita * coalesce(v_costo_unit, 0);
    v_peso_in := v_peso_in + v_in.quantita;

    insert into magazzino.movimento (
      organizzazione_id, ingrediente_id, deposito_id, lotto_id,
      causale_codice, quantita, costo_unitario, data_competenza,
      riferimento_tipo, riferimento_id, creato_da, note
    ) values (
      v_lav.organizzazione_id, v_in.ingrediente_id, v_deposito, v_in.lotto_id,
      'scarico_produzione', -v_in.quantita, v_costo_unit, v_lav.data_lavorazione,
      'lavorazione', p_lavorazione_id, auth.uid(),
      case when v_lav.tipo = 'disassemblaggio' then 'Pezzo lavorato' end
    );

    -- Il primo lotto in entrata diventa l'origine dei pezzi ottenuti. Con un
    -- solo pezzo intero — il caso normale del disassemblaggio — la catena
    -- resta esatta.
    if v_lotto_orig is null then v_lotto_orig := v_in.lotto_id; end if;
  end loop;

  -- ── Base della ripartizione ─────────────────────────────────────────────
  select
    sum(o.quantita),
    sum(case when v_lav.ripartizione = 'valore'
             then o.quantita * o.valore_relativo
             else o.quantita end)
  into v_peso_out, v_base
  from magazzino.lavorazione_output o
  where o.lavorazione_id = p_lavorazione_id;

  if v_lav.tipo = 'disassemblaggio' and v_peso_out > v_peso_in + 0.001 then
    raise exception
      'Da % non possono uscire %: controllare i pesi.',
      magazzino.numero_it(v_peso_in), magazzino.numero_it(v_peso_out);
  end if;

  -- ── Uscite: costo ripartito, carico, lotti ──────────────────────────────
  for v_out in
    select * from magazzino.lavorazione_output where lavorazione_id = p_lavorazione_id
  loop
    select * into v_ing from magazzino.ingrediente where id = v_out.ingrediente_id;

    -- Tutto il costo entrato si spalma su ciò che è uscito: lo scarto non
    -- sparisce, si distribuisce sui pezzi buoni.
    v_costo_unit := case
      when v_base > 0 and v_lav.ripartizione = 'valore'
        then v_costo_totale * v_out.valore_relativo / v_base
      when v_base > 0
        then v_costo_totale / v_base
    end;

    v_lotto := null;
    if v_ing.gestisci_lotti or v_ing.richiede_abbattimento or v_lotto_orig is not null then
      insert into magazzino.lotto (
        organizzazione_id, ingrediente_id, codice, data_carico,
        quantita_iniziale, costo_unitario, lotto_origine_id,
        data_scadenza
      ) values (
        v_lav.organizzazione_id, v_out.ingrediente_id,
        to_char(v_lav.data_lavorazione, 'YYYY') || '-L' ||
          lpad(nextval('magazzino.lotto_progressivo')::text, 5, '0'),
        v_lav.data_lavorazione, v_out.quantita, v_costo_unit, v_lotto_orig,
        case when v_ing.giorni_scadenza_default is not null
             then v_lav.data_lavorazione + v_ing.giorni_scadenza_default end
      ) returning id into v_lotto;
    end if;

    insert into magazzino.movimento (
      organizzazione_id, ingrediente_id, deposito_id, lotto_id,
      causale_codice, quantita, costo_unitario, data_competenza,
      riferimento_tipo, riferimento_id, creato_da
    ) values (
      v_lav.organizzazione_id, v_out.ingrediente_id, v_deposito, v_lotto,
      'carico_produzione', v_out.quantita, v_costo_unit, v_lav.data_lavorazione,
      'lavorazione', p_lavorazione_id, auth.uid()
    );

    perform magazzino.aggiorna_costo_medio(v_out.ingrediente_id, v_out.quantita, v_costo_unit);

    update magazzino.lavorazione_output
    set costo_unitario = v_costo_unit, lotto_id = v_lotto
    where id = v_out.id;

    v_n_out := v_n_out + 1;
  end loop;

  update magazzino.lavorazione
  set stato = 'chiusa', chiuso_da = auth.uid(), chiuso_il = now()
  where id = p_lavorazione_id;

  return jsonb_build_object(
    'lavorazione_id', p_lavorazione_id,
    'tipo',           v_lav.tipo,
    'peso_entrato',   v_peso_in,
    'peso_uscito',    v_peso_out,
    'scarto',         round(v_peso_in - v_peso_out, 3),
    -- La resa è il numero che conta. Sotto il 60% su un pesce c'è qualcosa
    -- da chiedere al fornitore, o da rivedere in cucina.
    'resa_percentuale', case when v_peso_in > 0
                             then round(100 * v_peso_out / v_peso_in, 1) end,
    'costo_lavorato', round(v_costo_totale, 2),
    'prodotti',       v_n_out
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  storna_lavorazione
-- ----------------------------------------------------------------------------
create or replace function magazzino.storna_lavorazione(
  p_lavorazione_id uuid,
  p_motivo         text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_lav magazzino.lavorazione%rowtype;
  v_mov record;
  v_n   integer := 0;
begin
  select * into v_lav from magazzino.lavorazione where id = p_lavorazione_id for update;
  if not found then
    raise exception 'Lavorazione % inesistente o non visibile.', p_lavorazione_id;
  end if;
  if v_lav.stato <> 'chiusa' then
    raise exception 'Si storna solo una lavorazione chiusa (stato attuale: %).', v_lav.stato;
  end if;
  if not magazzino.ha_ruolo(v_lav.organizzazione_id, array['titolare','gestore']) then
    raise exception 'Solo titolare o gestore possono stornare una lavorazione.';
  end if;

  for v_mov in
    select m.* from magazzino.movimento m
    where m.riferimento_tipo = 'lavorazione' and m.riferimento_id = p_lavorazione_id
      and not exists (select 1 from magazzino.movimento s where s.movimento_stornato_id = m.id)
  loop
    insert into magazzino.movimento (
      organizzazione_id, ingrediente_id, deposito_id, lotto_id,
      causale_codice, quantita, costo_unitario, data_competenza,
      riferimento_tipo, riferimento_id, movimento_stornato_id, note, creato_da
    ) values (
      v_mov.organizzazione_id, v_mov.ingrediente_id, v_mov.deposito_id, v_mov.lotto_id,
      'storno', -v_mov.quantita, v_mov.costo_unitario, current_date,
      'lavorazione', p_lavorazione_id, v_mov.id,
      coalesce(p_motivo, 'Storno lavorazione'), auth.uid()
    );
    v_n := v_n + 1;
  end loop;

  update magazzino.lotto set stato = 'scartato'
  where id in (select lotto_id from magazzino.lavorazione_output
               where lavorazione_id = p_lavorazione_id and lotto_id is not null);

  update magazzino.lavorazione set stato = 'annullata' where id = p_lavorazione_id;

  return jsonb_build_object('lavorazione_id', p_lavorazione_id, 'movimenti_stornati', v_n);
end;
$$;


-- ----------------------------------------------------------------------------
--  Le rese, che sono il motivo per cui esiste questo modulo
-- ----------------------------------------------------------------------------
create or replace view magazzino.resa_lavorazione
with (security_invoker = true)
as
select
  l.id,
  l.organizzazione_id,
  l.tipo,
  l.data_lavorazione,
  l.stato,
  (select string_agg(i.nome, ', ')
     from magazzino.lavorazione_input li
     join magazzino.ingrediente i on i.id = li.ingrediente_id
    where li.lavorazione_id = l.id)                       as lavorato,
  (select sum(li.quantita) from magazzino.lavorazione_input li
    where li.lavorazione_id = l.id)                       as peso_entrato,
  (select sum(lo.quantita) from magazzino.lavorazione_output lo
    where lo.lavorazione_id = l.id)                       as peso_uscito,
  (select round(100.0 * sum(lo.quantita) / nullif(
             (select sum(li.quantita) from magazzino.lavorazione_input li
               where li.lavorazione_id = l.id), 0), 1)
     from magazzino.lavorazione_output lo
    where lo.lavorazione_id = l.id)                       as resa_percentuale,
  (select round(sum(li.quantita * coalesce(li.costo_unitario, 0)), 2)
     from magazzino.lavorazione_input li
    where li.lavorazione_id = l.id)                       as costo_lavorato
from magazzino.lavorazione l;


--  Lo storico delle rese per materia prima e per fornitore.
--
--  È il dato commercialmente più prezioso del sistema: due fornitori allo
--  stesso prezzo al chilo non costano uguale se uno rende il 62% e l'altro
--  il 71%. Il prezzo si contratta, la resa si misura.
create or replace view magazzino.resa_per_fornitore
with (security_invoker = true)
as
select
  l.organizzazione_id,
  i.id                                as ingrediente_id,
  i.nome                              as ingrediente,
  f.id                                as fornitore_id,
  coalesce(f.denominazione, 'senza lotto tracciato') as fornitore,
  count(distinct l.id)                as lavorazioni,
  round(avg(r.resa_percentuale), 1)   as resa_media,
  min(r.resa_percentuale)             as resa_minima,
  max(r.resa_percentuale)             as resa_massima,
  round(sum(li.quantita), 3)          as peso_lavorato,
  max(l.data_lavorazione)             as ultima_lavorazione
from magazzino.lavorazione l
join magazzino.resa_lavorazione r on r.id = l.id
join magazzino.lavorazione_input li on li.lavorazione_id = l.id
join magazzino.ingrediente i on i.id = li.ingrediente_id
left join magazzino.lotto lt on lt.id = li.lotto_id
left join magazzino.fornitore f on f.id = lt.fornitore_id
where l.tipo = 'disassemblaggio' and l.stato = 'chiusa'
group by l.organizzazione_id, i.id, i.nome, f.id, f.denominazione;


-- ----------------------------------------------------------------------------
--  Trigger e sicurezza
-- ----------------------------------------------------------------------------
create trigger lavorazione_tocca before update on magazzino.lavorazione
  for each row execute function magazzino.tocca_aggiornato_il();

create or replace function magazzino.lavorazione_riga_eredita_org()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  select l.organizzazione_id into new.organizzazione_id
  from magazzino.lavorazione l where l.id = new.lavorazione_id;
  return new;
end;
$$;

create trigger lavorazione_input_eredita_org_tg
  before insert or update of lavorazione_id on magazzino.lavorazione_input
  for each row execute function magazzino.lavorazione_riga_eredita_org();

create trigger lavorazione_output_eredita_org_tg
  before insert or update of lavorazione_id on magazzino.lavorazione_output
  for each row execute function magazzino.lavorazione_riga_eredita_org();

alter table magazzino.lavorazione        enable row level security;
alter table magazzino.lavorazione_input  enable row level security;
alter table magazzino.lavorazione_output enable row level security;

do $$
declare t text;
begin
  -- Registrare i pesi è il gesto quotidiano di chi lavora al banco: lo può
  -- fare chiunque sia membro. Chiudere la lavorazione no — quella muove il
  -- magazzino — e il controllo sta dentro `chiudi_lavorazione`.
  foreach t in array array['lavorazione', 'lavorazione_input', 'lavorazione_output']
  loop
    execute format($f$
      create policy %1$s_lettura on magazzino.%1$s
        for select to authenticated
        using (organizzazione_id in (select magazzino.organizzazioni_utente()));
      create policy %1$s_scrittura on magazzino.%1$s
        for all to authenticated
        using (organizzazione_id in (select magazzino.organizzazioni_utente()))
        with check (organizzazione_id in (select magazzino.organizzazioni_utente()));
    $f$, t);
  end loop;
end;
$$;

grant execute on function magazzino.aggiorna_costo_medio(uuid, numeric, numeric) to authenticated;
grant execute on function magazzino.chiudi_lavorazione(uuid) to authenticated;
grant execute on function magazzino.storna_lavorazione(uuid, text) to authenticated;
