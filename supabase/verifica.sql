-- ============================================================================
--  Verifica dopo l'installazione — non modifica nulla
-- ============================================================================
--  UNA SOLA query: il SQL Editor di Supabase mostra solo il risultato
--  dell'ultima istruzione, quindi gli 11 controlli devono uscire insieme.
--
--  Attesi: 20 tabelle, 3 viste, 13 causali, 14 allergeni, 5 depositi,
--  zero tabelle senza RLS, zero policy di scrittura sul libro mastro.
-- ============================================================================

with controlli as (

  -- 1. Serve Postgres 15 o superiore
  select 1 as n, 'versione postgres' as controllo,
    current_setting('server_version') as valore,
    case when current_setting('server_version_num')::int >= 150000
         then 'OK' else 'ERRORE: serve Postgres 15+' end as esito

  union all
  -- 2. Tabelle create
  select 2, 'tabelle', count(*)::text,
    case when count(*) = 20 then 'OK' else 'ERRORE: attese 20' end
  from pg_tables where schemaname = 'magazzino'

  union all
  -- 3. Viste create: giacenza, giacenza_valorizzata, giacenza_lotto,
  --    documento_riepilogo
  select 3, 'viste', count(*)::text,
    case when count(*) = 4 then 'OK' else 'ERRORE: attese 4' end
  from pg_views where schemaname = 'magazzino'

  union all
  -- 4. Nessuna tabella deve restare senza RLS
  select 4, 'tabelle senza RLS',
    coalesce(string_agg(c.relname, ', '), 'nessuna'),
    case when count(*) = 0 then 'OK' else 'ERRORE: RLS mancante' end
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'magazzino' and c.relkind = 'r' and not c.relrowsecurity

  union all
  -- 5. Le viste devono girare coi permessi di chi interroga.
  --    Se qui esce ERRORE, un cliente vedrebbe i dati di un altro.
  select 5, 'viste security_invoker',
    coalesce(string_agg(c.relname, ', '), 'tutte protette'),
    case when count(*) = 0 then 'OK' else 'ERRORE: vista non protetta' end
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'magazzino' and c.relkind = 'v'
    and coalesce(array_to_string(c.reloptions, ','), '') not like '%security_invoker=true%'

  union all
  -- 6. Il libro mastro non deve avere policy di UPDATE ne' DELETE
  select 6, 'movimento sola aggiunta',
    coalesce(string_agg(polname, ', '), 'nessuna policy distruttiva'),
    case when to_regclass('magazzino.movimento') is null
              then 'ERRORE: tabella assente'
         when count(*) = 0 then 'OK'
         else 'ERRORE: il mastro e'' modificabile' end
  from pg_policy
  where polrelid = to_regclass('magazzino.movimento')
    and polcmd in ('w', 'd')

  union all
  -- 7. Causali di sistema
  select 7, 'causali', count(*)::text,
    case when count(*) = 13 then 'OK' else 'ERRORE: attese 13' end
  from magazzino.causale

  union all
  -- 8. Allergeni di legge
  select 8, 'allergeni', count(*)::text,
    case when count(*) = 14 then 'OK' else 'ERRORE: attesi 14' end
  from magazzino.allergene

  union all
  -- 9. Magazzino (solo dopo dati_iniziali/01_hio.sql). Uno solo, per scelta.
  select 9, 'magazzini',
    coalesce(string_agg(codice, ', ' order by ordinamento), 'nessuno'),
    case when count(*) = 1 then 'OK'
         when count(*) = 0 then 'ATTENZIONE: dati_iniziali non eseguito'
         else 'ATTENZIONE: ne risultano piu'' di uno' end
  from magazzino.deposito

  union all
  -- 10. Utenti abilitati. Finche' e' vuota, l'app non mostra nulla a nessuno.
  select 10, 'utenti abilitati', count(*)::text,
    case when count(*) > 0 then 'OK'
         else 'ATTENZIONE: nessuno vedra'' dati finche'' non ti aggiungi' end
  from magazzino.utente_organizzazione where attivo

  union all
  -- 11. Solo informativo. Su un progetto di prova public e' vuoto: giusto
  --     cosi'. In produzione deve contenere le tabelle delle prenotazioni.
  select 11, 'tabelle in public', count(*)::text,
    case when count(*) = 0 then 'INFO: vuoto, corretto su un progetto di prova'
         else 'INFO: in produzione devono restare tutte' end
  from pg_tables where schemaname = 'public'

  union all
  -- 12. Il bucket delle foto deve esistere e NON essere pubblico
  select 12, 'bucket documenti',
    coalesce(string_agg(id || case when public then ' (PUBBLICO)' else ' (privato)' end, ', '), 'assente'),
    case when count(*) = 1 and bool_and(not public) then 'OK'
         when count(*) = 0 then 'ERRORE: bucket assente'
         else 'ERRORE: il bucket e'' pubblico' end
  from storage.buckets where id = 'documenti-magazzino'

  union all
  -- 13. Le quattro policy sui file
  select 13, 'policy sui file', count(*)::text,
    case when count(*) = 4 then 'OK'
         else 'ERRORE: attese 4, crearle da Storage → Policies' end
  from pg_policy
  where polrelid = to_regclass('storage.objects')
    and polname like 'magazzino documenti%'

)
select n as "#", controllo, valore, esito
from controlli
order by n;
