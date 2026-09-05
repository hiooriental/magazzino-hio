-- ============================================================================
--  MAGAZZINO HIO — file 20: le bozze si possono buttare
-- ============================================================================
--
--  `estrazione_ai` è a sola aggiunta perché, quando fra sei mesi un carico
--  risulterà sbagliato, quella tabella è l'unico modo per sapere se ha
--  sbagliato il modello o l'operatore che ha confermato. Giusto.
--
--  Ma il trigger bloccava anche la cancellazione a cascata, e quindi rendeva
--  ineliminabile qualunque bozza: una foto venuta male restava in archivio
--  per sempre. La regola serviva a proteggere la storia di un carico
--  confermato, non a impedire di buttare una prova mal riuscita.
--
--  Nuova regola: la lettura non si modifica MAI, e non si cancella finché il
--  documento a cui appartiene ha mosso il magazzino. Una bozza che non ha
--  mosso niente non è storia di niente.
--
--  La protezione resta intera anche a cascata, perché un documento confermato
--  non si può cancellare (trigger del file 14): senza padre eliminabile, i
--  figli non spariscono.
-- ============================================================================

set search_path = magazzino, extensions, public;

create or replace function magazzino.estrazione_ai_protezione()
returns trigger
language plpgsql
set search_path = magazzino, public
as $$
declare
  v_stato text;
begin
  if tg_op = 'UPDATE' then
    raise exception
      'Le letture dell''AI non si modificano: sono la prova di cosa ha risposto il modello.';
  end if;

  select stato into v_stato
  from magazzino.documento_carico
  where id = old.documento_id;

  -- Se il documento non c'è più siamo dentro una cascata già autorizzata:
  -- il suo trigger ha già deciso che si poteva cancellare.
  if v_stato in ('confermato', 'annullato') then
    raise exception
      'Il documento ha già mosso il magazzino: la lettura resta come prova di come è stato letto.';
  end if;

  return old;
end;
$$;

drop trigger if exists estrazione_ai_sola_aggiunta on magazzino.estrazione_ai;
create trigger estrazione_ai_protezione_tg
  before update or delete on magazzino.estrazione_ai
  for each row execute function magazzino.estrazione_ai_protezione();
