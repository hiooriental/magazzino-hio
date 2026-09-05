-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 6: riconoscimento degli articoli
-- ============================================================================
--
--  Data una descrizione scritta dal fornitore, capire di che ingrediente si
--  tratta e quanta merce e' davvero entrata.
--
--  L'ordine in cui si prova conta piu' di qualunque modello:
--
--    1. codice fornitore identico   → certezza
--    2. EAN identico                → certezza
--    3. alias gia' confermato       → quasi certezza
--    4. somiglianza testuale        → punteggio
--    5. (solo se qui non esce niente) l'AI, che sta fuori da questo file
--
--  L'AI non e' il primo strumento, e' l'ultimo. Dopo qualche mese di fatture
--  i primi tre passaggi coprono quasi tutto e il modello non viene quasi mai
--  chiamato: e' il motivo per cui questo sistema diventa piu' economico man
--  mano che lo si usa, invece che piu' caro.
--
--  Tutto in SQL e non nell'edge function perche' cosi' si prova con una query,
--  come abbiamo fatto per la conferma.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  converti_um — le conversioni che si sanno senza aver imparato niente
-- ----------------------------------------------------------------------------
--  Se il fornitore scrive KG e l'ingrediente si misura in grammi, il fattore
--  e' 1000 e non serve nessun abbinamento. Vale solo per le unita' fisiche:
--  CT, CF, PZ e simili sono ambigui per definizione (un cartone di cosa?) e
--  richiedono il fattore imparato sull'articolo.
create or replace function magazzino.converti_um(p_um text, p_um_base text)
returns numeric
language sql
immutable
as $$
  select case lower(btrim(regexp_replace(coalesce(p_um, ''), '[^A-Za-z]', '', 'g')))
    when 'kg'  then case when p_um_base = 'g'  then 1000 end
    when 'kgm' then case when p_um_base = 'g'  then 1000 end
    when 'hg'  then case when p_um_base = 'g'  then 100  end
    when 'g'   then case when p_um_base = 'g'  then 1    end
    when 'gr'  then case when p_um_base = 'g'  then 1    end
    when 'grammi' then case when p_um_base = 'g' then 1  end
    when 'l'   then case when p_um_base = 'ml' then 1000 end
    when 'lt'  then case when p_um_base = 'ml' then 1000 end
    when 'ltr' then case when p_um_base = 'ml' then 1000 end
    when 'litri' then case when p_um_base = 'ml' then 1000 end
    when 'dl'  then case when p_um_base = 'ml' then 100  end
    when 'cl'  then case when p_um_base = 'ml' then 10   end
    when 'ml'  then case when p_um_base = 'ml' then 1    end
    when 'pz'  then case when p_um_base = 'pz' then 1    end
    when 'pzz' then case when p_um_base = 'pz' then 1    end
    when 'pezzi' then case when p_um_base = 'pz' then 1  end
    when 'nr'  then case when p_um_base = 'pz' then 1    end
    when 'n'   then case when p_um_base = 'pz' then 1    end
    when 'ن'   then null
    else null
  end::numeric;
$$;

comment on function magazzino.converti_um(text, text) is
  'Fattore di conversione fra unita'' fisiche note. Restituisce NULL quando l''unita'' e'' un imballo (CT, CF, COLLO): in quel caso serve il fattore imparato sull''articolo del fornitore.';


-- ----------------------------------------------------------------------------
--  Tipo di ritorno della ricerca
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'magazzino' and t.typname = 'candidato_articolo'
  ) then
    create type magazzino.candidato_articolo as (
      articolo_fornitore_id uuid,
      ingrediente_id        uuid,
      ingrediente           text,
      descrizione           text,
      fornitore             text,
      um_acquisto           text,
      fattore_conversione   numeric,
      metodo                text,
      punteggio             numeric
    );
  end if;
end;
$$;


-- ----------------------------------------------------------------------------
--  cerca_articolo — i candidati, col loro punteggio
-- ----------------------------------------------------------------------------
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
  -- Sotto i tre caratteri qualunque somiglianza e' rumore.
  if v_desc is null or length(v_desc) < 3 then
    if p_codice is null and p_ean is null then
      return;
    end if;
  end if;

  return query
  with candidati as (

    -- 1. Codice del fornitore: se coincide, non c'e' niente da interpretare.
    select a.id as aid, 'codice_fornitore'::text as met, 1.00::numeric as pt
    from magazzino.articolo_fornitore a
    where a.organizzazione_id = p_organizzazione_id
      and a.attivo
      and p_codice is not null
      and a.codice_fornitore = p_codice
      and (p_fornitore_id is null or a.fornitore_id = p_fornitore_id)

    union all

    -- 2. EAN: idem, ed e' l'unico identificativo davvero universale.
    select a.id, 'ean'::text, 1.00::numeric
    from magazzino.articolo_fornitore a
    where a.organizzazione_id = p_organizzazione_id
      and a.attivo
      and p_ean is not null
      and a.ean = p_ean

    union all

    -- 3. Alias gia' confermato da un operatore su un carico precedente.
    --    Non e' una stima: qualcuno ha gia' detto che questa scrittura
    --    significa quell'articolo.
    select al.articolo_fornitore_id, 'alias'::text, 0.98::numeric
    from magazzino.alias_articolo al
    where al.organizzazione_id = p_organizzazione_id
      and al.testo_normalizzato = v_desc

    union all

    -- 4. Somiglianza sulla descrizione dell'articolo.
    --    Penalizzata del 15% se l'articolo appartiene a un altro fornitore:
    --    puo' essere lo stesso prodotto, ma e' meno probabile.
    select a.id, 'similarita'::text,
           (similarity(a.descrizione_normalizzata, v_desc)
            * case when a.fornitore_id = p_fornitore_id then 1.0 else 0.85 end)::numeric
    from magazzino.articolo_fornitore a
    where a.organizzazione_id = p_organizzazione_id
      and a.attivo
      and v_desc is not null
      and a.descrizione_normalizzata % v_desc

    union all

    -- 5. Somiglianza sugli alias: intercetta le grafie viste in passato
    --    anche quando differiscono da quella "ufficiale" dell'articolo.
    select al.articolo_fornitore_id, 'similarita'::text,
           (similarity(al.testo_normalizzato, v_desc) * 0.95)::numeric
    from magazzino.alias_articolo al
    where al.organizzazione_id = p_organizzazione_id
      and v_desc is not null
      and al.testo_normalizzato % v_desc

  ),
  -- Lo stesso articolo puo' arrivare da piu' strade: tiene la migliore.
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

comment on function magazzino.cerca_articolo(uuid, uuid, text, text, text, integer) is
  'Candidati per una descrizione fornitore, ordinati per punteggio. La soglia della somiglianza testuale e'' pg_trgm.similarity_threshold (0.3 di default).';


-- ----------------------------------------------------------------------------
--  risolvi_riga — applica il candidato migliore a una riga di documento
-- ----------------------------------------------------------------------------
--  Le due soglie sono la parte piu' delicata di tutto il file:
--
--    >= 0.90  la riga si presenta gia' risolta, l'operatore non la guarda
--    >= 0.55  proposta, l'operatore conferma o corregge con un tocco
--    <  0.55  nessuna proposta: qui, e solo qui, ha senso chiamare l'AI
--
--  Alzarle significa piu' lavoro manuale; abbassarle significa carichi
--  sbagliati che nessuno ha guardato. 0,90 e' prudente di proposito: un
--  errore di riconoscimento non confermato da nessuno e' il tipo di guasto
--  che si scopre mesi dopo, quando l'inventario non torna.
create or replace function magazzino.risolvi_riga(p_riga_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  SOGLIA_AUTO         constant numeric := 0.90;
  SOGLIA_PROPOSTA     constant numeric := 0.55;

  v_riga    magazzino.documento_carico_riga%rowtype;
  v_doc     magazzino.documento_carico%rowtype;
  v_cand    magazzino.candidato_articolo;
  v_ing     magazzino.ingrediente%rowtype;
  v_fattore numeric;
  v_qta     numeric(14,3);
  v_costo   numeric(14,6);
  v_stato   text;
begin
  select * into v_riga from magazzino.documento_carico_riga where id = p_riga_id;
  if not found then
    raise exception 'Riga % inesistente o non visibile.', p_riga_id;
  end if;

  -- Una riga gia' confermata a mano non si tocca: la decisione umana vince
  -- sempre su quella automatica.
  if v_riga.stato_match = 'confermato' and v_riga.metodo_match = 'manuale' then
    return jsonb_build_object('riga_id', p_riga_id, 'esito', 'gia_confermata_a_mano');
  end if;

  select * into v_doc from magazzino.documento_carico where id = v_riga.documento_id;

  select * into v_cand
  from magazzino.cerca_articolo(
    v_doc.organizzazione_id, v_doc.fornitore_id,
    v_riga.descrizione_originale, v_riga.codice_fornitore_originale, null, 1
  );

  if v_cand.articolo_fornitore_id is null or v_cand.punteggio < SOGLIA_PROPOSTA then
    update magazzino.documento_carico_riga
    set stato_match = 'da_risolvere',
        confidenza  = coalesce(v_cand.punteggio, 0),
        metodo_match = null
    where id = p_riga_id;

    return jsonb_build_object(
      'riga_id', p_riga_id,
      'esito',   'nessun_candidato',
      'migliore_punteggio', coalesce(v_cand.punteggio, 0)
    );
  end if;

  v_stato := case when v_cand.punteggio >= SOGLIA_AUTO then 'confermato' else 'suggerito' end;

  -- ── Quanta merce e' entrata ─────────────────────────────────────────────
  if v_cand.ingrediente_id is not null then
    select * into v_ing from magazzino.ingrediente where id = v_cand.ingrediente_id;

    -- Prima l'unita' fisica dichiarata sul documento: se il fornitore scrive
    -- KG, quel dato e' piu' affidabile di qualunque fattore memorizzato,
    -- perche' non dipende da come era confezionata la merce quella volta.
    v_fattore := magazzino.converti_um(v_riga.um_dichiarata, v_ing.um_base);

    -- Altrimenti il fattore imparato sull'articolo (il cartone, il collo).
    if v_fattore is null then
      v_fattore := v_cand.fattore_conversione;
    end if;

    if v_fattore is not null and v_riga.quantita_dichiarata is not null then
      v_qta := v_riga.quantita_dichiarata * v_fattore;
    end if;

    -- Il costo si ricava dal totale di riga, che e' il numero che quadra col
    -- totale del documento. Il prezzo unitario e' un ripiego.
    if v_qta is not null and v_qta <> 0 then
      v_costo := case
        when v_riga.totale_riga is not null then abs(v_riga.totale_riga) / abs(v_qta)
        when v_riga.prezzo_unitario is not null and v_fattore <> 0
             then v_riga.prezzo_unitario / v_fattore
      end;
    end if;
  end if;

  update magazzino.documento_carico_riga
  set articolo_fornitore_id         = v_cand.articolo_fornitore_id,
      ingrediente_id                = v_cand.ingrediente_id,
      fattore_conversione_applicato = v_fattore,
      quantita_base                 = v_qta,
      costo_unitario_base           = v_costo,
      confidenza                    = v_cand.punteggio,
      metodo_match                  = v_cand.metodo,
      -- Senza ingrediente o senza quantita' la riga resta da lavorare, per
      -- quanto alto sia il punteggio: sapere COSA e' non basta se non si sa
      -- QUANTO e'.
      stato_match                   = case
                                        when v_cand.ingrediente_id is null then 'da_risolvere'
                                        when v_qta is null then 'da_risolvere'
                                        else v_stato
                                      end
  where id = p_riga_id;

  return jsonb_build_object(
    'riga_id',      p_riga_id,
    'esito',        'risolta',
    'articolo',     v_cand.descrizione,
    'ingrediente',  v_cand.ingrediente,
    'metodo',       v_cand.metodo,
    'punteggio',    v_cand.punteggio,
    'quantita_base', v_qta,
    'costo_um_base', v_costo,
    'stato',        case when v_cand.ingrediente_id is null or v_qta is null
                         then 'da_risolvere' else v_stato end
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  risolvi_documento — passa tutte le righe
-- ----------------------------------------------------------------------------
--  E' quello che si chiama subito dopo l'estrazione dalla foto: la maggior
--  parte delle righe si sistema da sola, e all'operatore resta l'elenco corto
--  di quelle davvero dubbie.
create or replace function magazzino.risolvi_documento(p_documento_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  v_riga        record;
  v_esito       jsonb;
  v_automatiche integer := 0;
  v_proposte    integer := 0;
  v_da_fare     integer := 0;
  v_totale      integer := 0;
begin
  for v_riga in
    select id from magazzino.documento_carico_riga
    where documento_id = p_documento_id
      and stato_match <> 'ignorata'
    order by numero_riga
  loop
    v_esito  := magazzino.risolvi_riga(v_riga.id);
    v_totale := v_totale + 1;

    case v_esito ->> 'stato'
      when 'confermato' then v_automatiche := v_automatiche + 1;
      when 'suggerito'  then v_proposte    := v_proposte + 1;
      else                   v_da_fare     := v_da_fare + 1;
    end case;
  end loop;

  return jsonb_build_object(
    'documento_id',  p_documento_id,
    'righe',         v_totale,
    'automatiche',   v_automatiche,
    'da_confermare', v_proposte,
    'da_risolvere',  v_da_fare,
    -- Quante righe sono passate senza far perdere tempo a nessuno. E' il
    -- numero che deve salire mese dopo mese: se non sale, il sistema non sta
    -- imparando e c'e' qualcosa da correggere.
    'copertura',     case when v_totale > 0
                          then round(100.0 * v_automatiche / v_totale, 1) end
  );
end;
$$;


grant execute on function magazzino.converti_um(text, text) to authenticated;
grant execute on function magazzino.cerca_articolo(uuid, uuid, text, text, text, integer) to authenticated;
grant execute on function magazzino.risolvi_riga(uuid) to authenticated;
grant execute on function magazzino.risolvi_documento(uuid) to authenticated;
