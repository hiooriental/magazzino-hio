-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 3 di 4: lotti, movimenti, inventari
-- ============================================================================
--
--  Regola non negoziabile: NESSUNA tabella ha un campo "giacenza".
--  La giacenza e' la somma dei movimenti, e basta.
--
--  Costa qualche join in piu' ma restituisce una cosa che un campo contatore
--  non puo' dare: la possibilita' di rispondere sempre alla domanda
--  "perche' la mozzarella e' 37,4 kg e non 40?" risalendo movimento per
--  movimento fino alla riga di DDT che l'ha caricata.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  causale — perche' la merce si e' mossa
-- ----------------------------------------------------------------------------
--  Tabella di sistema, uguale per tutte le organizzazioni.
create table magazzino.causale (
  codice             text primary key,
  descrizione        text not null,

  -- '+' solo carichi, '-' solo scarichi, 'B' entrambi i segni ammessi
  segno              char(1) not null check (segno in ('+', '-', 'B')),

  -- Se vero, questo movimento concorre al ricalcolo del costo medio.
  -- Un carico d'acquisto si', una rettifica d'inventario no: altrimenti un
  -- errore di conteggio inquinerebbe il food cost.
  influenza_costo    boolean not null default false,

  richiede_documento boolean not null default false,
  ordinamento        smallint not null default 0,
  attiva             boolean not null default true
);

insert into magazzino.causale
  (codice, descrizione, segno, influenza_costo, richiede_documento, ordinamento) values
  ('carico_acquisto',      'Carico da acquisto',                '+', true,  true,  10),
  ('reso_fornitore',       'Reso al fornitore',                 '-', true,  true,  20),
  ('carico_produzione',    'Carico da produzione interna',      '+', true,  false, 30),
  ('scarico_produzione',   'Scarico per produzione interna',    '-', false, false, 40),
  ('scarico_vendita',      'Scarico da vendita',                '-', false, false, 50),
  ('rettifica_inventario', 'Rettifica da inventario',           'B', false, false, 60),
  ('scarto',               'Scarto, rottura, deterioramento',   '-', false, false, 70),
  ('omaggio',              'Omaggio alla clientela',            '-', false, false, 80),
  ('pasto_personale',      'Pasto del personale',               '-', false, false, 90),
  ('trasferimento_uscita', 'Trasferimento, uscita',             '-', false, false, 100),
  ('trasferimento_entrata','Trasferimento, entrata',            '+', false, false, 110),
  ('storno',               'Storno di un movimento errato',     'B', false, false, 120),
  ('rimanenza_iniziale',   'Rimanenza iniziale',                '+', true,  false, 130);

comment on table magazzino.causale is
  'Elenco chiuso dei motivi per cui la merce si muove. Aggiungere una causale richiede una migrazione: e'' voluto, perche'' ogni causale nuova cambia il modo in cui si legge lo scostamento fra teorico e reale.';


-- ----------------------------------------------------------------------------
--  lotto
-- ----------------------------------------------------------------------------
--  Generato automaticamente alla conferma di un carico. Per il pesce servito
--  crudo porta anche i dati di abbattimento: cosi' la tracciabilita' HACCP
--  esce come effetto collaterale del magazzino, senza registri separati.
create table magazzino.lotto (
  id                        uuid primary key default gen_random_uuid(),
  organizzazione_id         uuid not null references magazzino.organizzazione(id) on delete cascade,
  ingrediente_id            uuid not null references magazzino.ingrediente(id) on delete restrict,
  fornitore_id              uuid references magazzino.fornitore(id) on delete set null,

  -- Codice interno leggibile, del tipo 2026-0917. E' quello che finisce
  -- sull'etichetta della vaschetta.
  codice                    text not null,
  lotto_fornitore           text,

  documento_riga_id         uuid references magazzino.documento_carico_riga(id) on delete set null,

  data_carico               date not null default current_date,
  data_scadenza             date,

  -- ── Abbattimento (Reg. CE 853/2004) ───────────────────────────────────
  abbattuto                 boolean not null default false,
  data_abbattimento_inizio  timestamptz,
  data_abbattimento_fine    timestamptz,
  temperatura_abbattimento  numeric(5,2),
  abbattuto_da              uuid references auth.users(id) on delete set null,

  quantita_iniziale         numeric(14,3) not null,
  costo_unitario            numeric(14,6),

  stato                     text not null default 'attivo'
                              check (stato in ('attivo', 'esaurito', 'scartato', 'bloccato')),
  note                      text,
  creato_il                 timestamptz not null default now(),
  aggiornato_il             timestamptz not null default now(),

  unique (organizzazione_id, ingrediente_id, codice),

  -- Se e' dichiarato abbattuto, i dati devono esserci davvero.
  constraint lotto_abbattimento_completo
    check (not abbattuto or (data_abbattimento_inizio is not null
                             and data_abbattimento_fine is not null
                             and temperatura_abbattimento is not null))
);

create index lotto_per_ingrediente
  on magazzino.lotto (organizzazione_id, ingrediente_id, data_carico desc);

create index lotto_in_scadenza
  on magazzino.lotto (organizzazione_id, data_scadenza)
  where stato = 'attivo' and data_scadenza is not null;


-- ----------------------------------------------------------------------------
--  movimento — il libro mastro
-- ----------------------------------------------------------------------------
--  A SOLA AGGIUNTA. Non si aggiorna e non si cancella: un movimento
--  sbagliato si corregge con un movimento di storno che lo referenzia.
--  E' la stessa disciplina della partita doppia, e per lo stesso motivo:
--  un registro riscrivibile non e' una prova di niente.
create table magazzino.movimento (
  id                     bigint generated always as identity primary key,
  organizzazione_id      uuid not null references magazzino.organizzazione(id) on delete cascade,

  ingrediente_id         uuid not null references magazzino.ingrediente(id) on delete restrict,
  deposito_id            uuid not null references magazzino.deposito(id) on delete restrict,
  lotto_id               uuid references magazzino.lotto(id) on delete restrict,

  causale_codice         text not null references magazzino.causale(codice),

  -- Con segno: positiva in entrata, negativa in uscita. Sempre in unita' base.
  quantita               numeric(14,3) not null check (quantita <> 0),
  costo_unitario         numeric(14,6),
  valore                 numeric(20,6) generated always as (quantita * costo_unitario) stored,

  -- Quando la merce si e' mossa davvero (puo' essere retrodatata: fattura
  -- differita che richiama un DDT di tre settimane prima).
  data_competenza        date not null default current_date,
  -- Quando la riga e' stata scritta. Non coincidono, e serve saperlo.
  registrato_il          timestamptz not null default now(),

  documento_riga_id      uuid references magazzino.documento_carico_riga(id) on delete restrict,

  -- Aggancio generico per cio' che arrivera' con la Sezione 2:
  -- 'vendita', 'lavorazione', 'inventario', 'trasferimento'.
  -- E' il motivo per cui la Sezione 2 aggiungera' tabelle senza toccare
  -- nessuna di queste.
  riferimento_tipo       text,
  riferimento_id         uuid,

  -- Nei trasferimenti: l'altro deposito coinvolto.
  deposito_controparte_id uuid references magazzino.deposito(id) on delete set null,

  -- Se questa riga e' uno storno, punta al movimento che annulla.
  movimento_stornato_id  bigint references magazzino.movimento(id) on delete restrict,

  note                   text,
  creato_da              uuid references auth.users(id) on delete set null
);

comment on table magazzino.movimento is
  'Libro mastro del magazzino. Sola aggiunta. La giacenza e'' la somma di queste righe: non esiste da nessuna parte un campo che la contenga.';

create index movimento_giacenza
  on magazzino.movimento (organizzazione_id, ingrediente_id, deposito_id);

create index movimento_cronologico
  on magazzino.movimento (organizzazione_id, data_competenza desc, id desc);

create index movimento_per_lotto
  on magazzino.movimento (lotto_id)
  where lotto_id is not null;

create index movimento_per_documento
  on magazzino.movimento (documento_riga_id)
  where documento_riga_id is not null;

create index movimento_per_riferimento
  on magazzino.movimento (riferimento_tipo, riferimento_id)
  where riferimento_id is not null;

create trigger movimento_sola_aggiunta
  before update or delete on magazzino.movimento
  for each row execute function magazzino.blocca_modifica();

-- Il segno deve rispettare la causale.
create or replace function magazzino.movimento_verifica_segno()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
declare
  s char(1);
begin
  select segno into s from magazzino.causale where codice = new.causale_codice;

  if s = '+' and new.quantita < 0 then
    raise exception 'La causale % ammette solo carichi, ricevuta quantita'' %', new.causale_codice, new.quantita;
  elsif s = '-' and new.quantita > 0 then
    raise exception 'La causale % ammette solo scarichi, ricevuta quantita'' %', new.causale_codice, new.quantita;
  end if;

  return new;
end;
$$;

create trigger movimento_verifica_segno_tg
  before insert on magazzino.movimento
  for each row execute function magazzino.movimento_verifica_segno();


-- ----------------------------------------------------------------------------
--  Viste di giacenza
-- ----------------------------------------------------------------------------
--  security_invoker = true e' essenziale: senza, la vista girerebbe con i
--  privilegi di chi l'ha creata e scavalcherebbe la RLS, mostrando a un
--  cliente i dati di un altro.

create view magazzino.giacenza
  with (security_invoker = true)
as
select
  m.organizzazione_id,
  m.ingrediente_id,
  m.deposito_id,
  sum(m.quantita)                                as quantita,
  max(m.data_competenza)                         as ultimo_movimento_il,
  count(*)                                       as numero_movimenti
from magazzino.movimento m
group by m.organizzazione_id, m.ingrediente_id, m.deposito_id
having sum(m.quantita) <> 0;

comment on view magazzino.giacenza is
  'Giacenza per ingrediente e deposito. Se diventa lenta si sostituisce con una vista materializzata aggiornata a ogni movimento: la firma resta questa, l''app non cambia.';


create view magazzino.giacenza_valorizzata
  with (security_invoker = true)
as
select
  g.organizzazione_id,
  g.ingrediente_id,
  i.nome                        as ingrediente,
  i.um_base,
  g.deposito_id,
  d.nome                        as deposito,
  g.quantita,
  i.costo_medio,
  round(g.quantita * coalesce(i.costo_medio, 0), 2) as valore,
  i.scorta_minima,
  (i.scorta_minima is not null and g.quantita < i.scorta_minima) as sotto_scorta,
  g.ultimo_movimento_il
from magazzino.giacenza g
join magazzino.ingrediente i on i.id = g.ingrediente_id
join magazzino.deposito    d on d.id = g.deposito_id;


create view magazzino.giacenza_lotto
  with (security_invoker = true)
as
select
  m.organizzazione_id,
  m.lotto_id,
  l.ingrediente_id,
  l.codice                as lotto,
  l.data_scadenza,
  l.abbattuto,
  m.deposito_id,
  sum(m.quantita)         as quantita
from magazzino.movimento m
join magazzino.lotto l on l.id = m.lotto_id
where m.lotto_id is not null
group by m.organizzazione_id, m.lotto_id, l.ingrediente_id, l.codice,
         l.data_scadenza, l.abbattuto, m.deposito_id
having sum(m.quantita) <> 0;

comment on view magazzino.giacenza_lotto is
  'Quanto resta di ogni lotto. E'' la base della tracciabilita'': dato un lotto si risale al DDT che l''ha portato, e dai movimenti si vede dov''e'' finito.';


-- ----------------------------------------------------------------------------
--  inventario
-- ----------------------------------------------------------------------------
create table magazzino.inventario (
  id                uuid primary key default gen_random_uuid(),
  organizzazione_id uuid not null references magazzino.organizzazione(id) on delete cascade,
  deposito_id       uuid not null references magazzino.deposito(id) on delete restrict,
  data_inventario   date not null default current_date,
  descrizione       text,
  stato             text not null default 'aperto'
                      check (stato in ('aperto', 'chiuso', 'annullato')),
  note              text,
  creato_da         uuid references auth.users(id) on delete set null,
  creato_il         timestamptz not null default now(),
  chiuso_da         uuid references auth.users(id) on delete set null,
  chiuso_il         timestamptz,
  aggiornato_il     timestamptz not null default now()
);

-- Un solo inventario aperto per deposito alla volta: due conteggi paralleli
-- sullo stesso frigo producono rettifiche che si annullano a vicenda.
create unique index inventario_uno_aperto_per_deposito
  on magazzino.inventario (organizzazione_id, deposito_id)
  where stato = 'aperto';


create table magazzino.inventario_riga (
  id                uuid primary key default gen_random_uuid(),
  inventario_id     uuid not null references magazzino.inventario(id) on delete cascade,
  organizzazione_id uuid not null references magazzino.organizzazione(id) on delete cascade,
  ingrediente_id    uuid not null references magazzino.ingrediente(id) on delete restrict,
  lotto_id          uuid references magazzino.lotto(id) on delete set null,

  -- Fotografia della giacenza calcolata nel momento del conteggio: senza,
  -- riaprendo l'inventario domani la differenza risulterebbe diversa.
  quantita_teorica  numeric(14,3) not null default 0,
  quantita_contata  numeric(14,3),

  -- ── Conteggio a peso, per il bar ──────────────────────────────────────
  -- Una bottiglia stimata "a vista" sbaglia del 20%. Pesata con tara e
  -- densita' sbaglia dell'1%. Con 28 gin, 11 whisky e 8 champagne in casa,
  -- la differenza fra i due metodi vale piu' di quanto sembri.
  peso_lordo_g      numeric(14,3),
  tara_g            numeric(14,3),
  densita           numeric(6,4),

  differenza        numeric(14,3) generated always as
                      (coalesce(quantita_contata, 0) - quantita_teorica) stored,
  costo_unitario    numeric(14,6),

  note              text,
  contato_da        uuid references auth.users(id) on delete set null,
  contato_il        timestamptz,
  creato_il         timestamptz not null default now(),
  aggiornato_il     timestamptz not null default now(),

  -- NULLS NOT DISTINCT (Postgres 15+): senza, due righe con lotto_id nullo
  -- per lo stesso ingrediente passerebbero il vincolo, e l'inventario
  -- conterebbe due volte la stessa cosa.
  unique nulls not distinct (inventario_id, ingrediente_id, lotto_id)
);

create index inventario_riga_per_inventario
  on magazzino.inventario_riga (inventario_id);

-- L'organizzazione della riga non si dichiara: si eredita dalla testata.
-- E' una colonna ridondante, tenuta solo per far girare la RLS senza join;
-- lasciarla scrivere all'app significherebbe che una riga con l'etichetta
-- sbagliata diventa una riga visibile al cliente sbagliato.
create or replace function magazzino.inventario_riga_eredita_org()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  select i.organizzazione_id into new.organizzazione_id
  from magazzino.inventario i
  where i.id = new.inventario_id;
  return new;
end;
$$;

create trigger inventario_riga_eredita_org_tg
  before insert or update of inventario_id on magazzino.inventario_riga
  for each row execute function magazzino.inventario_riga_eredita_org();

comment on column magazzino.inventario_riga.densita is
  'g/ml del liquido, per convertire il peso netto in millilitri. Distillati intorno a 0,94; sciroppi molto piu'' alti.';


-- ----------------------------------------------------------------------------
--  storico_prezzo
-- ----------------------------------------------------------------------------
--  Ogni riga di carico confermata deposita qui il prezzo. E' la base del food
--  cost e degli avvisi sui rincari ("il tonno e' salito del 14% in un mese").
create table magazzino.storico_prezzo (
  id                    uuid primary key default gen_random_uuid(),
  organizzazione_id     uuid not null references magazzino.organizzazione(id) on delete cascade,
  ingrediente_id        uuid not null references magazzino.ingrediente(id) on delete cascade,
  fornitore_id          uuid references magazzino.fornitore(id) on delete set null,
  articolo_fornitore_id uuid references magazzino.articolo_fornitore(id) on delete set null,
  documento_riga_id     uuid references magazzino.documento_carico_riga(id) on delete set null,

  data                  date not null,
  -- Prezzo per unita' d'acquisto (per collo, per cassa).
  prezzo_acquisto       numeric(12,4),
  -- Lo stesso prezzo per unita' base: e' questo il numero confrontabile
  -- nel tempo e fra fornitori diversi.
  prezzo_um_base        numeric(14,6) not null,

  creato_il             timestamptz not null default now()
);

create index storico_prezzo_serie
  on magazzino.storico_prezzo (organizzazione_id, ingrediente_id, data desc);

create index storico_prezzo_per_fornitore
  on magazzino.storico_prezzo (organizzazione_id, fornitore_id, data desc);


-- ----------------------------------------------------------------------------
--  Trigger `aggiornato_il`
-- ----------------------------------------------------------------------------
create trigger lotto_tocca before update on magazzino.lotto
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger inventario_tocca before update on magazzino.inventario
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger inventario_riga_tocca before update on magazzino.inventario_riga
  for each row execute function magazzino.tocca_aggiornato_il();
