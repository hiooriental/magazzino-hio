-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 12: chiamare le cose col loro nome
-- ============================================================================
--
--  Dal collaudo del ciclo di apprendimento: una riga con descrizione IDENTICA
--  a quella dell'articolo risultava abbinata con metodo "similarita" e
--  punteggio 1,000. Il risultato era giusto, il nome no.
--
--  Non e' pignoleria. Il metodo e' cio' che l'operatore legge per capire
--  perche' una riga e' passata senza chiedergli niente, e "somiglianza 100%"
--  e "descrizione identica" non ispirano la stessa fiducia — ne' meritano la
--  stessa attenzione quando qualcosa va storto.
--
--  Ordine delle strade, dalla piu' certa alla piu' incerta:
--
--    codice_fornitore  1.00   il fornitore lo identifica cosi'
--    ean               1.00   identificativo universale
--    descrizione       0.99   stringa identica a quella dell'articolo
--    alias             0.98   grafia gia' confermata da una persona
--    similarita        < 1    stima, e come tale non arriva mai
--                             all'automatico da sola
-- ============================================================================

set search_path = magazzino, extensions, public;


-- Il vincolo elenca i metodi ammessi: senza aggiornarlo, la prima riga
-- abbinata per descrizione esatta viene rifiutata dal database.
alter table magazzino.documento_carico_riga
  drop constraint if exists documento_carico_riga_metodo_match_check;

alter table magazzino.documento_carico_riga
  add constraint documento_carico_riga_metodo_match_check
  check (metodo_match in (
    'codice_fornitore', 'ean', 'descrizione', 'alias', 'similarita', 'ai', 'manuale'
  ));


create or replace function magazzino.cerca_articolo(
  p_organizzazione_id uuid,
  p_fornitore_id      uuid,
  p_descrizione       text,
  p_codice            text default null,
  p_ean               text default null,
  p_limite            integer default 5
)
returns setof magazzino.candidato_articolo
language plpgsql
stable
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  v_desc text := magazzino.normalizza(p_descrizione);
begin
  if v_desc is null or length(v_desc) < 3 then
    if p_codice is null and p_ean is null then
      return;
    end if;
  end if;

  return query
  with candidati as (

    -- 1. Codice del fornitore.
    select a.id as aid, 'codice_fornitore'::text as met, 1.00::numeric as pt
    from magazzino.articolo_fornitore a
    where a.organizzazione_id = p_organizzazione_id
      and a.attivo
      and p_codice is not null
      and a.codice_fornitore = p_codice
      and (p_fornitore_id is null or a.fornitore_id = p_fornitore_id)

    union all

    -- 2. EAN.
    select a.id, 'ean'::text, 1.00::numeric
    from magazzino.articolo_fornitore a
    where a.organizzazione_id = p_organizzazione_id
      and a.attivo
      and p_ean is not null
      and a.ean = p_ean

    union all

    -- 3. Descrizione identica a quella dell'articolo. Non e' una stima:
    --    e' la stessa identica stringa, a meno di accenti e spaziatura.
    select a.id, 'descrizione'::text, 0.99::numeric
    from magazzino.articolo_fornitore a
    where a.organizzazione_id = p_organizzazione_id
      and a.attivo
      and v_desc is not null
      and a.descrizione_normalizzata = v_desc

    union all

    -- 4. Alias: grafia diversa, ma gia' confermata da una persona.
    select al.articolo_fornitore_id, 'alias'::text, 0.98::numeric
    from magazzino.alias_articolo al
    where al.organizzazione_id = p_organizzazione_id
      and al.testo_normalizzato = v_desc

    union all

    -- 5. Somiglianza. Le corrispondenze esatte sono escluse qui sopra:
    --    se restassero, la somiglianza varrebbe 1,000 e scavalcherebbe le
    --    strade certe, che e' proprio l'equivoco da cui nasce questo file.
    select a.id, 'similarita'::text,
           (similarity(a.descrizione_normalizzata, v_desc)
            * case when a.fornitore_id = p_fornitore_id then 1.0 else 0.85 end)::numeric
    from magazzino.articolo_fornitore a
    where a.organizzazione_id = p_organizzazione_id
      and a.attivo
      and v_desc is not null
      and a.descrizione_normalizzata <> v_desc
      and a.descrizione_normalizzata % v_desc

    union all

    select al.articolo_fornitore_id, 'similarita'::text,
           (similarity(al.testo_normalizzato, v_desc) * 0.95)::numeric
    from magazzino.alias_articolo al
    where al.organizzazione_id = p_organizzazione_id
      and v_desc is not null
      and al.testo_normalizzato <> v_desc
      and al.testo_normalizzato % v_desc

  ),
  migliori as (
    select distinct on (c.aid) c.aid, c.met, c.pt
    from candidati c
    order by c.aid, c.pt desc
  )
  select
    a.id,
    a.ingrediente_id,
    i.nome,
    a.descrizione_originale,
    f.denominazione,
    a.um_acquisto,
    a.fattore_conversione,
    m.met,
    round(m.pt, 3)
  from migliori m
  join magazzino.articolo_fornitore a on a.id = m.aid
  left join magazzino.ingrediente i on i.id = a.ingrediente_id
  left join magazzino.fornitore f on f.id = a.fornitore_id
  order by m.pt desc, a.ultimo_acquisto_il desc nulls last
  limit p_limite;
end;
$$;
