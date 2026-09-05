-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 13: far capire l'elenco a colpo d'occhio
-- ============================================================================
--
--  Due difetti visti usando l'app con documenti veri.
--
--  1. L'elenco diceva "Fornitore da indicare" su tutto, anche quando il
--     modello aveva letto benissimo "LBF GROUP ITALIA S.r.l." — perche' il
--     nome letto finiva solo dentro il payload dell'estrazione e non veniva
--     salvato da nessuna parte di consultabile. Un dato che il sistema
--     conosce e non mostra e' peggio di un dato che non ha: sembra incapace.
--
--  2. Dall'elenco non si capiva cosa contenesse un documento ne' quanto
--     lavoro restasse da fare. Con sei documenti aperti e nomi simili,
--     l'unico modo per orientarsi era aprirli uno a uno.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- Il fornitore come l'ha letto il modello, anche quando in anagrafica non
-- c'e'. Resta scritto: serve a mostrarlo nell'elenco, e serve a
-- `crea_fornitore_da_documento` come valore di partenza.
alter table magazzino.documento_carico
  add column if not exists fornitore_letto text;

comment on column magazzino.documento_carico.fornitore_letto is
  'Denominazione letta sul documento, indipendente dall''anagrafica. Non e'' un doppione di fornitore_id: e'' cio'' che c''era scritto, e resta anche se poi il documento viene agganciato a un fornitore che si chiama in modo un po'' diverso.';


-- ----------------------------------------------------------------------------
--  documento_riepilogo
-- ----------------------------------------------------------------------------
--  Tutto quello che serve a una riga d'elenco, in una query sola. Senza,
--  l'app dovrebbe leggere le righe di ogni documento per contarle: sei
--  documenti, sette chiamate.
create or replace view magazzino.documento_riepilogo
with (security_invoker = true)
as
select
  d.id,
  d.organizzazione_id,
  d.fornitore_id,
  d.tipo,
  d.origine,
  d.numero_documento,
  d.data_documento,
  d.data_consegna,
  d.stato,
  d.totale_dichiarato,
  d.totale_documento,
  d.totale_calcolato,

  -- Il nome dell'anagrafica se c'e', altrimenti quello letto sul documento.
  coalesce(f.denominazione, d.fornitore_letto) as fornitore,
  -- Vero quando il nome mostrato viene dalla lettura e non dall'anagrafica:
  -- l'app lo segnala, cosi' si capisce che c'e' ancora un passo da fare.
  (d.fornitore_id is null)                     as fornitore_da_agganciare,

  (select count(*) from magazzino.documento_carico_riga r
    where r.documento_id = d.id and r.stato_match <> 'ignorata')      as righe,
  (select count(*) from magazzino.documento_carico_riga r
    where r.documento_id = d.id and r.stato_match = 'da_risolvere')   as da_risolvere,
  (select count(*) from magazzino.documento_carico_riga r
    where r.documento_id = d.id and r.stato_match = 'suggerito')      as da_confermare,

  -- Le prime tre descrizioni, troncate: e' cio' che permette di riconoscere
  -- un documento senza aprirlo. Solo la prima riga di ciascuna descrizione,
  -- perche' certi fornitori ci mettono dentro misure e riferimenti d'ordine.
  (select string_agg(a.testo, ' · ')
     from (select left(btrim(split_part(r.descrizione_originale, chr(10), 1)), 38) as testo
             from magazzino.documento_carico_riga r
            where r.documento_id = d.id and r.stato_match <> 'ignorata'
            order by r.numero_riga
            limit 3) a)                                               as anteprima

from magazzino.documento_carico d
left join magazzino.fornitore f on f.id = d.fornitore_id;

comment on view magazzino.documento_riepilogo is
  'Una riga per documento con fornitore, conteggi delle righe e anteprima del contenuto. Serve all''elenco: senza, l''app dovrebbe leggere le righe di ogni documento per sapere quanto lavoro resta.';
