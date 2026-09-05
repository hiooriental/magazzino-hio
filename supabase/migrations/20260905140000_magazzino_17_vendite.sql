-- ============================================================================
--  MAGAZZINO HIO — Sezione 2, file 17: vendite e scarico automatico
-- ============================================================================
--
--  Dallo scontrino al magazzino.
--
--  Lo scarico è deliberatamente SEPARATO dall'importazione: le vendite si
--  importano sempre, si scaricano solo quando i prodotti hanno una ricetta.
--  Un piatto senza distinta non deve impedire di importare la giornata, e
--  non deve nemmeno sparire in silenzio: resta lì, contato, come lavoro da
--  fare.
--
--  Il connettore iPratico non sta qui. Queste tabelle non sanno da dove
--  arrivano gli scontrini: `origine` e `codice_esterno` bastano a farci
--  entrare iPratico oggi e un altro registratore di cassa domani, senza
--  toccare né lo scarico né le ricette.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  vendita
-- ----------------------------------------------------------------------------
create table magazzino.vendita (
  id                 uuid primary key default gen_random_uuid(),
  organizzazione_id  uuid not null references magazzino.organizzazione(id) on delete cascade,

  origine            text not null default 'ipratico'
                       check (origine in ('ipratico', 'manuale', 'importazione')),
  -- Identificativo dello scontrino nel sistema di cassa. Serve a non
  -- importare due volte la stessa sera.
  codice_esterno     text,

  data_vendita       date not null,
  ora                time,
  coperti            smallint,
  totale             numeric(12,2),

  stato              text not null default 'importata'
                       check (stato in ('importata', 'scaricata', 'annullata')),

  scaricata_il       timestamptz,
  creato_il          timestamptz not null default now(),
  aggiornato_il      timestamptz not null default now()
);

create unique index vendita_codice_unico
  on magazzino.vendita (organizzazione_id, origine, codice_esterno)
  where codice_esterno is not null;

create index vendita_da_scaricare
  on magazzino.vendita (organizzazione_id, data_vendita)
  where stato = 'importata';

create index vendita_per_giorno
  on magazzino.vendita (organizzazione_id, data_vendita desc);


-- ----------------------------------------------------------------------------
--  vendita_riga
-- ----------------------------------------------------------------------------
create table magazzino.vendita_riga (
  id                   uuid primary key default gen_random_uuid(),
  vendita_id           uuid not null references magazzino.vendita(id) on delete cascade,
  organizzazione_id    uuid not null references magazzino.organizzazione(id) on delete cascade,

  -- Come arriva dalla cassa.
  codice_esterno       text,
  descrizione          text not null,
  quantita             numeric(10,3) not null default 1,
  prezzo_unitario      numeric(10,2),
  totale_riga          numeric(12,2),

  -- Un omaggio consuma magazzino esattamente come una vendita, ma non porta
  -- incasso: distinguerli è l'unico modo per capire se un ammanco è furto o
  -- generosità.
  tipo_riga            text not null default 'vendita'
                         check (tipo_riga in ('vendita', 'omaggio', 'storno', 'personale')),

  prodotto_venduto_id  uuid references magazzino.prodotto_venduto(id) on delete set null,

  creato_il            timestamptz not null default now()
);

create index vendita_riga_per_vendita
  on magazzino.vendita_riga (vendita_id);

create index vendita_riga_senza_prodotto
  on magazzino.vendita_riga (organizzazione_id)
  where prodotto_venduto_id is null;


-- ----------------------------------------------------------------------------
--  vendita_riga_modificatore
-- ----------------------------------------------------------------------------
--  «Margherita più funghi, senza basilico». Se i modificatori non si
--  registrano, il consumo teorico è sistematicamente più basso del reale e
--  ogni inventario sembra denunciare un ammanco che non c'è.
create table magazzino.vendita_riga_modificatore (
  id                uuid primary key default gen_random_uuid(),
  vendita_riga_id   uuid not null references magazzino.vendita_riga(id) on delete cascade,
  organizzazione_id uuid not null references magazzino.organizzazione(id) on delete cascade,
  codice_esterno    text,
  descrizione       text,
  modificatore_id   uuid references magazzino.modificatore(id) on delete set null,
  quantita          numeric(10,3) not null default 1,
  creato_il         timestamptz not null default now()
);

create index vendita_modificatore_per_riga
  on magazzino.vendita_riga_modificatore (vendita_riga_id);


-- ----------------------------------------------------------------------------
--  Abbinamento prodotto di cassa → prodotto interno
-- ----------------------------------------------------------------------------
--  Stesso principio degli articoli dei fornitori: prima il codice esatto,
--  poi il nome identico, poi la somiglianza. Confermato una volta, resta.
create or replace function magazzino.risolvi_vendita(p_vendita_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  v_org       uuid;
  v_r         record;
  v_prodotto  uuid;
  v_risolte   integer := 0;
  v_mancanti  integer := 0;
begin
  select organizzazione_id into v_org from magazzino.vendita where id = p_vendita_id;
  if v_org is null then
    raise exception 'Vendita % inesistente o non visibile.', p_vendita_id;
  end if;

  for v_r in
    select * from magazzino.vendita_riga
    where vendita_id = p_vendita_id and prodotto_venduto_id is null
  loop
    v_prodotto := null;

    if v_r.codice_esterno is not null then
      select id into v_prodotto from magazzino.prodotto_venduto
      where organizzazione_id = v_org and codice_esterno = v_r.codice_esterno;
    end if;

    if v_prodotto is null then
      select id into v_prodotto from magazzino.prodotto_venduto
      where organizzazione_id = v_org
        and magazzino.normalizza(nome) = magazzino.normalizza(v_r.descrizione)
      limit 1;
    end if;

    if v_prodotto is not null then
      update magazzino.vendita_riga set prodotto_venduto_id = v_prodotto where id = v_r.id;
      v_risolte := v_risolte + 1;
    else
      v_mancanti := v_mancanti + 1;
    end if;
  end loop;

  -- Stessa cosa per i modificatori.
  update magazzino.vendita_riga_modificatore vm
  set modificatore_id = m.id
  from magazzino.modificatore m, magazzino.vendita_riga r
  where vm.vendita_riga_id = r.id
    and r.vendita_id = p_vendita_id
    and vm.modificatore_id is null
    and m.organizzazione_id = v_org
    and (m.codice_esterno = vm.codice_esterno
         or magazzino.normalizza(m.nome) = magazzino.normalizza(vm.descrizione));

  return jsonb_build_object(
    'vendita_id', p_vendita_id, 'risolte', v_risolte, 'senza_prodotto', v_mancanti);
end;
$$;


-- ----------------------------------------------------------------------------
--  scarica_vendita
-- ----------------------------------------------------------------------------
--  Genera i movimenti di consumo. Un movimento per ingrediente, non uno per
--  riga: dieci Margherite sullo stesso scontrino fanno un solo scarico di
--  mozzarella, e il libro mastro resta leggibile.
--
--  Uno storno conta a rovescio: la merce non è mai uscita.
create or replace function magazzino.scarica_vendita(p_vendita_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  v_ven        magazzino.vendita%rowtype;
  v_deposito   uuid;
  v_c          record;
  v_n          integer := 0;
  v_valore     numeric := 0;
  v_senza      integer;
begin
  select * into v_ven from magazzino.vendita where id = p_vendita_id for update;
  if not found then
    raise exception 'Vendita % inesistente o non visibile.', p_vendita_id;
  end if;
  if v_ven.stato = 'scaricata' then
    raise exception 'Vendita già scaricata il %.', v_ven.scaricata_il;
  end if;
  if v_ven.stato = 'annullata' then
    raise exception 'Vendita annullata: non si scarica.';
  end if;

  -- Righe senza prodotto abbinato: si scarica lo stesso il resto, ma il
  -- numero va restituito, altrimenti il consumo sembra completo e non lo è.
  select count(*) into v_senza
  from magazzino.vendita_riga
  where vendita_id = p_vendita_id and prodotto_venduto_id is null;

  select id into v_deposito
  from magazzino.deposito
  where organizzazione_id = v_ven.organizzazione_id and attivo
  order by ordinamento, codice limit 1;

  -- Consumo totale per ingrediente: ricette dei piatti, più le aggiunte,
  -- meno i «senza».
  for v_c in
    with righe as (
      select r.id, r.quantita,
             case when r.tipo_riga = 'storno' then -1 else 1 end as verso,
             r.prodotto_venduto_id
      from magazzino.vendita_riga r
      where r.vendita_id = p_vendita_id and r.prodotto_venduto_id is not null
    ),
    da_ricetta as (
      select dc.ingrediente_id,
             sum(r.quantita * r.verso * dc.quantita
                 / (1 - dc.scarto_percentuale / 100.0)) as quantita
      from righe r
      join magazzino.distinta d
        on d.prodotto_venduto_id = r.prodotto_venduto_id and d.stato = 'attiva'
      join magazzino.distinta_componente dc on dc.distinta_id = d.id
      group by dc.ingrediente_id
    ),
    da_modificatori as (
      select mc.ingrediente_id,
             sum(r.quantita * r.verso * vm.quantita * mc.quantita
                 / (1 - mc.scarto_percentuale / 100.0)
                 * case when m.tipo = 'rimozione' then -1 else 1 end) as quantita
      from righe r
      join magazzino.vendita_riga_modificatore vm on vm.vendita_riga_id = r.id
      join magazzino.modificatore m on m.id = vm.modificatore_id
      join magazzino.modificatore_componente mc on mc.modificatore_id = m.id
      group by mc.ingrediente_id
    ),
    totale as (
      select ingrediente_id, sum(quantita) as quantita
      from (select * from da_ricetta union all select * from da_modificatori) x
      group by ingrediente_id
    )
    select t.ingrediente_id, round(t.quantita, 3) as quantita, i.costo_medio
    from totale t
    join magazzino.ingrediente i on i.id = t.ingrediente_id
    where round(t.quantita, 3) <> 0
  loop
    insert into magazzino.movimento (
      organizzazione_id, ingrediente_id, deposito_id,
      causale_codice, quantita, costo_unitario, data_competenza,
      riferimento_tipo, riferimento_id, creato_da
    ) values (
      v_ven.organizzazione_id, v_c.ingrediente_id, v_deposito,
      'scarico_vendita', -v_c.quantita, v_c.costo_medio, v_ven.data_vendita,
      'vendita', p_vendita_id, auth.uid()
    );
    v_n := v_n + 1;
    v_valore := v_valore + v_c.quantita * coalesce(v_c.costo_medio, 0);
  end loop;

  update magazzino.vendita
  set stato = 'scaricata', scaricata_il = now()
  where id = p_vendita_id;

  return jsonb_build_object(
    'vendita_id',        p_vendita_id,
    'ingredienti',       v_n,
    'costo_materie',     round(v_valore, 2),
    'righe_senza_prodotto', v_senza
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  scarica_giornata
-- ----------------------------------------------------------------------------
--  Il gesto di fine servizio: scarica tutto quello che è pronto e dice cosa
--  è rimasto indietro e perché.
create or replace function magazzino.scarica_giornata(
  p_organizzazione_id uuid,
  p_data              date
)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_v        record;
  v_esito    jsonb;
  v_ok       integer := 0;
  v_valore   numeric := 0;
  v_senza    integer := 0;
begin
  for v_v in
    select id from magazzino.vendita
    where organizzazione_id = p_organizzazione_id
      and data_vendita = p_data
      and stato = 'importata'
    order by ora nulls last
  loop
    perform magazzino.risolvi_vendita(v_v.id);
    v_esito := magazzino.scarica_vendita(v_v.id);
    v_ok := v_ok + 1;
    v_valore := v_valore + coalesce((v_esito ->> 'costo_materie')::numeric, 0);
    v_senza := v_senza + coalesce((v_esito ->> 'righe_senza_prodotto')::integer, 0);
  end loop;

  return jsonb_build_object(
    'data',              p_data,
    'scontrini',         v_ok,
    'costo_materie',     round(v_valore, 2),
    -- Righe vendute che il magazzino non sa cosa siano: o il prodotto non è
    -- in anagrafica, o non ha una ricetta. Finché è maggiore di zero, il
    -- consumo teorico è incompleto.
    'righe_non_scaricate', v_senza
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  Cosa manca per poter scaricare
-- ----------------------------------------------------------------------------
--  La coda di lavoro: prodotti visti in cassa che il magazzino non sa
--  tradurre. Ordinata per quante volte sono stati venduti, così si comincia
--  da quelli che pesano di più.
create or replace view magazzino.prodotti_da_collegare
with (security_invoker = true)
as
select
  r.organizzazione_id,
  r.codice_esterno,
  r.descrizione,
  count(*)                     as volte_venduto,
  sum(r.quantita)              as pezzi,
  max(v.data_vendita)          as ultima_vendita,
  case
    when r.prodotto_venduto_id is null then 'prodotto sconosciuto'
    else 'senza ricetta'
  end                          as motivo
from magazzino.vendita_riga r
join magazzino.vendita v on v.id = r.vendita_id
left join magazzino.prodotto_venduto p on p.id = r.prodotto_venduto_id
left join magazzino.distinta d
  on d.prodotto_venduto_id = p.id and d.stato = 'attiva'
where r.prodotto_venduto_id is null
   or (d.id is null and coalesce(p.senza_distinta, false) = false)
group by r.organizzazione_id, r.codice_esterno, r.descrizione,
         case when r.prodotto_venduto_id is null then 'prodotto sconosciuto'
              else 'senza ricetta' end
order by count(*) desc;


-- ----------------------------------------------------------------------------
--  Trigger e sicurezza
-- ----------------------------------------------------------------------------
create trigger vendita_tocca before update on magazzino.vendita
  for each row execute function magazzino.tocca_aggiornato_il();

create or replace function magazzino.vendita_riga_eredita_org()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  select v.organizzazione_id into new.organizzazione_id
  from magazzino.vendita v where v.id = new.vendita_id;
  return new;
end;
$$;

create trigger vendita_riga_eredita_org_tg
  before insert or update of vendita_id on magazzino.vendita_riga
  for each row execute function magazzino.vendita_riga_eredita_org();

create or replace function magazzino.vendita_mod_eredita_org()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  select r.organizzazione_id into new.organizzazione_id
  from magazzino.vendita_riga r where r.id = new.vendita_riga_id;
  return new;
end;
$$;

create trigger vendita_mod_eredita_org_tg
  before insert or update of vendita_riga_id on magazzino.vendita_riga_modificatore
  for each row execute function magazzino.vendita_mod_eredita_org();

alter table magazzino.vendita                    enable row level security;
alter table magazzino.vendita_riga               enable row level security;
alter table magazzino.vendita_riga_modificatore  enable row level security;

do $$
declare t text;
begin
  foreach t in array array['vendita', 'vendita_riga', 'vendita_riga_modificatore']
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

grant execute on function magazzino.risolvi_vendita(uuid) to authenticated;
grant execute on function magazzino.scarica_vendita(uuid) to authenticated;
grant execute on function magazzino.scarica_giornata(uuid, date) to authenticated;
