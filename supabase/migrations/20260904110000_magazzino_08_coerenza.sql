-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 8: il conto deve tornare
-- ============================================================================
--
--  Nato da un caso reale, al primo collaudo su un DDT vero.
--
--  Il documento diceva: 720.000,00 PZ a 0,007 = 5.040,00.
--  Il modello ha letto: 720 PZ a 0,007 = 5.040,00.
--
--  L'articolo era riconosciuto benissimo, il prezzo era giusto, il totale era
--  giusto. Solo la quantita' era mille volte piu' piccola, e niente nel
--  sistema se ne accorgeva: sarebbe entrato in magazzino un millesimo della
--  merce, e la differenza sarebbe saltata fuori all'inventario, mesi dopo,
--  senza piu' modo di capire da dove venisse.
--
--  Il rimedio non e' un prompt migliore — quello aiuta ma sbagliera' ancora.
--  Il rimedio e' che il documento verifichi se stesso: quantita' per prezzo
--  deve dare il totale di riga. Sono tre numeri letti indipendentemente
--  dalla stessa immagine, e la probabilita' che sbaglino tutti e tre in modo
--  coerente e' bassissima.
--
--  Vale anche per l'inserimento a mano, dove le dita sbagliano quanto l'AI.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  numero_it — un numero come lo legge chi sta guardando il documento
-- ----------------------------------------------------------------------------
--  I messaggi di errore servono a essere confrontati con la carta che
--  l'operatore ha in mano. Scrivere "5040." mentre sul DDT c'e' "5.040,00"
--  costringe a una traduzione mentale proprio nel momento in cui si sta
--  cercando un errore.
--
--  to_char scrive all'inglese (virgola per le migliaia, punto per i decimali);
--  qui i due separatori vengono scambiati passando per un carattere neutro.
create or replace function magazzino.numero_it(p_numero numeric)
returns text
language sql
immutable
as $$
  select case when p_numero is null then null else
    replace(replace(replace(
      rtrim(to_char(p_numero, 'FM999,999,999,990.9999'), '.'),
      '.', '#'), ',', '.'), '#', ',')
  end;
$$;


-- ----------------------------------------------------------------------------
--  verifica_coerenza_riga
-- ----------------------------------------------------------------------------
--  NULL se i conti tornano (o se mancano i dati per verificarlo).
--  Altrimenti il messaggio da mostrare all'operatore, con la quantita' che
--  renderebbe coerente la riga: quasi sempre e' quella giusta, ed e' molto
--  piu' utile di un generico "controlla".
create or replace function magazzino.verifica_coerenza_riga(
  p_quantita   numeric,
  p_prezzo     numeric,
  p_sconto     numeric,
  p_totale     numeric
)
returns text
language sql
immutable
as $$
  with c as (
    select
      p_quantita * p_prezzo * (1 - coalesce(p_sconto, 0) / 100.0) as atteso,
      -- Due centesimi di tolleranza assoluta per gli arrotondamenti, oppure
      -- l'1% per le righe grosse, dove gli scarti di arrotondamento crescono.
      greatest(0.02, abs(p_totale) * 0.01) as tolleranza
  )
  select case
    when p_quantita is null or p_prezzo is null or p_totale is null then null
    when p_prezzo = 0 or p_quantita = 0 then null
    -- Sconto totale: il prezzo netto e' zero e la quantita' non e' ricavabile.
    when coalesce(p_sconto, 0) >= 100 then null
    when abs(c.atteso - p_totale) <= c.tolleranza then null
    else
      'Il conto non torna: ' || magazzino.numero_it(p_quantita) ||
      ' × ' || magazzino.numero_it(p_prezzo) ||
      case when coalesce(p_sconto, 0) <> 0
           then ' meno ' || magazzino.numero_it(p_sconto) || '%' else '' end ||
      ' fa ' || magazzino.numero_it(round(c.atteso, 2)) ||
      ', ma il totale di riga è ' || magazzino.numero_it(p_totale) ||
      '. Con questo prezzo la quantità dovrebbe essere ' ||
      magazzino.numero_it(round(p_totale / (p_prezzo * (1 - coalesce(p_sconto, 0) / 100.0)), 3)) ||
      '.'
  end
  from c;
$$;

comment on function magazzino.verifica_coerenza_riga(numeric, numeric, numeric, numeric) is
  'Controlla che quantita'' per prezzo dia il totale di riga. Nato da un DDT dove 720.000,00 era stato letto 720: articolo giusto, prezzo giusto, e solo la quantita'' mille volte piu'' piccola.';


-- ----------------------------------------------------------------------------
--  risolvi_riga, con il controllo dentro
-- ----------------------------------------------------------------------------
--  Unica differenza rispetto alla versione precedente: qualunque sia il
--  punteggio dell'abbinamento, se i conti non tornano la riga NON passa in
--  automatico. Riconoscere l'articolo e leggere le cifre sono due cose
--  diverse, e la prima non garantisce la seconda.
create or replace function magazzino.risolvi_riga(p_riga_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  SOGLIA_AUTO     constant numeric := 0.90;
  SOGLIA_PROPOSTA constant numeric := 0.55;

  v_riga     magazzino.documento_carico_riga%rowtype;
  v_doc      magazzino.documento_carico%rowtype;
  v_cand     magazzino.candidato_articolo;
  v_ing      magazzino.ingrediente%rowtype;
  v_fattore  numeric;
  v_qta      numeric(14,3);
  v_costo    numeric(14,6);
  v_stato    text;
  v_incoerenza text;
begin
  select * into v_riga from magazzino.documento_carico_riga where id = p_riga_id;
  if not found then
    raise exception 'Riga % inesistente o non visibile.', p_riga_id;
  end if;

  if v_riga.stato_match = 'confermato' and v_riga.metodo_match = 'manuale' then
    return jsonb_build_object('riga_id', p_riga_id, 'esito', 'gia_confermata_a_mano');
  end if;

  -- Il controllo aritmetico si fa PRIMA di cercare l'articolo: non dipende da
  -- cosa sia il prodotto, solo da come sono state lette le cifre.
  v_incoerenza := magazzino.verifica_coerenza_riga(
    v_riga.quantita_dichiarata, v_riga.prezzo_unitario,
    v_riga.sconto_percentuale, v_riga.totale_riga
  );

  select * into v_doc from magazzino.documento_carico where id = v_riga.documento_id;

  select * into v_cand
  from magazzino.cerca_articolo(
    v_doc.organizzazione_id, v_doc.fornitore_id,
    v_riga.descrizione_originale, v_riga.codice_fornitore_originale, null, 1
  );

  if v_cand.articolo_fornitore_id is null or v_cand.punteggio < SOGLIA_PROPOSTA then
    update magazzino.documento_carico_riga
    set stato_match  = 'da_risolvere',
        confidenza   = coalesce(v_cand.punteggio, 0),
        metodo_match = null,
        note         = v_incoerenza
    where id = p_riga_id;

    return jsonb_build_object(
      'riga_id', p_riga_id,
      'esito',   'nessun_candidato',
      'migliore_punteggio', coalesce(v_cand.punteggio, 0),
      'incoerenza', v_incoerenza
    );
  end if;

  v_stato := case when v_cand.punteggio >= SOGLIA_AUTO then 'confermato' else 'suggerito' end;

  if v_cand.ingrediente_id is not null then
    select * into v_ing from magazzino.ingrediente where id = v_cand.ingrediente_id;

    v_fattore := magazzino.converti_um(v_riga.um_dichiarata, v_ing.um_base);
    if v_fattore is null then
      v_fattore := v_cand.fattore_conversione;
    end if;

    if v_fattore is not null and v_riga.quantita_dichiarata is not null then
      v_qta := v_riga.quantita_dichiarata * v_fattore;
    end if;

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
      note                          = v_incoerenza,
      stato_match                   = case
                                        -- I conti che non tornano fermano la
                                        -- riga anche con abbinamento perfetto.
                                        when v_incoerenza is not null then 'da_risolvere'
                                        when v_cand.ingrediente_id is null then 'da_risolvere'
                                        when v_qta is null then 'da_risolvere'
                                        else v_stato
                                      end
  where id = p_riga_id;

  return jsonb_build_object(
    'riga_id',       p_riga_id,
    'esito',         'risolta',
    'articolo',      v_cand.descrizione,
    'ingrediente',   v_cand.ingrediente,
    'metodo',        v_cand.metodo,
    'punteggio',     v_cand.punteggio,
    'quantita_base', v_qta,
    'costo_um_base', v_costo,
    'incoerenza',    v_incoerenza,
    'stato',         case
                       when v_incoerenza is not null then 'da_risolvere'
                       when v_cand.ingrediente_id is null or v_qta is null then 'da_risolvere'
                       else v_stato
                     end
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  E la conferma non passa se una riga non quadra
-- ----------------------------------------------------------------------------
--  Il controllo in `risolvi_riga` marca la riga, ma qualcuno potrebbe forzare
--  lo stato a mano. Questo e' l'ultimo cancello prima che la merce entri.
create or replace function magazzino.righe_incoerenti(p_documento_id uuid)
returns table (numero_riga smallint, descrizione text, problema text)
language sql
stable
security invoker
set search_path = magazzino, public
as $$
  select r.numero_riga, r.descrizione_originale,
         magazzino.verifica_coerenza_riga(
           r.quantita_dichiarata, r.prezzo_unitario,
           r.sconto_percentuale, r.totale_riga)
  from magazzino.documento_carico_riga r
  where r.documento_id = p_documento_id
    and r.stato_match <> 'ignorata'
    and magazzino.verifica_coerenza_riga(
          r.quantita_dichiarata, r.prezzo_unitario,
          r.sconto_percentuale, r.totale_riga) is not null
  order by r.numero_riga;
$$;


grant execute on function magazzino.numero_it(numeric) to authenticated;
grant execute on function magazzino.verifica_coerenza_riga(numeric, numeric, numeric, numeric) to authenticated;
grant execute on function magazzino.righe_incoerenti(uuid) to authenticated;
