-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 10: anche i totali si trascrivono
-- ============================================================================
--
--  Stessa cura applicata alle righe, estesa alla testata. E una separazione
--  che finora mancava:
--
--    totale_dichiarato → l'IMPONIBILE, l'unico numero confrontabile con la
--                        somma delle righe
--    totale_documento  → il totale IVA compresa, quello stampato in fondo
--
--  Tenerli separati non e' pignoleria contabile. Se in `totale_dichiarato`
--  finisse il lordo, la conferma segnalerebbe uno scostamento del 22% a ogni
--  singolo documento, e dopo due settimane nessuno guarderebbe piu' quella
--  segnalazione. Un allarme che suona sempre e' un allarme spento.
--
--  Per lo stesso motivo, se l'imponibile non si legge `totale_dichiarato`
--  resta NULL: meglio nessun confronto che un confronto falso.
-- ============================================================================

set search_path = magazzino, extensions, public;

alter table magazzino.documento_carico
  add column if not exists totale_imponibile_testo text,
  add column if not exists totale_documento_testo  text,
  add column if not exists totale_documento        numeric(12,2);

comment on column magazzino.documento_carico.totale_dichiarato is
  'Imponibile letto sul documento, al netto dell''IVA. E'' il termine di confronto con la somma delle righe. Se non si legge resta NULL: un confronto falso e'' peggio di nessun confronto.';

comment on column magazzino.documento_carico.totale_documento is
  'Totale IVA compresa, quello stampato in fondo. Serve a farlo riconoscere all''operatore che ha il documento in mano, non ai calcoli.';


create or replace function magazzino.documento_converti_numeri()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  if new.totale_imponibile_testo is not null
     and (tg_op = 'INSERT'
          or new.totale_imponibile_testo is distinct from old.totale_imponibile_testo) then
    new.totale_dichiarato := coalesce(
      magazzino.numero_it_da_testo(new.totale_imponibile_testo), new.totale_dichiarato);
  end if;

  if new.totale_documento_testo is not null
     and (tg_op = 'INSERT'
          or new.totale_documento_testo is distinct from old.totale_documento_testo) then
    new.totale_documento := coalesce(
      magazzino.numero_it_da_testo(new.totale_documento_testo), new.totale_documento);
  end if;

  return new;
end;
$$;

drop trigger if exists documento_converti_numeri_tg on magazzino.documento_carico;
create trigger documento_converti_numeri_tg
  before insert or update on magazzino.documento_carico
  for each row execute function magazzino.documento_converti_numeri();
