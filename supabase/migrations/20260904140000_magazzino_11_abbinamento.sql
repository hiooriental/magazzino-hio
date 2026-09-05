-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 11: l'abbinamento manuale
-- ============================================================================
--
--  Il momento in cui il sistema impara.
--
--  Una riga resta `da_risolvere` perche' quel prodotto non l'ha mai visto
--  nessuno. L'operatore dice una volta sola "questo e' Mazzancolle giganti, e
--  un cartone fa 5 kg". Da quel gesto nascono tre cose:
--
--    - l'articolo del fornitore, con il suo fattore di conversione
--    - l'alias, cioe' la grafia esatta incontrata su quel documento
--    - il ricalcolo di tutte le altre righe dello stesso documento
--
--  Dalla volta dopo quella riga passa da sola, per sempre. E' il meccanismo
--  per cui la copertura sale da zero al novanta per cento nel giro di qualche
--  mese, e per cui l'AI viene chiamata sempre meno invece che sempre di piu'.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  crea_fornitore_da_documento
-- ----------------------------------------------------------------------------
--  L'estrazione non crea fornitori da sola, di proposito: riempirebbe
--  l'anagrafica di doppioni scritti in modo appena diverso. Li crea questa,
--  quando una persona conferma.
--
--  Se esiste gia' un fornitore con quella partita IVA lo aggancia invece di
--  duplicarlo, anche se la denominazione letta e' scritta diversamente.
create or replace function magazzino.crea_fornitore_da_documento(
  p_documento_id  uuid,
  p_denominazione text default null,
  p_partita_iva   text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_doc     magazzino.documento_carico%rowtype;
  v_nome    text;
  v_piva    text;
  v_id      uuid;
  v_creato  boolean := false;
begin
  select * into v_doc from magazzino.documento_carico where id = p_documento_id;
  if not found then
    raise exception 'Documento % inesistente o non visibile.', p_documento_id;
  end if;

  if v_doc.fornitore_id is not null then
    return jsonb_build_object(
      'fornitore_id', v_doc.fornitore_id, 'creato', false,
      'nota', 'Il documento aveva gia'' un fornitore.');
  end if;

  -- Se non arrivano dall'operatore, si prendono da cio' che ha letto il
  -- modello nell'ultima estrazione riuscita.
  v_nome := p_denominazione;
  v_piva := p_partita_iva;

  if v_nome is null or v_piva is null then
    select coalesce(v_nome, payload -> 'fornitore' ->> 'denominazione'),
           coalesce(v_piva, payload -> 'fornitore' ->> 'partita_iva')
      into v_nome, v_piva
    from magazzino.estrazione_ai
    where documento_id = p_documento_id and stato = 'completata'
    order by creato_il desc
    limit 1;
  end if;

  if v_nome is null or btrim(v_nome) = '' then
    raise exception 'Manca la denominazione del fornitore: indicarla a mano.';
  end if;

  -- "IT01346641218" e "01346641218" sono lo stesso fornitore.
  v_piva := nullif(regexp_replace(coalesce(v_piva, ''), '\D', '', 'g'), '');

  if v_piva is not null then
    select id into v_id
    from magazzino.fornitore
    where organizzazione_id = v_doc.organizzazione_id and partita_iva = v_piva;
  end if;

  if v_id is null then
    insert into magazzino.fornitore (organizzazione_id, denominazione, partita_iva)
    values (v_doc.organizzazione_id, btrim(v_nome), v_piva)
    returning id into v_id;
    v_creato := true;
  end if;

  update magazzino.documento_carico set fornitore_id = v_id where id = p_documento_id;

  return jsonb_build_object(
    'fornitore_id', v_id,
    'denominazione', btrim(v_nome),
    'partita_iva', v_piva,
    'creato', v_creato);
end;
$$;


-- ----------------------------------------------------------------------------
--  abbina_riga
-- ----------------------------------------------------------------------------
--  Il fattore di conversione dice quante unita' base stanno in UNA unita'
--  d'acquisto: cartone da 5 kg di un ingrediente misurato in grammi → 5000.
--
--  Puo' restare nullo quando l'unita' del documento e' gia' fisica (KG, LT):
--  in quel caso `converti_um` sa gia' rispondere e non c'e' niente da
--  imparare. Se pero' l'unita' e' un imballo (CT, CF, COLLO) e il fattore non
--  viene indicato, la funzione si ferma: caricare "3" senza sapere 3 di cosa
--  e' il modo piu' rapido per avere una giacenza priva di significato.
create or replace function magazzino.abbina_riga(
  p_riga_id             uuid,
  p_ingrediente_id      uuid,
  p_fattore_conversione numeric default null,
  p_um_acquisto         text    default null,
  p_codice_fornitore    text    default null
)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  v_riga      magazzino.documento_carico_riga%rowtype;
  v_doc       magazzino.documento_carico%rowtype;
  v_ing       magazzino.ingrediente%rowtype;
  v_articolo  uuid;
  v_creato    boolean := false;
  v_codice    text;
  v_um        text;
  v_fattore   numeric;
  v_esito     jsonb;
begin
  select * into v_riga from magazzino.documento_carico_riga where id = p_riga_id;
  if not found then
    raise exception 'Riga % inesistente o non visibile.', p_riga_id;
  end if;

  select * into v_doc from magazzino.documento_carico where id = v_riga.documento_id;

  if v_doc.stato = 'confermato' then
    raise exception 'Il documento e'' gia'' confermato: non si riabbinano le righe.';
  end if;

  if v_doc.fornitore_id is null then
    raise exception 'Il documento non ha ancora un fornitore. Usare prima crea_fornitore_da_documento().';
  end if;

  select * into v_ing
  from magazzino.ingrediente
  where id = p_ingrediente_id and organizzazione_id = v_doc.organizzazione_id;

  if not found then
    raise exception 'Ingrediente % inesistente o di un''altra organizzazione.', p_ingrediente_id;
  end if;

  v_codice  := coalesce(p_codice_fornitore, v_riga.codice_fornitore_originale);
  v_um      := coalesce(p_um_acquisto, v_riga.um_dichiarata);
  v_fattore := p_fattore_conversione;

  -- Serve un fattore solo se l'unita' non si sa convertire da sola.
  if v_fattore is null and magazzino.converti_um(v_um, v_ing.um_base) is null then
    raise exception
      'Serve il fattore di conversione: quante % stanno in una unita'' d''acquisto "%"?',
      v_ing.um_base, coalesce(v_um, '(non indicata)');
  end if;

  -- ── L'articolo del fornitore ────────────────────────────────────────────
  -- Prima per codice, poi per descrizione identica: due strade per non creare
  -- un doppione di qualcosa che c'e' gia'.
  if v_codice is not null then
    select id into v_articolo
    from magazzino.articolo_fornitore
    where organizzazione_id = v_doc.organizzazione_id
      and fornitore_id = v_doc.fornitore_id
      and codice_fornitore = v_codice;
  end if;

  if v_articolo is null then
    select id into v_articolo
    from magazzino.articolo_fornitore
    where organizzazione_id = v_doc.organizzazione_id
      and fornitore_id = v_doc.fornitore_id
      and descrizione_normalizzata = magazzino.normalizza(v_riga.descrizione_originale)
    limit 1;
  end if;

  if v_articolo is null then
    insert into magazzino.articolo_fornitore (
      organizzazione_id, fornitore_id, ingrediente_id,
      codice_fornitore, descrizione_originale, um_acquisto, fattore_conversione
    )
    values (
      v_doc.organizzazione_id, v_doc.fornitore_id, p_ingrediente_id,
      v_codice, v_riga.descrizione_originale, v_um, v_fattore
    )
    returning id into v_articolo;
    v_creato := true;
  else
    update magazzino.articolo_fornitore
    set ingrediente_id      = p_ingrediente_id,
        codice_fornitore    = coalesce(codice_fornitore, v_codice),
        um_acquisto         = coalesce(v_um, um_acquisto),
        fattore_conversione = coalesce(v_fattore, fattore_conversione),
        attivo              = true
    where id = v_articolo;
  end if;

  -- ── L'alias ─────────────────────────────────────────────────────────────
  -- La grafia esatta di questo documento. E' cio' che rendera' automatica la
  -- prossima lettura, senza somiglianze da valutare.
  insert into magazzino.alias_articolo (
    organizzazione_id, articolo_fornitore_id,
    testo_originale, testo_normalizzato, origine
  )
  values (
    v_doc.organizzazione_id, v_articolo,
    v_riga.descrizione_originale,
    coalesce(magazzino.normalizza(v_riga.descrizione_originale), ''),
    v_doc.origine
  )
  on conflict (organizzazione_id, articolo_fornitore_id, testo_normalizzato)
  do update set conteggio_usi = magazzino.alias_articolo.conteggio_usi + 1,
                ultimo_uso_il = now();

  -- ── Ricalcolo ───────────────────────────────────────────────────────────
  -- Prima questa riga, poi tutto il documento: capita spesso che lo stesso
  -- prodotto compaia su piu' righe, e non ha senso farlo abbinare due volte.
  v_esito := magazzino.risolvi_riga(p_riga_id);

  -- La decisione e' di una persona: si annota, cosi' un ricalcolo successivo
  -- non la sovrascrive. Lo STATO invece resta quello calcolato: se i conti
  -- della riga non tornano, la riga resta ferma anche se l'articolo e' certo.
  update magazzino.documento_carico_riga
  set metodo_match = 'manuale', confidenza = 1
  where id = p_riga_id;

  return jsonb_build_object(
    'riga_id',            p_riga_id,
    'articolo_id',        v_articolo,
    'articolo_creato',    v_creato,
    'ingrediente',        v_ing.nome,
    'fattore_conversione', coalesce(v_fattore,
                                    magazzino.converti_um(v_um, v_ing.um_base)),
    'stato',              v_esito ->> 'stato',
    'incoerenza',         v_esito ->> 'incoerenza',
    'documento',          magazzino.risolvi_documento(v_riga.documento_id)
  );
end;
$$;


-- ----------------------------------------------------------------------------
--  crea_ingrediente_da_riga
-- ----------------------------------------------------------------------------
--  Il caso piu' frequente all'inizio: il prodotto non esiste proprio in
--  anagrafica. Crea l'ingrediente e lo abbina in un colpo solo, cosi'
--  dall'interfaccia e' un modulo unico invece di due passaggi.
create or replace function magazzino.crea_ingrediente_da_riga(
  p_riga_id             uuid,
  p_nome                text,
  p_um_base             text,
  p_fattore_conversione numeric default null,
  p_categoria_id        uuid    default null,
  p_conservazione       text    default 'ambiente',
  p_gestisci_lotti      boolean default false,
  p_richiede_abbattimento boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, extensions, public
as $$
declare
  v_riga  magazzino.documento_carico_riga%rowtype;
  v_doc   magazzino.documento_carico%rowtype;
  v_ing   uuid;
begin
  select * into v_riga from magazzino.documento_carico_riga where id = p_riga_id;
  if not found then
    raise exception 'Riga % inesistente o non visibile.', p_riga_id;
  end if;

  select * into v_doc from magazzino.documento_carico where id = v_riga.documento_id;

  -- Un ingrediente con lo stesso nome esiste gia': si riusa invece di creare
  -- "Mazzancolle giganti" e "MAZZANCOLLE GIGANTI" come due cose diverse.
  select id into v_ing
  from magazzino.ingrediente
  where organizzazione_id = v_doc.organizzazione_id
    and nome_normalizzato = magazzino.normalizza(p_nome);

  if v_ing is null then
    insert into magazzino.ingrediente (
      organizzazione_id, nome, um_base, categoria_id,
      conservazione, gestisci_lotti, richiede_abbattimento
    )
    values (
      v_doc.organizzazione_id, btrim(p_nome), p_um_base, p_categoria_id,
      p_conservazione, p_gestisci_lotti, p_richiede_abbattimento
    )
    returning id into v_ing;
  end if;

  return magazzino.abbina_riga(p_riga_id, v_ing, p_fattore_conversione);
end;
$$;


grant execute on function magazzino.crea_fornitore_da_documento(uuid, text, text) to authenticated;
grant execute on function magazzino.abbina_riga(uuid, uuid, numeric, text, text) to authenticated;
grant execute on function magazzino.crea_ingrediente_da_riga(uuid, text, text, numeric, uuid, text, boolean, boolean) to authenticated;
