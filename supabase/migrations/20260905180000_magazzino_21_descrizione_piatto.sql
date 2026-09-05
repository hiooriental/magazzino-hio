-- ============================================================================
--  MAGAZZINO HIO — file 21: la descrizione del piatto
-- ============================================================================
--
--  Duecentoventicinque piatti a menù e nessuna ricetta: normale, perché il
--  menu dice COSA c'è dentro a parole e non QUANTI GRAMMI. Le quantità non si
--  possono indovinare — un numero inventato produrrebbe un food cost sbagliato
--  e uno scarico sbagliato, in silenzio, che è il guasto peggiore di tutti.
--
--  Quello che si può fare è togliere di mezzo il lavoro inutile: mentre si
--  compone la ricetta, avere sotto gli occhi la descrizione del menu evita di
--  andarsela a cercare sul sito e di dimenticare metà degli ingredienti.
--
--    «Tartare di salmone | erba cipollina | teriyaki allo yuzu | avocado |
--     riso giapponese aromatizzato con crema di risotto al limone»
--
--  Da lì gli ingredienti si aggiungono in fila, e restano da decidere solo i
--  grammi — che è l'unica cosa che deve deciderla una persona.
-- ============================================================================

set search_path = magazzino, extensions, public;

alter table magazzino.prodotto_venduto
  add column if not exists descrizione text;

comment on column magazzino.prodotto_venduto.descrizione is
  'La descrizione come compare a menù. Non serve ai calcoli: serve a chi compone la ricetta per non doversi ricordare cosa c''è dentro il piatto.';
