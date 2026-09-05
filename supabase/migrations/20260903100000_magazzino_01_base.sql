-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 1 di 4: fondamenta e anagrafiche
-- ============================================================================
--
--  Tutto vive nello schema `magazzino`, separato da `public` dove stanno le
--  prenotazioni. Stesso database, quindi stesso login del personale e le
--  prenotazioni restano interrogabili (coperti previsti -> fabbisogno), ma i
--  nomi delle tabelle non possono collidere.
--
--  Ricordarsi di aggiungere `magazzino` agli "Exposed schemas" in
--  Impostazioni -> API, altrimenti il client Flutter non lo vede.
--  Da Dart si usa: client.schema('magazzino').from('ingrediente')
--
--  Convenzioni adottate ovunque:
--    - nomi in italiano, singolare (ingrediente, non ingredienti)
--    - ogni tabella porta `organizzazione_id`: e' l'etichetta multi-tenant
--    - le quantita' stanno SEMPRE in unita' base: g, ml, pz. Mai kg o litri.
--      Una sola scala elimina un'intera classe di errori di conversione.
--    - quantita' numeric(14,3) — al milligrammo
--    - costo per unita' base numeric(14,6) — serve davvero: il wagyu sta
--      intorno a 0,15 €/g, il riso a 0,002 €/g
--    - importi in euro numeric(12,2)
-- ============================================================================

create schema if not exists magazzino;

-- pg_trgm: similarita' fra stringhe, serve a riconoscere che
-- "MAZZANC. GIG. CT/5" e "MAZZANCOLLE GIGANTI CT 5" sono la stessa cosa.
-- unaccent: toglie gli accenti prima del confronto.
--
-- Installate esplicitamente in `extensions`, lo schema che Supabase crea
-- apposta. Senza indicarlo finirebbero in `public`, cioe' in mezzo alle
-- tabelle delle prenotazioni. Se sono gia' installate, IF NOT EXISTS non fa
-- nulla e non le sposta.
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Le estensioni possono stare in `extensions` (default Supabase) oppure in
-- `public` a seconda di come e' nato il progetto: le includiamo entrambe nel
-- search_path per non dipendere da quale delle due.
set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  Funzioni di servizio
-- ----------------------------------------------------------------------------

-- Aggiorna `aggiornato_il` a ogni UPDATE. Agganciata a tutte le tabelle
-- modificabili in fondo al file.
create or replace function magazzino.tocca_aggiornato_il()
returns trigger
language plpgsql
as $$
begin
  new.aggiornato_il = now();
  return new;
end;
$$;

-- Riduce una descrizione fornitore a una forma confrontabile:
-- "MOZZ. FDL JULIENNE 4X2,5 KG" -> "mozz fdl julienne 4x2 5 kg"
--
-- Volutamente STABLE e non IMMUTABLE: `unaccent()` a un argomento dipende dal
-- dizionario di default, quindi dichiararla immutabile sarebbe una bugia al
-- planner. Per questo le colonne normalizzate sono riempite da trigger e non
-- sono colonne generate: cosi' l'indice trigram lavora su una colonna vera.
create or replace function magazzino.normalizza(testo text)
returns text
language sql
stable
set search_path = magazzino, extensions, public
as $$
  select nullif(
           btrim(
             regexp_replace(
               lower(unaccent(coalesce(testo, ''))),
               '[^a-z0-9]+', ' ', 'g'
             )
           ),
           ''
         );
$$;

-- Vieta UPDATE e DELETE. Usata sulle tabelle che devono restare a sola
-- aggiunta: il libro mastro dei movimenti e le estrazioni AI.
create or replace function magazzino.blocca_modifica()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'La tabella %.% e'' a sola aggiunta: non si modifica e non si cancella. Per correggere, inserire un movimento di storno.',
    tg_table_schema, tg_table_name;
end;
$$;


-- ----------------------------------------------------------------------------
--  organizzazione — il "tenant"
-- ----------------------------------------------------------------------------
create table magazzino.organizzazione (
  id                uuid primary key default gen_random_uuid(),
  nome              text        not null,
  ragione_sociale   text,
  partita_iva       text,
  codice_fiscale    text,
  attiva            boolean     not null default true,
  creato_il         timestamptz not null default now(),
  aggiornato_il     timestamptz not null default now()
);

comment on table magazzino.organizzazione is
  'Un locale (o gruppo) cliente. Oggi ce n''e'' uno solo, HIO. Ogni riga di ogni altra tabella punta qui: e'' cio'' che rende il sistema rivendibile senza riscriverlo.';


-- ----------------------------------------------------------------------------
--  utente_organizzazione — chi puo' entrare e con che ruolo
-- ----------------------------------------------------------------------------
--  Volutamente NON riusa `public.staff_members` delle prenotazioni: quella
--  tabella ha un modello di permessi pensato per sala e turni. Le due si
--  popolano in parallelo (stesso auth.users), ma restano indipendenti cosi'
--  un cambio ai permessi del magazzino non tocca le prenotazioni.
--
--  Ruoli:
--    titolare  — tutto, compresa la cancellazione e la chiusura inventari
--    gestore   — carica, conferma documenti, gestisce anagrafiche
--    operatore — fotografa DDT, compila bozze, conta l'inventario;
--                NON puo' confermare un carico ne' cancellare
create table magazzino.utente_organizzazione (
  utente_id         uuid        not null references auth.users(id) on delete cascade,
  organizzazione_id uuid        not null references magazzino.organizzazione(id) on delete cascade,
  ruolo             text        not null default 'operatore'
                      check (ruolo in ('titolare', 'gestore', 'operatore')),
  attivo            boolean     not null default true,
  creato_il         timestamptz not null default now(),
  primary key (utente_id, organizzazione_id)
);

-- Restituisce le organizzazioni dell'utente collegato.
-- SECURITY DEFINER apposta: deve poter leggere `utente_organizzazione`
-- scavalcando la RLS, altrimenti le policy che la usano si chiamerebbero
-- ricorsivamente all'infinito.
create or replace function magazzino.organizzazioni_utente()
returns setof uuid
language sql
stable
security definer
set search_path = magazzino, public
as $$
  select organizzazione_id
  from magazzino.utente_organizzazione
  where utente_id = auth.uid()
    and attivo;
$$;

-- Vero se l'utente ha almeno uno dei ruoli indicati nell'organizzazione data.
create or replace function magazzino.ha_ruolo(org uuid, ruoli text[])
returns boolean
language sql
stable
security definer
set search_path = magazzino, public
as $$
  select exists (
    select 1
    from magazzino.utente_organizzazione
    where utente_id = auth.uid()
      and organizzazione_id = org
      and attivo
      and ruolo = any(ruoli)
  );
$$;


-- ----------------------------------------------------------------------------
--  deposito — i magazzini fisici
-- ----------------------------------------------------------------------------
--  Si chiama `deposito` e non `magazzino` solo per non scrivere
--  `magazzino.magazzino`, che si legge male. Per il personale restano
--  "i magazzini".
create table magazzino.deposito (
  id                 uuid primary key default gen_random_uuid(),
  organizzazione_id  uuid        not null references magazzino.organizzazione(id) on delete cascade,
  codice             text        not null,
  nome               text        not null,
  tipo               text        not null default 'ambiente'
                       check (tipo in ('ambiente', 'frigo', 'freezer')),
  temperatura_min    numeric(5,2),
  temperatura_max    numeric(5,2),
  ordinamento        smallint    not null default 0,
  attivo             boolean     not null default true,
  creato_il          timestamptz not null default now(),
  aggiornato_il      timestamptz not null default now(),
  unique (organizzazione_id, codice)
);

comment on column magazzino.deposito.temperatura_min is
  'Range di conservazione atteso. Serve alla registrazione HACCP delle temperature, non al calcolo delle giacenze.';


-- ----------------------------------------------------------------------------
--  fornitore
-- ----------------------------------------------------------------------------
create table magazzino.fornitore (
  id                 uuid primary key default gen_random_uuid(),
  organizzazione_id  uuid        not null references magazzino.organizzazione(id) on delete cascade,
  denominazione      text        not null,
  partita_iva        text,
  codice_fiscale     text,
  email              text,
  telefono           text,
  referente          text,
  giorni_consegna    text[],
  note               text,
  attivo             boolean     not null default true,
  creato_il          timestamptz not null default now(),
  aggiornato_il      timestamptz not null default now()
);

-- La partita IVA e' la chiave con cui, quando arrivera' l'XML da Arca, si
-- riconoscera' il fornitore senza chiedere niente all'operatore.
create unique index fornitore_piva_unica
  on magazzino.fornitore (organizzazione_id, partita_iva)
  where partita_iva is not null;

create index fornitore_denominazione_trgm
  on magazzino.fornitore using gin (denominazione gin_trgm_ops);


-- ----------------------------------------------------------------------------
--  categoria_ingrediente
-- ----------------------------------------------------------------------------
create table magazzino.categoria_ingrediente (
  id                 uuid primary key default gen_random_uuid(),
  organizzazione_id  uuid        not null references magazzino.organizzazione(id) on delete cascade,
  padre_id           uuid        references magazzino.categoria_ingrediente(id) on delete set null,
  nome               text        not null,
  colore             text,
  ordinamento        smallint    not null default 0,
  creato_il          timestamptz not null default now(),
  aggiornato_il      timestamptz not null default now(),
  unique (organizzazione_id, nome)
);


-- ----------------------------------------------------------------------------
--  allergene — i 14 allergeni dell'allegato II Reg. UE 1169/2011
-- ----------------------------------------------------------------------------
--  Tabella di sistema, uguale per tutti: e' un elenco di legge, non una
--  scelta del locale.
create table magazzino.allergene (
  codice      text primary key,
  nome        text     not null,
  ordinamento smallint not null default 0
);

insert into magazzino.allergene (codice, nome, ordinamento) values
  ('glutine',          'Cereali contenenti glutine',        1),
  ('crostacei',        'Crostacei',                          2),
  ('uova',             'Uova',                               3),
  ('pesce',            'Pesce',                              4),
  ('arachidi',         'Arachidi',                           5),
  ('soia',             'Soia',                               6),
  ('latte',            'Latte e derivati',                   7),
  ('frutta_a_guscio',  'Frutta a guscio',                    8),
  ('sedano',           'Sedano',                             9),
  ('senape',           'Senape',                            10),
  ('sesamo',           'Semi di sesamo',                    11),
  ('solfiti',          'Anidride solforosa e solfiti',      12),
  ('lupini',           'Lupini',                            13),
  ('molluschi',        'Molluschi',                         14);


-- ----------------------------------------------------------------------------
--  ingrediente — l'articolo interno
-- ----------------------------------------------------------------------------
--  E' il cuore dell'anagrafica. Nota il flag `vendibile_diretto`: senza quello
--  il bar non si modella. La bottiglia di gin e' contemporaneamente un
--  prodotto venduto (gin tonic, liscio) e un componente dei cocktail; deve
--  essere una sola entita', scaricabile in entrambi i modi.
create table magazzino.ingrediente (
  id                     uuid primary key default gen_random_uuid(),
  organizzazione_id      uuid        not null references magazzino.organizzazione(id) on delete cascade,
  categoria_id           uuid        references magazzino.categoria_ingrediente(id) on delete set null,
  codice_interno         text,
  nome                   text        not null,
  nome_normalizzato      text,
  nome_breve             text,

  -- Unita' base: g, ml oppure pz. Nient'altro.
  um_base                text        not null check (um_base in ('g', 'ml', 'pz')),

  -- Vero per gin, whisky, birre, vini: si vendono anche cosi' come sono.
  vendibile_diretto      boolean     not null default false,

  -- Dose standard di mescita in ml (4,5 cl = 45). Fa da distinta implicita
  -- per i prodotti venduti lisci o al tonic.
  dose_standard          numeric(14,3),

  deposito_predefinito_id uuid       references magazzino.deposito(id) on delete set null,
  conservazione          text        not null default 'ambiente'
                           check (conservazione in ('ambiente', 'frigo', 'freezer')),
  giorni_scadenza_default smallint,

  -- Pesce destinato al consumo crudo: obbligo di abbattimento documentato
  -- (Reg. CE 853/2004, -20 °C per 24 h oppure -35 °C per 15 h).
  -- Se vero, il carico non si conferma senza i dati di abbattimento.
  richiede_abbattimento  boolean     not null default false,

  scorta_minima          numeric(14,3),
  scorta_ideale          numeric(14,3),

  -- Denormalizzati per non ricalcolare a ogni schermata. La verita' resta il
  -- libro mastro: questi si ricalcolano dai movimenti (media ponderata mobile).
  costo_medio            numeric(14,6),
  ultimo_costo           numeric(14,6),
  costo_aggiornato_il    timestamptz,

  note                   text,
  attivo                 boolean     not null default true,
  creato_il              timestamptz not null default now(),
  aggiornato_il          timestamptz not null default now(),

  unique (organizzazione_id, nome)
);

create unique index ingrediente_codice_unico
  on magazzino.ingrediente (organizzazione_id, codice_interno)
  where codice_interno is not null;

create index ingrediente_nome_trgm
  on magazzino.ingrediente using gin (nome_normalizzato gin_trgm_ops);

create index ingrediente_categoria
  on magazzino.ingrediente (organizzazione_id, categoria_id)
  where attivo;

comment on column magazzino.ingrediente.costo_medio is
  'Media ponderata mobile, ricalcolata dai movimenti di carico. Valore di comodo: la fonte di verita'' e'' sempre magazzino.movimento.';

create or replace function magazzino.ingrediente_normalizza()
returns trigger
language plpgsql
as $$
begin
  new.nome_normalizzato = magazzino.normalizza(new.nome);
  return new;
end;
$$;

create trigger ingrediente_normalizza_tg
  before insert or update of nome on magazzino.ingrediente
  for each row execute function magazzino.ingrediente_normalizza();


-- ----------------------------------------------------------------------------
--  ingrediente_allergene
-- ----------------------------------------------------------------------------
--  Dichiarare gli allergeni sull'ingrediente invece che sul piatto significa
--  che, quando ci saranno le distinte base, gli allergeni dei piatti si
--  calcolano da soli e restano coerenti anche se cambi una ricetta.
create table magazzino.ingrediente_allergene (
  ingrediente_id  uuid not null references magazzino.ingrediente(id) on delete cascade,
  allergene       text not null references magazzino.allergene(codice),
  tracce          boolean not null default false,
  primary key (ingrediente_id, allergene)
);

comment on column magazzino.ingrediente_allergene.tracce is
  'Vero quando l''allergene non e'' ingrediente ma possibile contaminazione ("puo'' contenere tracce di").';


-- ----------------------------------------------------------------------------
--  articolo_fornitore — la traduzione fornitore -> ingrediente
-- ----------------------------------------------------------------------------
--  Qui vive l'intelligenza che il sistema accumula:
--    "MAZZANC. GIG. CT/5"  del fornitore X
--      -> ingrediente "Mazzancolle giganti"
--      -> 1 collo = 5000 g
--
--  La prima volta lo decide l'AI con conferma umana. Dalla seconda in poi
--  e' una lettura da tabella, senza AI e senza domande.
create table magazzino.articolo_fornitore (
  id                        uuid primary key default gen_random_uuid(),
  organizzazione_id         uuid        not null references magazzino.organizzazione(id) on delete cascade,
  fornitore_id              uuid        not null references magazzino.fornitore(id) on delete cascade,

  -- Nullo finche' l'articolo non e' stato abbinato a un ingrediente interno.
  ingrediente_id            uuid        references magazzino.ingrediente(id) on delete set null,

  codice_fornitore          text,
  ean                       text,
  descrizione_originale     text        not null,
  descrizione_normalizzata  text,

  -- Come e' scritta sul documento: 'CT', 'PZ', 'KG', 'CF', 'NR'... testo
  -- libero apposta, i fornitori ci scrivono di tutto.
  um_acquisto               text,

  -- Quante unita' base (g/ml/pz) stanno in UNA unita' d'acquisto.
  -- Cartone da 4x2,5 kg -> 10000. Bottiglia da 70 cl -> 700.
  fattore_conversione       numeric(14,4) check (fattore_conversione > 0),
  confezione_descrizione    text,

  -- Ultimo prezzo per unita' d'acquisto e il suo equivalente per unita' base:
  -- il secondo e' quello che serve al food cost.
  ultimo_prezzo             numeric(12,4),
  ultimo_prezzo_um_base     numeric(14,6),
  ultimo_acquisto_il        date,

  attivo                    boolean     not null default true,
  creato_il                 timestamptz not null default now(),
  aggiornato_il             timestamptz not null default now()
);

create unique index articolo_fornitore_codice_unico
  on magazzino.articolo_fornitore (organizzazione_id, fornitore_id, codice_fornitore)
  where codice_fornitore is not null;

create index articolo_fornitore_descrizione_trgm
  on magazzino.articolo_fornitore using gin (descrizione_normalizzata gin_trgm_ops);

create index articolo_fornitore_ingrediente
  on magazzino.articolo_fornitore (organizzazione_id, ingrediente_id);

-- Articoli mai abbinati: e' la coda di lavoro dell'operatore.
create index articolo_fornitore_da_abbinare
  on magazzino.articolo_fornitore (organizzazione_id, fornitore_id)
  where ingrediente_id is null and attivo;

create or replace function magazzino.articolo_fornitore_normalizza()
returns trigger
language plpgsql
as $$
begin
  new.descrizione_normalizzata = magazzino.normalizza(new.descrizione_originale);
  return new;
end;
$$;

create trigger articolo_fornitore_normalizza_tg
  before insert or update of descrizione_originale on magazzino.articolo_fornitore
  for each row execute function magazzino.articolo_fornitore_normalizza();


-- ----------------------------------------------------------------------------
--  alias_articolo — le grafie gia' viste
-- ----------------------------------------------------------------------------
--  Un DDT fotografato non restituisce mai due volte esattamente la stessa
--  stringa: cambia la spaziatura, l'OCR legge 0 al posto di O, il fornitore
--  cambia stampante. Ogni conferma dell'operatore deposita qui la grafia
--  incontrata, cosi' la volta dopo il riconoscimento e' esatto e non stimato.
create table magazzino.alias_articolo (
  id                     uuid primary key default gen_random_uuid(),
  organizzazione_id      uuid        not null references magazzino.organizzazione(id) on delete cascade,
  articolo_fornitore_id  uuid        not null references magazzino.articolo_fornitore(id) on delete cascade,
  testo_originale        text        not null,
  testo_normalizzato     text        not null,
  origine                text        not null default 'foto'
                           check (origine in ('foto', 'manuale', 'xml')),
  conteggio_usi          integer     not null default 1,
  ultimo_uso_il          timestamptz not null default now(),
  creato_il              timestamptz not null default now()
);

create unique index alias_articolo_unico
  on magazzino.alias_articolo (organizzazione_id, articolo_fornitore_id, testo_normalizzato);

create index alias_articolo_testo_trgm
  on magazzino.alias_articolo using gin (testo_normalizzato gin_trgm_ops);


-- ----------------------------------------------------------------------------
--  Trigger `aggiornato_il`
-- ----------------------------------------------------------------------------
create trigger organizzazione_tocca before update on magazzino.organizzazione
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger deposito_tocca before update on magazzino.deposito
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger fornitore_tocca before update on magazzino.fornitore
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger categoria_ingrediente_tocca before update on magazzino.categoria_ingrediente
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger ingrediente_tocca before update on magazzino.ingrediente
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger articolo_fornitore_tocca before update on magazzino.articolo_fornitore
  for each row execute function magazzino.tocca_aggiornato_il();
