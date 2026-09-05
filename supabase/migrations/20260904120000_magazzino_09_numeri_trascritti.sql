-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 9: i numeri li converte il codice
-- ============================================================================
--
--  Seconda lezione dallo stesso DDT, e piu' importante della prima.
--
--  Il documento diceva:  720.000,00 PZ  ×  0,007  =  5.040,00
--  Prima lettura:        720 × 0,007 = 5.040,00     → i conti non tornano,
--                                                      il controllo lo becca
--  Dopo aver aggiunto al prompt "controlla che i conti tornino":
--  Seconda lettura:      720 × 7,0000 = 5.040,00    → i conti tornano,
--                                                      e l'errore e' invisibile
--
--  Il modello non ha riletto l'immagine: ha aggiustato i numeri finche' non
--  erano coerenti. Chiedere a un modello di verificarsi da solo lo invita a
--  fabbricare la coerenza, che e' esattamente il guasto peggiore: un dato
--  sbagliato che supera tutti i controlli.
--
--  Rimedio: il modello TRASCRIVE la stringa stampata ("720.000,00") e la
--  conversione la fa questo file, con regole fisse e verificabili. Leggere
--  caratteri e' cio' che un modello di visione sa fare; decidere se un punto
--  separa le migliaia o i decimali e' cio' che sa fare il codice.
-- ============================================================================

set search_path = magazzino, extensions, public;


-- ----------------------------------------------------------------------------
--  numero_it_da_testo
-- ----------------------------------------------------------------------------
--  Regole, pensate per documenti italiani:
--
--    c'e' una virgola          → la virgola separa i decimali, i punti le
--                                migliaia.        "1.250,50" → 1250.50
--    solo punti, piu' di uno   → tutti separatori di migliaia.
--                                                 "1.720.000" → 1720000
--    un punto solo, 3 cifre    → separatore di migliaia.
--    dopo, e non inizia con 0                     "720.000" → 720000
--    tutti gli altri casi      → il punto separa i decimali.
--                                                 "0.007" → 0.007
--                                                 "12.5"  → 12.5
--
--  Il caso "inizia con 0" esiste perche' nessuno scrive zero migliaia:
--  "0.007" e' un decimale scritto all'inglese, non settemila.
create or replace function magazzino.numero_it_da_testo(p_testo text)
returns numeric
language plpgsql
immutable
as $$
declare
  v          text;
  v_negativo boolean := false;
  v_virgole  integer;
  v_punti    integer;
  v_coda     integer;   -- cifre dopo l'ultimo punto
  v_testa    text;      -- cifre prima del primo punto
begin
  if p_testo is null then return null; end if;

  v := btrim(p_testo);
  if v = '' then return null; end if;

  -- Il segno prima di buttare via tutto il resto. Sui documenti il negativo
  -- si scrive anche fra parentesi.
  if v ~ '^\s*-' or v ~ '^\s*\(' then v_negativo := true; end if;

  v := regexp_replace(v, '[^0-9.,]', '', 'g');
  if v = '' or v !~ '[0-9]' then return null; end if;

  v_virgole := length(v) - length(replace(v, ',', ''));
  v_punti   := length(v) - length(replace(v, '.', ''));

  if v_virgole > 0 then
    -- Virgola presente: e' lei il separatore decimale. Se ce n'e' piu' d'una
    -- il numero e' illeggibile e non si indovina.
    if v_virgole > 1 then return null; end if;
    v := replace(v, '.', '');
    v := replace(v, ',', '.');

  elsif v_punti > 1 then
    -- Piu' punti e nessuna virgola: sono tutti separatori di migliaia.
    v := replace(v, '.', '');

  elsif v_punti = 1 then
    v_testa := split_part(v, '.', 1);
    v_coda  := length(split_part(v, '.', 2));

    if v_coda = 3 and v_testa <> '' and v_testa !~ '^0+$' then
      -- "720.000" → migliaia. "0.007" no: nessuno scrive zero migliaia.
      v := replace(v, '.', '');
    end if;
    -- Negli altri casi il punto resta dov'e': e' gia' un decimale valido.
  end if;

  if v !~ '^[0-9]*\.?[0-9]+$' and v !~ '^[0-9]+\.?[0-9]*$' then
    return null;
  end if;

  return case when v_negativo then -v::numeric else v::numeric end;
exception
  when others then return null;
end;
$$;

comment on function magazzino.numero_it_da_testo(text) is
  'Converte un numero trascritto da un documento italiano. Esiste perche'' il modello di visione non deve interpretare i separatori: trascrive, e la conversione la fa questa funzione con regole fisse.';


-- ----------------------------------------------------------------------------
--  Le stringhe come sono stampate
-- ----------------------------------------------------------------------------
alter table magazzino.documento_carico_riga
  add column if not exists quantita_testo text,
  add column if not exists prezzo_testo   text,
  add column if not exists totale_testo   text;

comment on column magazzino.documento_carico_riga.quantita_testo is
  'La quantita'' esattamente come e'' stampata sul documento ("720.000,00"). E'' il dato di partenza: il campo numerico si ricava da qui, non viceversa.';


-- ----------------------------------------------------------------------------
--  Trigger di conversione
-- ----------------------------------------------------------------------------
--  Quando c'e' la trascrizione, e' lei a comandare: il numero calcolato dal
--  modello viene ignorato. In UPDATE agisce solo se la trascrizione cambia,
--  altrimenti sovrascriverebbe le correzioni fatte a mano dall'operatore.
create or replace function magazzino.riga_converti_numeri()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  if new.quantita_testo is not null
     and (tg_op = 'INSERT' or new.quantita_testo is distinct from old.quantita_testo) then
    new.quantita_dichiarata := coalesce(
      magazzino.numero_it_da_testo(new.quantita_testo), new.quantita_dichiarata);
  end if;

  if new.prezzo_testo is not null
     and (tg_op = 'INSERT' or new.prezzo_testo is distinct from old.prezzo_testo) then
    new.prezzo_unitario := coalesce(
      magazzino.numero_it_da_testo(new.prezzo_testo), new.prezzo_unitario);
  end if;

  if new.totale_testo is not null
     and (tg_op = 'INSERT' or new.totale_testo is distinct from old.totale_testo) then
    new.totale_riga := coalesce(
      magazzino.numero_it_da_testo(new.totale_testo), new.totale_riga);
  end if;

  return new;
end;
$$;

drop trigger if exists riga_converti_numeri_tg on magazzino.documento_carico_riga;
create trigger riga_converti_numeri_tg
  before insert or update on magazzino.documento_carico_riga
  for each row execute function magazzino.riga_converti_numeri();


grant execute on function magazzino.numero_it_da_testo(text) to authenticated;
