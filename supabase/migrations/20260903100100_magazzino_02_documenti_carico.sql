-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 2 di 4: documenti di carico
-- ============================================================================
--
--  Il punto della sezione: le tre origini producono la STESSA struttura.
--
--      foto DDT     ─┐
--      form manuale ─┼──> documento_carico (bozza) ──> revisione ──> conferma
--      XML fattura  ─┘                                                  │
--                                                                       v
--                                                          movimenti + lotti
--
--  La foto non e' un flusso a parte: e' solo un modo di riempire un
--  documento che poi e' identico a uno digitato a mano. Quando arrivera'
--  l'XML da Arca non si riscrive niente, si aggiunge un'origine.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  documento_carico
-- ----------------------------------------------------------------------------
create table magazzino.documento_carico (
  id                  uuid primary key default gen_random_uuid(),
  organizzazione_id   uuid not null references magazzino.organizzazione(id) on delete cascade,
  fornitore_id        uuid references magazzino.fornitore(id) on delete restrict,

  -- Destinazione predefinita della merce. La singola riga puo' derogare
  -- (il vino va al bar anche se il resto va in cucina).
  deposito_id         uuid references magazzino.deposito(id) on delete restrict,

  tipo                text not null
                        check (tipo in ('ddt', 'fattura', 'acquisto_diretto', 'reso')),
  origine             text not null
                        check (origine in ('foto', 'manuale', 'xml')),

  numero_documento    text,
  data_documento      date not null,

  -- Il momento in cui la merce e' entrata davvero. Di norma coincide con la
  -- data documento per i DDT, ma per le fatture differite di fine mese e' la
  -- data del DDT richiamato nell'XML: i movimenti vanno datati QUI, altrimenti
  -- le giacenze sono indietro di trenta giorni.
  data_consegna       date not null default current_date,

  stato               text not null default 'bozza'
                        check (stato in ('bozza', 'in_revisione', 'confermato', 'annullato')),

  -- Dichiarato = totale letto sul documento. Calcolato = somma delle righe.
  -- Se non coincidono, l'AI ha letto male qualcosa: e' il controllo piu'
  -- economico ed efficace che abbiamo.
  totale_dichiarato   numeric(12,2),
  totale_calcolato    numeric(12,2),

  -- La fattura che comprende questo DDT. Riempito in riconciliazione quando
  -- arrivera' l'XML: il DDT ha gia' mosso il magazzino, la fattura corregge
  -- solo i prezzi e segnala le differenze fra consegnato e fatturato.
  documento_padre_id  uuid references magazzino.documento_carico(id) on delete set null,
  riconciliato_il     timestamptz,

  note                text,
  creato_da           uuid references auth.users(id) on delete set null,
  creato_il           timestamptz not null default now(),
  confermato_da       uuid references auth.users(id) on delete set null,
  confermato_il       timestamptz,
  aggiornato_il       timestamptz not null default now(),

  -- Un documento confermato deve sapere chi e quando.
  constraint documento_confermato_tracciato
    check (stato <> 'confermato' or (confermato_da is not null and confermato_il is not null))
);

-- Difesa contro il doppio carico: stesso fornitore, stesso tipo, stesso
-- numero, stessa data = stesso documento. Capita spessissimo che due persone
-- fotografino lo stesso DDT.
create unique index documento_carico_non_duplicato
  on magazzino.documento_carico (organizzazione_id, fornitore_id, tipo, numero_documento, data_documento)
  where numero_documento is not null and stato <> 'annullato';

create index documento_carico_da_lavorare
  on magazzino.documento_carico (organizzazione_id, stato, data_consegna desc)
  where stato in ('bozza', 'in_revisione');

create index documento_carico_per_fornitore
  on magazzino.documento_carico (organizzazione_id, fornitore_id, data_documento desc);

create index documento_carico_da_riconciliare
  on magazzino.documento_carico (organizzazione_id, fornitore_id, data_consegna)
  where tipo = 'ddt' and documento_padre_id is null and stato = 'confermato';


-- ----------------------------------------------------------------------------
--  documento_carico_riga
-- ----------------------------------------------------------------------------
--  Due blocchi distinti di campi, e la distinzione conta:
--    - cio' che C'ERA SCRITTO sul documento (descrizione, quantita', prezzo):
--      non si tocca mai piu', e' la prova
--    - cio' che il sistema HA CAPITO (ingrediente, quantita' in unita' base):
--      correggibile fino alla conferma
create table magazzino.documento_carico_riga (
  id                        uuid primary key default gen_random_uuid(),
  documento_id              uuid not null references magazzino.documento_carico(id) on delete cascade,
  organizzazione_id         uuid not null references magazzino.organizzazione(id) on delete cascade,
  numero_riga               smallint not null,

  -- ── Come letto sul documento ──────────────────────────────────────────
  descrizione_originale     text not null,
  descrizione_normalizzata  text,
  codice_fornitore_originale text,
  quantita_dichiarata       numeric(14,3),
  um_dichiarata             text,
  prezzo_unitario           numeric(12,4),
  sconto_percentuale        numeric(6,3),
  totale_riga               numeric(12,2),
  aliquota_iva              numeric(5,2),

  -- ── Come interpretato ─────────────────────────────────────────────────
  articolo_fornitore_id     uuid references magazzino.articolo_fornitore(id) on delete set null,
  ingrediente_id            uuid references magazzino.ingrediente(id) on delete set null,
  deposito_id               uuid references magazzino.deposito(id) on delete set null,
  fattore_conversione_applicato numeric(14,4),

  -- La quantita' che entrera' davvero in magazzino, in g/ml/pz.
  quantita_base             numeric(14,3),
  costo_unitario_base       numeric(14,6),

  -- Quanto il sistema si fida di questo abbinamento, da 0 a 1.
  -- Sopra 0,90 la riga si presenta gia' verde; sotto, chiede all'operatore.
  confidenza                numeric(4,3) check (confidenza between 0 and 1),
  metodo_match              text check (metodo_match in
                              ('codice_fornitore', 'ean', 'alias', 'similarita', 'ai', 'manuale')),

  stato_match               text not null default 'da_risolvere'
                              check (stato_match in
                                ('da_risolvere', 'suggerito', 'confermato', 'nuovo_articolo', 'ignorata')),

  -- ── Accettazione fisica ───────────────────────────────────────────────
  -- Il peso davvero pesato al banco. Sul pesce e sulla carne diverge spesso
  -- da quello scritto sul DDT, e la differenza accumulata per fornitore e'
  -- uno dei numeri piu' preziosi che questo sistema produrra'.
  -- Quando e' valorizzata, e' LEI a generare il movimento, non la dichiarata.
  quantita_reale            numeric(14,3),
  pesata_da                 uuid references auth.users(id) on delete set null,
  pesata_il                 timestamptz,

  -- ── Tracciabilita' ────────────────────────────────────────────────────
  lotto_fornitore           text,
  data_scadenza             date,

  note                      text,
  creato_il                 timestamptz not null default now(),
  aggiornato_il             timestamptz not null default now(),

  unique (documento_id, numero_riga)
);

create index documento_riga_per_documento
  on magazzino.documento_carico_riga (documento_id, numero_riga);

create index documento_riga_da_risolvere
  on magazzino.documento_carico_riga (organizzazione_id, stato_match)
  where stato_match in ('da_risolvere', 'suggerito');

create index documento_riga_per_ingrediente
  on magazzino.documento_carico_riga (organizzazione_id, ingrediente_id);

create index documento_riga_descrizione_trgm
  on magazzino.documento_carico_riga using gin (descrizione_normalizzata gin_trgm_ops);

comment on column magazzino.documento_carico_riga.quantita_reale is
  'Peso pesato in accettazione. Se presente prevale sulla quantita'' dichiarata nella generazione dei movimenti.';

create or replace function magazzino.documento_riga_normalizza()
returns trigger
language plpgsql
as $$
begin
  new.descrizione_normalizzata = magazzino.normalizza(new.descrizione_originale);
  return new;
end;
$$;

create trigger documento_riga_normalizza_tg
  before insert or update of descrizione_originale on magazzino.documento_carico_riga
  for each row execute function magazzino.documento_riga_normalizza();

-- `organizzazione_id` sulla riga e' ridondante: esiste solo per far girare la
-- RLS senza join sulla testata. Proprio per questo non la scrive l'app, la
-- eredita il trigger. Una riga con l'etichetta sbagliata sarebbe una riga
-- visibile al cliente sbagliato.
create or replace function magazzino.documento_riga_eredita_org()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  select d.organizzazione_id into new.organizzazione_id
  from magazzino.documento_carico d
  where d.id = new.documento_id;
  return new;
end;
$$;

create trigger documento_riga_eredita_org_tg
  before insert or update of documento_id on magazzino.documento_carico_riga
  for each row execute function magazzino.documento_riga_eredita_org();


-- ----------------------------------------------------------------------------
--  allegato — le foto del DDT e i PDF/XML originali
-- ----------------------------------------------------------------------------
create table magazzino.allegato (
  id                uuid primary key default gen_random_uuid(),
  organizzazione_id uuid not null references magazzino.organizzazione(id) on delete cascade,
  documento_id      uuid not null references magazzino.documento_carico(id) on delete cascade,
  percorso_storage  text not null,
  nome_file         text,
  tipo_mime         text,
  dimensione_byte   bigint,

  -- SHA-256 del file. Serve a due cose: accorgersi che si sta caricando la
  -- stessa foto due volte, e poter dimostrare che l'immagine su cui l'AI ha
  -- lavorato e' esattamente quella archiviata.
  hash_sha256       text,

  pagina            smallint not null default 1,
  creato_da         uuid references auth.users(id) on delete set null,
  creato_il         timestamptz not null default now(),

  unique (documento_id, pagina)
);

create unique index allegato_hash_unico
  on magazzino.allegato (organizzazione_id, hash_sha256)
  where hash_sha256 is not null;


-- ----------------------------------------------------------------------------
--  estrazione_ai — la scatola nera
-- ----------------------------------------------------------------------------
--  Registra ogni chiamata al modello: cosa ha risposto, con che modello, con
--  che versione di prompt, quanto e' costata.
--
--  E' a SOLA AGGIUNTA, non per pignoleria: quando fra sei mesi un carico
--  risultera' sbagliato, questa tabella e' l'unico modo per sapere se ha
--  sbagliato il modello o l'operatore che ha confermato. Se si potesse
--  aggiornare, quella distinzione sparirebbe.
create table magazzino.estrazione_ai (
  id                uuid primary key default gen_random_uuid(),
  organizzazione_id uuid not null references magazzino.organizzazione(id) on delete cascade,
  documento_id      uuid not null references magazzino.documento_carico(id) on delete cascade,

  modello           text not null,
  versione_prompt   text not null,
  stato             text not null check (stato in ('completata', 'errore')),

  -- La risposta grezza del modello, prima di qualunque interpretazione.
  payload           jsonb,
  errore            text,

  token_input       integer,
  token_output      integer,
  durata_ms         integer,
  creato_il         timestamptz not null default now()
);

create index estrazione_ai_per_documento
  on magazzino.estrazione_ai (documento_id, creato_il desc);

-- La riga si scrive una volta sola, a chiamata conclusa: nessuno stato
-- "in corso" da aggiornare dopo.
create trigger estrazione_ai_sola_aggiunta
  before update or delete on magazzino.estrazione_ai
  for each row execute function magazzino.blocca_modifica();


-- ----------------------------------------------------------------------------
--  Trigger `aggiornato_il`
-- ----------------------------------------------------------------------------
create trigger documento_carico_tocca before update on magazzino.documento_carico
  for each row execute function magazzino.tocca_aggiornato_il();
create trigger documento_carico_riga_tocca before update on magazzino.documento_carico_riga
  for each row execute function magazzino.tocca_aggiornato_il();
