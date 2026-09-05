-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 5: conferma e storno di un carico
-- ============================================================================
--
--  E' l'unico punto del sistema in cui il magazzino si muove per acquisto.
--  Sta nel database e non nell'app per un motivo solo: deve essere tutto o
--  niente. Se la connessione cade a meta', non deve restare mezzo carico
--  registrato — sarebbe la situazione peggiore, perche' i numeri sembrerebbero
--  buoni e non lo sarebbero.
--
--  `conferma_carico` fa cinque cose in una transazione:
--    1. valida che ogni riga sia risolta
--    2. crea i lotti dove servono
--    3. scrive i movimenti nel libro mastro
--    4. registra i prezzi e aggiorna il costo medio
--    5. impara gli alias per la prossima volta
--
--  `storna_carico` la annulla: non cancella niente, scrive i movimenti
--  contrari. Il libro mastro resta a sola aggiunta.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  Cosa manca ancora allo schema
-- ----------------------------------------------------------------------------

-- Non tutti gli ingredienti meritano un lotto. Il tonno si', i tovaglioli no:
-- generare un lotto per ogni confezione di tovaglioli riempirebbe la tabella
-- di righe che nessuno guardera' mai. Flag esplicito invece che regola
-- indovinata dal sistema.
alter table magazzino.ingrediente
  add column if not exists gestisci_lotti boolean not null default false;

comment on column magazzino.ingrediente.gestisci_lotti is
  'Se vero, ogni carico genera un lotto. La funzione di conferma lo fa comunque quando l''ingrediente richiede abbattimento o quando la riga porta scadenza o lotto del fornitore: il flag e'' un "sempre", non un "solo se".';

-- Chiarimento necessario: sta in unita' base (g/ml/pz), perche' e' una pesata,
-- non una quantita' letta dal documento.
comment on column magazzino.documento_carico_riga.quantita_reale is
  'Peso pesato in accettazione, in unita'' base (g/ml/pz). Se presente prevale su quantita_base nella generazione dei movimenti. La differenza fra le due, accumulata per fornitore, e'' uno dei dati piu'' preziosi del sistema.';

-- Numerazione progressiva dei lotti, condivisa da tutte le organizzazioni:
-- garantisce l'unicita' senza dover bloccare niente.
create sequence if not exists magazzino.lotto_progressivo;


-- ----------------------------------------------------------------------------
--  conferma_carico
-- ----------------------------------------------------------------------------
create or replace function magazzino.conferma_carico(p_documento_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_doc           magazzino.documento_carico%rowtype;
  v_ing           magazzino.ingrediente%rowtype;
  v_riga          record;
  v_deposito      uuid;
  v_causale       text;
  v_verso         smallint;
  v_qta           numeric(14,3);
  v_costo         numeric(14,6);
  v_lotto         uuid;
  v_giacenza      numeric(14,3);
  v_nuovo_costo   numeric(14,6);
  v_problemi      text;
  v_n_righe       integer := 0;
  v_n_lotti       integer := 0;
  v_totale        numeric(14,2) := 0;
  v_valore        numeric(20,6) := 0;
begin
  -- ── 1. Il documento ─────────────────────────────────────────────────────
  -- FOR UPDATE: due persone che premono "conferma" nello stesso momento
  -- caricherebbero la merce due volte. La seconda aspetta e trova lo stato
  -- gia' cambiato.
  select * into v_doc
  from magazzino.documento_carico
  where id = p_documento_id
  for update;

  if not found then
    raise exception 'Documento % inesistente o non visibile.', p_documento_id;
  end if;

  if v_doc.stato = 'confermato' then
    raise exception 'Il documento e'' gia'' stato confermato il %.', v_doc.confermato_il;
  end if;

  if v_doc.stato = 'annullato' then
    raise exception 'Il documento e'' annullato: non si puo'' confermare.';
  end if;

  if not magazzino.ha_ruolo(v_doc.organizzazione_id, array['titolare','gestore']) then
    raise exception 'Solo titolare o gestore possono confermare un carico.';
  end if;

  -- ── 2. Le righe devono essere tutte risolte ─────────────────────────────
  -- Meglio fermarsi prima con un elenco preciso che caricare meta' documento.
  select string_agg(numero_riga::text, ', ' order by numero_riga)
    into v_problemi
  from magazzino.documento_carico_riga
  where documento_id = p_documento_id
    and stato_match <> 'ignorata'
    and (
      ingrediente_id is null
      or coalesce(quantita_reale, quantita_base) is null
      or coalesce(quantita_reale, quantita_base) = 0
    );

  if v_problemi is not null then
    raise exception
      'Righe senza ingrediente o senza quantita'': %. Risolvere prima di confermare.',
      v_problemi;
  end if;

  if not exists (
    select 1 from magazzino.documento_carico_riga
    where documento_id = p_documento_id and stato_match <> 'ignorata'
  ) then
    raise exception 'Il documento non ha righe da caricare.';
  end if;

  -- ── 3. Verso e causale ──────────────────────────────────────────────────
  if v_doc.tipo = 'reso' then
    v_verso   := -1;
    v_causale := 'reso_fornitore';
  else
    v_verso   := 1;
    v_causale := 'carico_acquisto';
  end if;

  -- Magazzino di destinazione: quello della riga, se manca quello del
  -- documento, se manca l'unico attivo dell'organizzazione.
  select id into v_deposito
  from magazzino.deposito
  where organizzazione_id = v_doc.organizzazione_id and attivo
  order by ordinamento, codice
  limit 1;

  -- ── 4. Riga per riga ────────────────────────────────────────────────────
  for v_riga in
    select *
    from magazzino.documento_carico_riga
    where documento_id = p_documento_id
      and stato_match <> 'ignorata'
    order by numero_riga
  loop
    select * into v_ing
    from magazzino.ingrediente
    where id = v_riga.ingrediente_id;

    -- La pesata vince sul dichiarato.
    v_qta := coalesce(v_riga.quantita_reale, v_riga.quantita_base);

    -- Costo per unita' base. Se non e' stato calcolato a monte, si ricava dal
    -- totale di riga, che e' il dato piu' affidabile del documento: e' quello
    -- che quadra col totale della fattura.
    v_costo := coalesce(
      v_riga.costo_unitario_base,
      case when v_qta <> 0 and v_riga.totale_riga is not null
           then abs(v_riga.totale_riga) / abs(v_qta) end
    );

    -- ── Lotto ──────────────────────────────────────────────────────────
    v_lotto := null;
    if v_verso = 1 and (
         v_ing.gestisci_lotti
      or v_ing.richiede_abbattimento
      or v_riga.lotto_fornitore is not null
      or v_riga.data_scadenza is not null
    ) then
      insert into magazzino.lotto (
        organizzazione_id, ingrediente_id, fornitore_id, codice, lotto_fornitore,
        documento_riga_id, data_carico, data_scadenza,
        quantita_iniziale, costo_unitario
      )
      values (
        v_doc.organizzazione_id, v_ing.id, v_doc.fornitore_id,
        to_char(v_doc.data_consegna, 'YYYY') || '-' ||
          lpad(nextval('magazzino.lotto_progressivo')::text, 5, '0'),
        v_riga.lotto_fornitore,
        v_riga.id, v_doc.data_consegna,
        coalesce(v_riga.data_scadenza,
                 case when v_ing.giorni_scadenza_default is not null
                      then v_doc.data_consegna + v_ing.giorni_scadenza_default end),
        v_qta, v_costo
      )
      returning id into v_lotto;

      v_n_lotti := v_n_lotti + 1;
    end if;

    -- ── Movimento ──────────────────────────────────────────────────────
    insert into magazzino.movimento (
      organizzazione_id, ingrediente_id, deposito_id, lotto_id,
      causale_codice, quantita, costo_unitario,
      data_competenza, documento_riga_id, creato_da
    )
    values (
      v_doc.organizzazione_id, v_ing.id,
      coalesce(v_riga.deposito_id, v_doc.deposito_id, v_deposito),
      v_lotto,
      v_causale, v_verso * abs(v_qta), v_costo,
      v_doc.data_consegna, v_riga.id, auth.uid()
    );

    -- ── Costo medio ponderato mobile ───────────────────────────────────
    -- Si calcola sulla giacenza PRIMA di questo carico. Il movimento e' gia'
    -- scritto, quindi va sottratto.
    if v_costo is not null and v_verso = 1 then
      select coalesce(sum(quantita), 0) - (v_verso * abs(v_qta))
        into v_giacenza
      from magazzino.movimento
      where organizzazione_id = v_doc.organizzazione_id
        and ingrediente_id = v_ing.id;

      if v_giacenza > 0 and v_ing.costo_medio is not null then
        v_nuovo_costo := (v_giacenza * v_ing.costo_medio + abs(v_qta) * v_costo)
                         / (v_giacenza + abs(v_qta));
      else
        -- Giacenza nulla o negativa, oppure primo acquisto: la media non ha
        -- storia su cui appoggiarsi, vale il prezzo appena pagato.
        v_nuovo_costo := v_costo;
      end if;

      update magazzino.ingrediente
      set costo_medio         = v_nuovo_costo,
          ultimo_costo        = v_costo,
          costo_aggiornato_il = now()
      where id = v_ing.id;
    end if;

    -- ── Storico prezzi ─────────────────────────────────────────────────
    if v_costo is not null and v_verso = 1 then
      insert into magazzino.storico_prezzo (
        organizzazione_id, ingrediente_id, fornitore_id, articolo_fornitore_id,
        documento_riga_id, data, prezzo_acquisto, prezzo_um_base
      )
      values (
        v_doc.organizzazione_id, v_ing.id, v_doc.fornitore_id,
        v_riga.articolo_fornitore_id, v_riga.id, v_doc.data_consegna,
        v_riga.prezzo_unitario, v_costo
      );
    end if;

    -- ── L'articolo del fornitore impara ────────────────────────────────
    if v_riga.articolo_fornitore_id is not null then
      update magazzino.articolo_fornitore
      set ultimo_prezzo         = coalesce(v_riga.prezzo_unitario, ultimo_prezzo),
          ultimo_prezzo_um_base = coalesce(v_costo, ultimo_prezzo_um_base),
          ultimo_acquisto_il    = v_doc.data_consegna,
          ingrediente_id        = coalesce(ingrediente_id, v_ing.id)
      where id = v_riga.articolo_fornitore_id;

      -- La grafia incontrata su questo documento diventa memoria: la prossima
      -- volta che il fornitore scrivera' cosi', il riconoscimento e' esatto
      -- e non stimato. E' il meccanismo per cui il sistema smette
      -- progressivamente di fare domande.
      insert into magazzino.alias_articolo (
        organizzazione_id, articolo_fornitore_id,
        testo_originale, testo_normalizzato, origine
      )
      values (
        v_doc.organizzazione_id, v_riga.articolo_fornitore_id,
        v_riga.descrizione_originale,
        coalesce(magazzino.normalizza(v_riga.descrizione_originale), ''),
        v_doc.origine
      )
      on conflict (organizzazione_id, articolo_fornitore_id, testo_normalizzato)
      do update set conteggio_usi = magazzino.alias_articolo.conteggio_usi + 1,
                    ultimo_uso_il = now();
    end if;

    -- Marca la riga come definitivamente risolta.
    update magazzino.documento_carico_riga
    set stato_match = 'confermato'
    where id = v_riga.id;

    v_n_righe := v_n_righe + 1;
    v_totale  := v_totale + coalesce(v_riga.totale_riga, 0);
    v_valore  := v_valore + coalesce(abs(v_qta) * v_costo, 0);
  end loop;

  -- ── 5. Chiusura del documento ───────────────────────────────────────────
  update magazzino.documento_carico
  set stato            = 'confermato',
      totale_calcolato = v_totale,
      confermato_da    = auth.uid(),
      confermato_il    = now()
  where id = p_documento_id;

  return jsonb_build_object(
    'documento_id',      p_documento_id,
    'righe_caricate',    v_n_righe,
    'lotti_creati',      v_n_lotti,
    'totale_documento',  v_totale,
    'valore_caricato',   round(v_valore, 2),
    -- Se questi due non coincidono, l'AI ha letto male qualcosa: e' il
    -- controllo piu' economico che abbiamo, e va mostrato all'operatore.
    'totale_dichiarato', v_doc.totale_dichiarato,
    'scostamento',       case when v_doc.totale_dichiarato is not null
                              then round(v_totale - v_doc.totale_dichiarato, 2) end
  );
end;
$$;

comment on function magazzino.conferma_carico(uuid) is
  'Trasforma un documento in bozza in movimenti, lotti, prezzi e alias. Tutto o niente. Restituisce un riepilogo con lo scostamento fra totale calcolato e totale dichiarato.';


-- ----------------------------------------------------------------------------
--  storna_carico
-- ----------------------------------------------------------------------------
--  Annulla un carico confermato senza cancellare niente: scrive i movimenti
--  contrari. Se un carico e' stato sbagliato, la storia deve mostrare che e'
--  stato fatto e poi corretto, non fingere che non sia mai successo.
create or replace function magazzino.storna_carico(
  p_documento_id uuid,
  p_motivo       text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_doc      magazzino.documento_carico%rowtype;
  v_mov      record;
  v_n        integer := 0;
begin
  select * into v_doc
  from magazzino.documento_carico
  where id = p_documento_id
  for update;

  if not found then
    raise exception 'Documento % inesistente o non visibile.', p_documento_id;
  end if;

  if v_doc.stato <> 'confermato' then
    raise exception 'Si puo'' stornare solo un documento confermato (stato attuale: %).', v_doc.stato;
  end if;

  if not magazzino.ha_ruolo(v_doc.organizzazione_id, array['titolare','gestore']) then
    raise exception 'Solo titolare o gestore possono stornare un carico.';
  end if;

  for v_mov in
    select m.*
    from magazzino.movimento m
    join magazzino.documento_carico_riga r on r.id = m.documento_riga_id
    where r.documento_id = p_documento_id
      and not exists (
        select 1 from magazzino.movimento s where s.movimento_stornato_id = m.id
      )
  loop
    insert into magazzino.movimento (
      organizzazione_id, ingrediente_id, deposito_id, lotto_id,
      causale_codice, quantita, costo_unitario,
      data_competenza, documento_riga_id, movimento_stornato_id,
      note, creato_da
    )
    values (
      v_mov.organizzazione_id, v_mov.ingrediente_id, v_mov.deposito_id, v_mov.lotto_id,
      'storno', -v_mov.quantita, v_mov.costo_unitario,
      current_date, v_mov.documento_riga_id, v_mov.id,
      coalesce(p_motivo, 'Storno del documento ' || coalesce(v_doc.numero_documento, '(senza numero)')),
      auth.uid()
    );
    v_n := v_n + 1;
  end loop;

  update magazzino.lotto
  set stato = 'scartato'
  where documento_riga_id in (
    select id from magazzino.documento_carico_riga where documento_id = p_documento_id
  );

  update magazzino.documento_carico
  set stato = 'annullato',
      note  = trim(both e'\n' from coalesce(note, '') || e'\n' ||
                   'Stornato il ' || to_char(now(), 'DD/MM/YYYY HH24:MI') ||
                   coalesce(': ' || p_motivo, ''))
  where id = p_documento_id;

  return jsonb_build_object(
    'documento_id',      p_documento_id,
    'movimenti_stornati', v_n,
    -- Il costo medio NON viene ripristinato al valore precedente, e non e'
    -- una dimenticanza: una media ponderata mobile non e' invertibile, il
    -- valore di prima non e' ricostruibile da quello di dopo. Si riallinea
    -- da solo al carico successivo, oppure lo si corregge a mano.
    'nota',              'Costo medio non ripristinato: si riallinea al prossimo carico.'
  );
end;
$$;


grant execute on function magazzino.conferma_carico(uuid) to authenticated;
grant execute on function magazzino.storna_carico(uuid, text) to authenticated;
