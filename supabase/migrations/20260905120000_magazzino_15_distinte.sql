-- ============================================================================
--  MAGAZZINO HIO — Sezione 2, file 15: distinte base
-- ============================================================================
--
--  Le ricette. Cosa contiene un piatto, cosa contiene un semilavorato.
--
--  Due scelte che reggono tutto il resto:
--
--  1. UN SEMILAVORATO È UN INGREDIENTE.
--     Il riso condito non si compra, si produce. Ma si stocca, si conta a
--     inventario, ha un costo al grammo e finisce dentro altre ricette: fa
--     esattamente quello che fa un ingrediente. Serve una bandiera
--     (`prodotto_internamente`), non una tabella nuova.
--
--  2. L'ESPLOSIONE SI FERMA SUI SEMILAVORATI.
--     Una ricetta scarica 250 g di riso condito, non riso crudo + aceto +
--     zucchero: quelli sono già usciti dal magazzino quando il riso è stato
--     preparato. Esplodere fino alle materie prime scaricherebbe due volte.
--
--  Da qui discende una cosa comoda: il costo di una ricetta è la semplice
--  somma di quantità per costo medio, senza ricorsione. Il costo medio dei
--  semilavorati arriva dai movimenti di produzione, che sono già registrati
--  nel libro mastro come qualunque altro carico.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  L'ingrediente può essere prodotto in casa
-- ----------------------------------------------------------------------------
alter table magazzino.ingrediente
  add column if not exists prodotto_internamente boolean not null default false;

comment on column magazzino.ingrediente.prodotto_internamente is
  'Semilavorato: riso condito, salse, brodi, tranci ricavati da un pezzo intero. Ha una distinta e un costo che nasce dalle lavorazioni invece che dagli acquisti.';


-- ----------------------------------------------------------------------------
--  prodotto_venduto
-- ----------------------------------------------------------------------------
--  Quello che compare sullo scontrino. Il `codice_esterno` è la chiave verso
--  iPratico: dev'essere un identificativo STABILE nel tempo, non il nome —
--  se il nome cambia («Tartare di tonno» → «Tartare di tonno Fuentes») il
--  collegamento con la ricetta non deve rompersi.
create table magazzino.prodotto_venduto (
  id                 uuid primary key default gen_random_uuid(),
  organizzazione_id  uuid not null references magazzino.organizzazione(id) on delete cascade,

  codice_esterno     text,
  nome               text not null,
  categoria_menu     text,
  prezzo_vendita     numeric(10,2),

  -- Prodotti che non consumano magazzino: coperto, servizio, buoni.
  senza_distinta     boolean not null default false,

  attivo             boolean not null default true,
  creato_il          timestamptz not null default now(),
  aggiornato_il      timestamptz not null default now(),

  unique (organizzazione_id, nome)
);

create unique index prodotto_venduto_codice_unico
  on magazzino.prodotto_venduto (organizzazione_id, codice_esterno)
  where codice_esterno is not null;

create index prodotto_venduto_attivi
  on magazzino.prodotto_venduto (organizzazione_id, categoria_menu)
  where attivo;


-- ----------------------------------------------------------------------------
--  distinta
-- ----------------------------------------------------------------------------
--  Una distinta descrive O un prodotto venduto O un semilavorato, mai
--  entrambi. Le versioni si accumulano: cambiare una ricetta non deve
--  riscrivere il costo dei piatti già venduti il mese scorso.
create table magazzino.distinta (
  id                    uuid primary key default gen_random_uuid(),
  organizzazione_id     uuid not null references magazzino.organizzazione(id) on delete cascade,

  prodotto_venduto_id   uuid references magazzino.prodotto_venduto(id) on delete cascade,
  ingrediente_id        uuid references magazzino.ingrediente(id) on delete cascade,

  versione              smallint not null default 1,
  valida_da             date not null default current_date,
  stato                 text not null default 'bozza'
                          check (stato in ('bozza', 'attiva', 'archiviata')),

  -- Solo per i semilavorati: quanto ne esce da una preparazione intera.
  -- 40 kg di riso condito da una cotta. Serve a dividere il costo degli
  -- ingredienti sulla quantità prodotta.
  quantita_prodotta     numeric(14,3),

  -- Piatti ad assortimento: «Sushi selection 24pz» cambia composizione ogni
  -- giorno secondo il pescato. La distinta esiste ma è una media, e il
  -- consumo va dichiarato a parte. Segnalarlo evita di prendere per esatto
  -- un numero che non lo è.
  variabile             boolean not null default false,

  note                  text,
  creato_da             uuid references auth.users(id) on delete set null,
  creato_il             timestamptz not null default now(),
  aggiornato_il         timestamptz not null default now(),

  -- Una distinta descrive una cosa sola.
  constraint distinta_un_solo_bersaglio check (
    (prodotto_venduto_id is not null and ingrediente_id is null) or
    (prodotto_venduto_id is null and ingrediente_id is not null)
  ),
  -- Un semilavorato senza resa non permette di calcolare il costo unitario.
  constraint distinta_semilavorato_con_resa check (
    ingrediente_id is null or coalesce(quantita_prodotta, 0) > 0
  )
);

-- Una sola distinta attiva per prodotto e per semilavorato.
create unique index distinta_attiva_prodotto
  on magazzino.distinta (prodotto_venduto_id)
  where stato = 'attiva' and prodotto_venduto_id is not null;

create unique index distinta_attiva_ingrediente
  on magazzino.distinta (ingrediente_id)
  where stato = 'attiva' and ingrediente_id is not null;

create index distinta_per_organizzazione
  on magazzino.distinta (organizzazione_id, stato);


-- ----------------------------------------------------------------------------
--  distinta_componente
-- ----------------------------------------------------------------------------
create table magazzino.distinta_componente (
  id                  uuid primary key default gen_random_uuid(),
  distinta_id         uuid not null references magazzino.distinta(id) on delete cascade,
  organizzazione_id   uuid not null references magazzino.organizzazione(id) on delete cascade,
  ingrediente_id      uuid not null references magazzino.ingrediente(id) on delete restrict,

  -- Nell'unità base dell'ingrediente: grammi, millilitri, pezzi.
  quantita            numeric(14,3) not null check (quantita > 0),

  -- Quanto se ne perde lavorandolo: bucce, ritagli, cali di cottura.
  -- Il consumo reale è quantita / (1 - scarto/100): per avere 100 g di
  -- avocado nel piatto con il 30% di scarto ne servono 143.
  scarto_percentuale  numeric(5,2) not null default 0
                        check (scarto_percentuale >= 0 and scarto_percentuale < 100),

  -- Falso per i «senza»: se manca non blocca la produzione.
  obbligatorio        boolean not null default true,
  ordinamento         smallint not null default 0,
  note                text,
  creato_il           timestamptz not null default now(),
  aggiornato_il       timestamptz not null default now(),

  unique (distinta_id, ingrediente_id)
);

create index distinta_componente_per_distinta
  on magazzino.distinta_componente (distinta_id, ordinamento);

create index distinta_componente_per_ingrediente
  on magazzino.distinta_componente (organizzazione_id, ingrediente_id);

comment on column magazzino.distinta_componente.scarto_percentuale is
  'Percentuale persa nella lavorazione. Il consumo effettivo è quantita / (1 - scarto/100).';


-- ----------------------------------------------------------------------------
--  modificatore
-- ----------------------------------------------------------------------------
--  Le aggiunte e i «senza». Senza questi il consumo teorico è
--  sistematicamente più basso del reale, e la differenza sembra un
--  ammanco quando invece è doppia mozzarella pagata dal cliente.
create table magazzino.modificatore (
  id                 uuid primary key default gen_random_uuid(),
  organizzazione_id  uuid not null references magazzino.organizzazione(id) on delete cascade,
  codice_esterno     text,
  nome               text not null,
  tipo               text not null default 'aggiunta'
                       check (tipo in ('aggiunta', 'rimozione')),
  prezzo             numeric(10,2),
  attivo             boolean not null default true,
  creato_il          timestamptz not null default now(),
  aggiornato_il      timestamptz not null default now(),
  unique (organizzazione_id, nome)
);

create unique index modificatore_codice_unico
  on magazzino.modificatore (organizzazione_id, codice_esterno)
  where codice_esterno is not null;


create table magazzino.modificatore_componente (
  id                 uuid primary key default gen_random_uuid(),
  modificatore_id    uuid not null references magazzino.modificatore(id) on delete cascade,
  organizzazione_id  uuid not null references magazzino.organizzazione(id) on delete cascade,
  ingrediente_id     uuid not null references magazzino.ingrediente(id) on delete restrict,
  -- Sempre positiva: è il TIPO del modificatore a dire se si aggiunge o si
  -- toglie. Tenere il segno qui vorrebbe dire poterlo contraddire.
  quantita           numeric(14,3) not null check (quantita > 0),
  scarto_percentuale numeric(5,2) not null default 0,
  creato_il          timestamptz not null default now(),
  unique (modificatore_id, ingrediente_id)
);


-- ----------------------------------------------------------------------------
--  Costo di un ingrediente
-- ----------------------------------------------------------------------------
--  Normalmente è il costo medio, che nasce dagli acquisti o dalle produzioni.
--
--  L'eccezione è il semilavorato mai ancora prodotto: non ha storia, quindi
--  il costo si stima dalla sua distinta. Da lì la ricorsione, con un limite
--  di profondità: una ricetta che contiene se stessa è un errore di
--  inserimento, e senza limite manderebbe in stallo la query invece di
--  segnalarlo.
create or replace function magazzino.costo_ingrediente(
  p_ingrediente_id uuid,
  p_profondita     integer default 0
)
returns numeric
language plpgsql
stable
security invoker
set search_path = magazzino, public
as $$
declare
  v_ing     magazzino.ingrediente%rowtype;
  v_distinta uuid;
  v_resa    numeric;
  v_totale  numeric := 0;
  v_c       record;
begin
  if p_profondita > 6 then
    raise exception 'Distinte annidate troppo in profondità: probabile ricetta che contiene se stessa.';
  end if;

  select * into v_ing from magazzino.ingrediente where id = p_ingrediente_id;
  if not found then return null; end if;

  if v_ing.costo_medio is not null then
    return v_ing.costo_medio;
  end if;

  if not v_ing.prodotto_internamente then
    return null;
  end if;

  select id, quantita_prodotta into v_distinta, v_resa
  from magazzino.distinta
  where ingrediente_id = p_ingrediente_id and stato = 'attiva';

  if v_distinta is null or coalesce(v_resa, 0) = 0 then
    return null;
  end if;

  for v_c in
    select ingrediente_id, quantita, scarto_percentuale
    from magazzino.distinta_componente
    where distinta_id = v_distinta
  loop
    v_totale := v_totale
      + (v_c.quantita / (1 - v_c.scarto_percentuale / 100.0))
      * coalesce(magazzino.costo_ingrediente(v_c.ingrediente_id, p_profondita + 1), 0);
  end loop;

  return v_totale / v_resa;
end;
$$;


-- ----------------------------------------------------------------------------
--  Costo di una distinta
-- ----------------------------------------------------------------------------
create or replace function magazzino.costo_distinta(p_distinta_id uuid)
returns numeric
language sql
stable
security invoker
set search_path = magazzino, public
as $$
  select coalesce(sum(
           (c.quantita / (1 - c.scarto_percentuale / 100.0))
           * coalesce(magazzino.costo_ingrediente(c.ingrediente_id), 0)
         ), 0)
  from magazzino.distinta_componente c
  where c.distinta_id = p_distinta_id;
$$;

comment on function magazzino.costo_distinta(uuid) is
  'Costo di una ricetta ai costi medi correnti. Gli ingredienti senza costo medio contano zero: il totale è quindi un limite inferiore, e la vista food_cost segnala quanti ne mancano.';


-- ----------------------------------------------------------------------------
--  Vista: food cost per prodotto venduto
-- ----------------------------------------------------------------------------
create or replace view magazzino.food_cost
with (security_invoker = true)
as
select
  p.organizzazione_id,
  p.id                        as prodotto_id,
  p.nome                      as prodotto,
  p.categoria_menu,
  p.prezzo_vendita,
  d.id                        as distinta_id,
  d.variabile                 as composizione_variabile,
  round(magazzino.costo_distinta(d.id), 4)  as costo,
  round(p.prezzo_vendita - magazzino.costo_distinta(d.id), 2) as margine,
  case when coalesce(p.prezzo_vendita, 0) > 0
       then round(100 * magazzino.costo_distinta(d.id) / p.prezzo_vendita, 1)
  end                         as incidenza_percentuale,
  (select count(*) from magazzino.distinta_componente c
    where c.distinta_id = d.id)                              as componenti,
  -- Quanti componenti non hanno ancora un costo. Finché è maggiore di zero
  -- il food cost è sottostimato, e va detto invece che lasciato credere.
  (select count(*) from magazzino.distinta_componente c
     join magazzino.ingrediente i on i.id = c.ingrediente_id
    where c.distinta_id = d.id and i.costo_medio is null)    as componenti_senza_costo
from magazzino.prodotto_venduto p
join magazzino.distinta d
  on d.prodotto_venduto_id = p.id and d.stato = 'attiva'
where p.attivo;

comment on view magazzino.food_cost is
  'Costo, margine e incidenza per ogni prodotto con una distinta attiva. `componenti_senza_costo` maggiore di zero significa che il costo mostrato è più basso di quello vero.';


-- ----------------------------------------------------------------------------
--  Trigger
-- ----------------------------------------------------------------------------
create trigger prodotto_venduto_tocca before update on magazzino.prodotto_venduto
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger distinta_tocca before update on magazzino.distinta
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger distinta_componente_tocca before update on magazzino.distinta_componente
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger modificatore_tocca before update on magazzino.modificatore
  for each row execute function magazzino.tocca_aggiornato_il();

-- L'organizzazione delle righe si eredita dalla testata, come per i documenti:
-- è una colonna ridondante che serve solo alla RLS, e lasciarla scrivere
-- all'app significherebbe poterla sbagliare.
create or replace function magazzino.componente_eredita_org()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  select d.organizzazione_id into new.organizzazione_id
  from magazzino.distinta d where d.id = new.distinta_id;
  return new;
end;
$$;

create trigger distinta_componente_eredita_org_tg
  before insert or update of distinta_id on magazzino.distinta_componente
  for each row execute function magazzino.componente_eredita_org();

create or replace function magazzino.modificatore_componente_eredita_org()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  select m.organizzazione_id into new.organizzazione_id
  from magazzino.modificatore m where m.id = new.modificatore_id;
  return new;
end;
$$;

create trigger modificatore_componente_eredita_org_tg
  before insert or update of modificatore_id on magazzino.modificatore_componente
  for each row execute function magazzino.modificatore_componente_eredita_org();


-- ----------------------------------------------------------------------------
--  Sicurezza
-- ----------------------------------------------------------------------------
alter table magazzino.prodotto_venduto        enable row level security;
alter table magazzino.distinta                enable row level security;
alter table magazzino.distinta_componente     enable row level security;
alter table magazzino.modificatore            enable row level security;
alter table magazzino.modificatore_componente enable row level security;

do $$
declare t text;
begin
  -- Le ricette le legge chiunque sia membro; le cambiano titolare e gestore.
  -- Un operatore che modifica una distinta cambierebbe il costo di tutti i
  -- piatti venduti da lì in avanti, senza che nessuno se ne accorga.
  foreach t in array array[
    'prodotto_venduto', 'distinta', 'distinta_componente',
    'modificatore', 'modificatore_componente'
  ]
  loop
    execute format($f$
      create policy %1$s_lettura on magazzino.%1$s
        for select to authenticated
        using (organizzazione_id in (select magazzino.organizzazioni_utente()));
      create policy %1$s_scrittura on magazzino.%1$s
        for all to authenticated
        using (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']))
        with check (magazzino.ha_ruolo(organizzazione_id, array['titolare','gestore']));
    $f$, t);
  end loop;
end;
$$;

grant execute on function magazzino.costo_ingrediente(uuid, integer) to authenticated;
grant execute on function magazzino.costo_distinta(uuid) to authenticated;
