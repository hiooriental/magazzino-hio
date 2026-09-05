-- ============================================================================
--  MAGAZZINO HIO — Sezione 1, file 14: eliminare una bozza
-- ============================================================================
--
--  Le bozze sbagliate vanno via, i carichi confermati no.
--
--  Il database gia' si difende da solo: `movimento.documento_riga_id` e'
--  `on delete restrict`, quindi cancellare un documento confermato fallisce
--  comunque. Ma fallisce con un messaggio da manuale di PostgreSQL, che a chi
--  sta lavorando non dice niente. Questo trigger arriva prima e spiega.
--
--  Perche' non un "annulla" al posto della cancellazione: un carico
--  confermato si storna (`storna_carico`), e li' la storia resta. Un documento
--  MAI confermato invece non e' storia di niente — e' una foto venuta male o
--  un doppione, e tenerlo in archivio serve solo a sporcare l'elenco.
-- ============================================================================

set search_path = magazzino, extensions, public;

create or replace function magazzino.documento_blocca_eliminazione()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
begin
  if old.stato = 'confermato' then
    raise exception
      'Il documento % e'' confermato e ha gia'' mosso il magazzino: non si cancella, si storna.',
      coalesce(old.numero_documento, '(senza numero)');
  end if;

  -- Un documento annullato e' gia' passato per uno storno: i movimenti
  -- contrari lo referenziano, e devono restare leggibili.
  if old.stato = 'annullato' then
    raise exception
      'Il documento % e'' stato stornato: resta in archivio come prova di cio'' che e'' successo.',
      coalesce(old.numero_documento, '(senza numero)');
  end if;

  return old;
end;
$$;

drop trigger if exists documento_blocca_eliminazione_tg on magazzino.documento_carico;
create trigger documento_blocca_eliminazione_tg
  before delete on magazzino.documento_carico
  for each row execute function magazzino.documento_blocca_eliminazione();
