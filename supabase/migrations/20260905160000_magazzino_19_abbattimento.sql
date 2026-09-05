-- ============================================================================
--  MAGAZZINO HIO — file 19: registrazione dell'abbattimento
-- ============================================================================
--
--  Il pesce destinato al consumo crudo va bonificato dall'anisakis prima di
--  essere servito. Il Reg. CE 853/2004 fissa due modi, e sono alternativi:
--
--      -20 °C o meno   per almeno 24 ore
--      -35 °C o meno   per almeno 15 ore
--
--  Questa funzione li verifica invece di limitarsi a registrare quello che
--  le viene detto. Una registrazione che accetta qualunque valore non è un
--  documento: è un modulo compilato. Se il trattamento non rispetta i limiti,
--  rifiuta e spiega perché — meglio scoprirlo davanti all'abbattitore che
--  davanti a un ispettore.
-- ============================================================================

set search_path = magazzino, extensions, public;

create or replace function magazzino.registra_abbattimento(
  p_lotto_id    uuid,
  p_inizio      timestamptz,
  p_fine        timestamptz,
  p_temperatura numeric
)
returns jsonb
language plpgsql
security invoker
set search_path = magazzino, public
as $$
declare
  v_lotto magazzino.lotto%rowtype;
  v_ore   numeric;
begin
  select * into v_lotto from magazzino.lotto where id = p_lotto_id for update;
  if not found then
    raise exception 'Lotto % inesistente o non visibile.', p_lotto_id;
  end if;
  if v_lotto.abbattuto then
    raise exception 'Il lotto % risulta già abbattuto il %.',
      v_lotto.codice, to_char(v_lotto.data_abbattimento_fine, 'DD/MM/YYYY HH24:MI');
  end if;

  if p_fine <= p_inizio then
    raise exception 'La fine deve venire dopo l''inizio.';
  end if;

  v_ore := extract(epoch from (p_fine - p_inizio)) / 3600.0;

  -- I due trattamenti ammessi. Fuori da questi due casi non è abbattimento,
  -- è solo pesce messo in freezer.
  if p_temperatura <= -35 then
    if v_ore < 15 then
      raise exception
        'A % °C servono almeno 15 ore: ne risultano %.',
        magazzino.numero_it(p_temperatura), magazzino.numero_it(round(v_ore, 1));
    end if;
  elsif p_temperatura <= -20 then
    if v_ore < 24 then
      raise exception
        'A % °C servono almeno 24 ore: ne risultano %.',
        magazzino.numero_it(p_temperatura), magazzino.numero_it(round(v_ore, 1));
    end if;
  else
    raise exception
      'A % °C non è abbattimento: servono -20 °C per 24 ore, oppure -35 °C per 15 ore.',
      magazzino.numero_it(p_temperatura);
  end if;

  update magazzino.lotto
  set abbattuto                = true,
      data_abbattimento_inizio = p_inizio,
      data_abbattimento_fine   = p_fine,
      temperatura_abbattimento = p_temperatura,
      abbattuto_da             = auth.uid()
  where id = p_lotto_id;

  return jsonb_build_object(
    'lotto_id',    p_lotto_id,
    'codice',      v_lotto.codice,
    'ore',         round(v_ore, 1),
    'temperatura', p_temperatura,
    'conforme',    true
  );
end;
$$;

comment on function magazzino.registra_abbattimento(uuid, timestamptz, timestamptz, numeric) is
  'Registra l''abbattimento verificando i limiti del Reg. CE 853/2004. Rifiuta i trattamenti non conformi invece di archiviarli come validi.';


-- ----------------------------------------------------------------------------
--  Il registro
-- ----------------------------------------------------------------------------
--  Quello che si mostra a un controllo: cosa è stato abbattuto, quando, a
--  che temperatura, per quanto, e da chi. Esce dal magazzino senza che
--  nessuno debba tenere un quaderno a parte.
create or replace view magazzino.registro_abbattimenti
with (security_invoker = true)
as
select
  l.organizzazione_id,
  l.id                                as lotto_id,
  l.codice                            as lotto,
  i.nome                              as ingrediente,
  f.denominazione                     as fornitore,
  l.lotto_fornitore,
  l.data_carico,
  l.data_abbattimento_inizio,
  l.data_abbattimento_fine,
  round(extract(epoch from
    (l.data_abbattimento_fine - l.data_abbattimento_inizio)) / 3600.0, 1) as ore,
  l.temperatura_abbattimento,
  l.quantita_iniziale,
  i.um_base,
  l.abbattuto_da
from magazzino.lotto l
join magazzino.ingrediente i on i.id = l.ingrediente_id
left join magazzino.fornitore f on f.id = l.fornitore_id
where l.abbattuto;

grant execute on function
  magazzino.registra_abbattimento(uuid, timestamptz, timestamptz, numeric)
  to authenticated;
