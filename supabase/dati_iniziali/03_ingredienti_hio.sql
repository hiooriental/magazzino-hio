-- ============================================================================
--  Ingredienti HIO — anagrafica iniziale, ricavata dal menu
-- ============================================================================
--
--  Ricavata leggendo le descrizioni dei piatti sul sito. Non sostituisce i
--  carichi: serve a fare in modo che la PRIMA fattura trovi già qualcosa a
--  cui agganciarsi, invece di creare un ingrediente nuovo per ogni riga.
--
--  Tre distinzioni che il menu non fa e che qui contano:
--
--  COSA SI COMPRA e COSA SI PRODUCE.  «Salsa hio», «ragout di wagyu», «bao a
--    vapore», «teriyaki allo yuzu» non si comprano: si preparano. Sono
--    semilavorati (`prodotto_internamente`), hanno una loro distinta e un
--    costo che nasce dalle lavorazioni. Metterli fra gli acquisti vorrebbe
--    dire cercarli invano sulle fatture.
--
--  COSA VA ABBATTUTO.  Tonno, salmone, gambero rosso, scampi, ricciola:
--    vanno crudi nel piatto, quindi obbligo di abbattimento documentato
--    (Reg. CE 853/2004). Il flag fa comparire il lotto fra quelli da
--    trattare appena entra.
--
--  COSA MERITA UN LOTTO.  Il pesce e la carne sì, il sale no. Un lotto per
--    ogni confezione di panko riempirebbe l'archivio di righe che nessuno
--    guarderà mai.
--
--  Le quantità sono sempre in g, ml o pz: mai kg o litri.
--
--  NON è una migrazione: sono dati. Idempotente, si può rieseguire.
--  I nomi sono quelli che usate voi, non quelli dei fornitori: la traduzione
--  fra le due cose la impara il sistema, una volta per articolo.
-- ============================================================================

set search_path = magazzino, public;

insert into magazzino.ingrediente (
  organizzazione_id, nome, um_base, conservazione, categoria_id,
  richiede_abbattimento, gestisci_lotti, prodotto_internamente
)
select
  '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d',
  x.nome, x.um, x.cons,
  (select c.id from magazzino.categoria_ingrediente c
    where c.organizzazione_id = '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d'
      and c.nome = x.cat),
  x.abbattimento, x.lotti, x.interno
from (values

  -- ── Pesce destinato al crudo ──────────────────────────────────────────
  -- Abbattimento obbligatorio: entrano in magazzino e compaiono subito
  -- nell'elenco di quelli da trattare.
  ('Tonno rosso Fuentes',        'g',  'frigo',   'Pesce per crudo', true,  true,  false),
  ('Salmone Ora King',           'g',  'frigo',   'Pesce per crudo', true,  true,  false),
  ('Ricciola hamachi',           'g',  'frigo',   'Pesce per crudo', true,  true,  false),
  ('Gambero rosso di Mazara',    'g',  'frigo',   'Pesce per crudo', true,  true,  false),
  ('Scampi',                     'g',  'frigo',   'Pesce per crudo', true,  true,  false),

  -- ── Pesce e crostacei ─────────────────────────────────────────────────
  ('Mazzancolle',                'g',  'frigo',   'Pesce e crostacei', false, true,  false),
  ('Mazzancolle giganti',        'g',  'frigo',   'Pesce e crostacei', false, true,  false),
  ('Astice',                     'g',  'freezer', 'Pesce e crostacei', false, true,  false),
  ('Ostriche Gillardeau n4',     'pz', 'frigo',   'Pesce e crostacei', false, true,  false),
  ('Ricci di mare',              'g',  'frigo',   'Pesce e crostacei', false, true,  false),
  ('Caviale Baikal',             'g',  'frigo',   'Pesce e crostacei', false, true,  false),
  ('Nero di seppia',             'g',  'frigo',   'Pesce e crostacei', false, false, false),

  -- ── Carne ─────────────────────────────────────────────────────────────
  -- I tagli di wagyu sono separati perché si comprano separati e hanno
  -- prezzi molto diversi: tenerli insieme renderebbe il costo medio inutile.
  ('Wagyu A5 giapponese filetto',   'g', 'frigo', 'Carne', false, true,  false),
  ('Wagyu A5 australiano ribeye',   'g', 'frigo', 'Carne', false, true,  false),
  ('Wagyu A5 scamone',              'g', 'frigo', 'Carne', false, true,  false),
  ('Wagyu A5 trita',                'g', 'frigo', 'Carne', false, true,  false),
  ('Nobile grasso di wagyu',        'g', 'frigo', 'Carne', false, true,  false),
  ('Scottona bavarese macinata',    'g', 'frigo', 'Carne', false, true,  false),
  ('Pastrami Dierendonck',          'g', 'frigo', 'Carne', false, true,  false),
  ('Jamon pata negra',              'g', 'frigo', 'Carne', false, true,  false),
  ('Guanciale di pata negra',       'g', 'frigo', 'Carne', false, true,  false),
  ('Pancetta di maialino iberico',  'g', 'frigo', 'Carne', false, true,  false),

  -- ── Riso, paste, pani ─────────────────────────────────────────────────
  ('Riso per sushi',             'g',  'ambiente', 'Riso e cereali', false, false, false),
  ('Semola di grano duro',       'g',  'ambiente', 'Riso e cereali', false, false, false),
  ('Farina per bao',             'g',  'ambiente', 'Riso e cereali', false, false, false),
  ('Tonnarelli freschi',         'g',  'frigo',    'Riso e cereali', false, false, false),
  ('Mezzi paccheri',             'g',  'ambiente', 'Riso e cereali', false, false, false),
  ('Calamarata',                 'g',  'ambiente', 'Riso e cereali', false, false, false),
  ('Noodles di grano duro',      'g',  'ambiente', 'Riso e cereali', false, false, false),
  ('Panko',                      'g',  'ambiente', 'Riso e cereali', false, false, false),
  ('Pasta brick',                'pz', 'frigo',    'Riso e cereali', false, false, false),
  ('Sfoglia di riso',            'pz', 'ambiente', 'Riso e cereali', false, false, false),
  ('Tortilla',                   'pz', 'ambiente', 'Riso e cereali', false, false, false),
  ('Taco croccante',             'pz', 'ambiente', 'Riso e cereali', false, false, false),
  ('Shokupan',                   'pz', 'ambiente', 'Riso e cereali', false, false, false),
  ('Alga nori',                  'pz', 'ambiente', 'Riso e cereali', false, false, false),

  -- ── Verdura e frutta ──────────────────────────────────────────────────
  ('Avocado',                    'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Pack choi',                  'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Tenerumi',                   'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Lattuga',                    'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Cavolo cappuccio',           'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Cipolla bianca',             'g',  'ambiente', 'Verdura e frutta', false, false, false),
  ('Cipollotto',                 'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Erba cipollina',             'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Porro',                      'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Patate',                     'g',  'ambiente', 'Verdura e frutta', false, false, false),
  ('Pomodorino datterino',       'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Foglie di shiso',            'pz', 'frigo',    'Verdura e frutta', false, false, false),
  ('Zenzero',                    'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Aglio',                      'g',  'ambiente', 'Verdura e frutta', false, false, false),
  ('Lime',                       'pz', 'frigo',    'Verdura e frutta', false, false, false),
  ('Limoni',                     'pz', 'frigo',    'Verdura e frutta', false, false, false),
  ('Arance',                     'pz', 'frigo',    'Verdura e frutta', false, false, false),
  ('Fave fresche',               'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Fragole',                    'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Mango',                      'g',  'frigo',    'Verdura e frutta', false, false, false),
  ('Frutti di bosco',            'g',  'freezer',  'Verdura e frutta', false, false, false),
  ('Lamponi',                    'g',  'freezer',  'Verdura e frutta', false, false, false),
  ('Tartufo bianco fresco',      'g',  'frigo',    'Verdura e frutta', false, true,  false),

  -- ── Latticini e uova ──────────────────────────────────────────────────
  ('Mozzarella fior di latte',   'g',  'frigo', 'Latticini e uova', false, false, false),
  ('Cheddar',                    'g',  'frigo', 'Latticini e uova', false, false, false),
  ('Parmigiano 30 mesi',         'g',  'frigo', 'Latticini e uova', false, false, false),
  ('Parmigiano 36 mesi',         'g',  'frigo', 'Latticini e uova', false, false, false),
  ('Pecorino al tartufo 12 mesi','g',  'frigo', 'Latticini e uova', false, false, false),
  ('Caciocavallo ragusano',      'g',  'frigo', 'Latticini e uova', false, false, false),
  ('Burro',                      'g',  'frigo', 'Latticini e uova', false, false, false),
  ('Burro salato',               'g',  'frigo', 'Latticini e uova', false, false, false),
  ('Uova biologiche',            'pz', 'frigo', 'Latticini e uova', false, false, false),
  ('Latte di cocco',             'ml', 'ambiente', 'Latticini e uova', false, false, false),
  ('Gelato fior di latte',       'g',  'freezer',  'Latticini e uova', false, false, false),

  -- ── Salse e condimenti che si comprano ────────────────────────────────
  ('Salsa di soia',              'ml', 'ambiente', 'Salse e condimenti', false, false, false),
  ('Ponzu',                      'ml', 'ambiente', 'Salse e condimenti', false, false, false),
  ('Salsa teriyaki',             'ml', 'ambiente', 'Salse e condimenti', false, false, false),
  ('Maionese giapponese',        'ml', 'frigo',    'Salse e condimenti', false, false, false),
  ('Succo di yuzu',              'ml', 'frigo',    'Salse e condimenti', false, false, false),
  ('Gochujang',                  'g',  'frigo',    'Salse e condimenti', false, false, false),
  ('Pasta di miso',              'g',  'frigo',    'Salse e condimenti', false, false, false),
  ('Pasta di arachidi',          'g',  'ambiente', 'Salse e condimenti', false, false, false),
  ('Wasabi',                     'g',  'frigo',    'Salse e condimenti', false, false, false),
  ('Peperoncino fritto koreano', 'g',  'ambiente', 'Salse e condimenti', false, false, false),
  ('Senape',                     'ml', 'frigo',    'Salse e condimenti', false, false, false),
  ('Miele',                      'g',  'ambiente', 'Salse e condimenti', false, false, false),
  ('Miele al tartufo bianco',    'g',  'ambiente', 'Salse e condimenti', false, false, false),
  ('Aceto di riso',              'ml', 'ambiente', 'Salse e condimenti', false, false, false),
  ('Olio di semi per friggere',  'ml', 'ambiente', 'Salse e condimenti', false, false, false),
  ('Olio extravergine',          'ml', 'ambiente', 'Salse e condimenti', false, false, false),
  ('Pepe nero del Madagascar',   'g',  'ambiente', 'Dispensa e secchi', false, false, false),
  ('Pepe verde',                 'g',  'ambiente', 'Dispensa e secchi', false, false, false),
  ('Pepe selvatico',             'g',  'ambiente', 'Dispensa e secchi', false, false, false),
  ('Paprika dolce',              'g',  'ambiente', 'Dispensa e secchi', false, false, false),
  ('Sale marino',                'g',  'ambiente', 'Dispensa e secchi', false, false, false),
  ('Zucchero',                   'g',  'ambiente', 'Dispensa e secchi', false, false, false),
  ('Farina per tempura',         'g',  'ambiente', 'Dispensa e secchi', false, false, false),
  ('Lievito naturale',           'g',  'frigo',    'Dispensa e secchi', false, false, false),

  -- ── Dessert e pasticceria ─────────────────────────────────────────────
  ('Cioccolato fondente',        'g',  'ambiente', 'Dessert e pasticceria', false, false, false),
  ('Cioccolato al latte',        'g',  'ambiente', 'Dessert e pasticceria', false, false, false),
  ('Cioccolato bianco',          'g',  'ambiente', 'Dessert e pasticceria', false, false, false),
  ('Mandorle',                   'g',  'ambiente', 'Dessert e pasticceria', false, false, false),
  ('Cereali per crumble',        'g',  'ambiente', 'Dessert e pasticceria', false, false, false),

  -- ── Surgelati ─────────────────────────────────────────────────────────
  ('Edamame',                    'g',  'freezer', 'Surgelati', false, false, false),
  ('Patatine fritte surgelate',  'g',  'freezer', 'Surgelati', false, false, false),

  -- ══════════════════════════════════════════════════════════════════════
  --  SEMILAVORATI — non si comprano, si preparano
  -- ══════════════════════════════════════════════════════════════════════
  --  Ognuno vuole la sua distinta e la sua resa. Finché non ne registri una
  --  lavorazione restano senza costo, e i piatti che li contengono lo
  --  segnalano invece di fingere un food cost più basso del vero.

  ('Riso condito per sushi',       'g',  'frigo', 'Riso e cereali', false, true,  true),
  ('Impasto per pizza',            'g',  'frigo', 'Riso e cereali', false, true,  true),
  ('Bao a vapore',                 'pz', 'frigo', 'Riso e cereali', false, true,  true),
  ('Pastella tempura',             'g',  'frigo', 'Riso e cereali', false, false, true),

  ('Salsa hio',                    'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Salsa hio spicy',              'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Maionese al wasabi',           'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Maionese al gochujang',        'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Maionese agli agrumi',         'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Maionese al parmigiano e tartufo', 'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Teriyaki allo yuzu',           'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Teriyaki al wasabi',           'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Teriyaki al gochujang',        'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Soia dolce allo zenzero',      'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Salsa agropiccante',           'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Salsa di pomodoro hio',        'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Salsa di parmigiano',          'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Salsa miso al pepe verde',     'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Besciamella al cocco',         'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Senape al miele',              'ml', 'frigo', 'Salse e condimenti', false, true, true),
  ('Senape al miele e tartufo',    'ml', 'frigo', 'Salse e condimenti', false, true, true),

  ('Ragout di wagyu',              'g',  'frigo', 'Carne', false, true, true),
  ('Chili di wagyu',               'g',  'frigo', 'Carne', false, true, true),
  ('Cipolla caramellata al peperoncino', 'g', 'frigo', 'Verdura e frutta', false, true, true),
  ('Crema di avocado',             'g',  'frigo', 'Verdura e frutta', false, true, true),

  ('Brodo di crostacei',           'ml', 'frigo', 'Pesce e crostacei', false, true, true),
  ('Brodo di ricciola',            'ml', 'frigo', 'Pesce e crostacei', false, true, true),
  ('Vellutata di nero di seppia',  'ml', 'frigo', 'Pesce e crostacei', false, true, true),

  ('Crema di risotto al limone',   'ml', 'frigo', 'Riso e cereali', false, true, true),
  ('Crema di riso, cocco e tartufo','g', 'frigo', 'Riso e cereali', false, true, true),

  ('Crema pasticcera all''arancia','g',  'frigo', 'Dessert e pasticceria', false, true, true),
  ('Mandorle caramellate',         'g',  'ambiente', 'Dessert e pasticceria', false, false, true),
  ('Crumble di mandorle e cereali','g',  'ambiente', 'Dessert e pasticceria', false, false, true),
  ('Caramello',                    'ml', 'ambiente', 'Dessert e pasticceria', false, false, true),

  -- ══════════════════════════════════════════════════════════════════════
  --  I TAGLI DEL PESCE — nascono dal disassemblaggio, non dagli acquisti
  -- ══════════════════════════════════════════════════════════════════════
  --  Si compra un loin intero, si ottengono tranci con rese e costi diversi.
  --  È il motivo per cui esiste il modulo lavorazioni: senza questi, il
  --  costo di una tagliata sarebbe il prezzo al chilo del pesce intero,
  --  cioè un numero sbagliato in difetto.

  ('Tonno per tagliata',   'g', 'frigo', 'Pesce per crudo', true, true, true),
  ('Tonno per tartare',    'g', 'frigo', 'Pesce per crudo', true, true, true),
  ('Tonno per sashimi',    'g', 'frigo', 'Pesce per crudo', true, true, true),
  ('Salmone per tartare',  'g', 'frigo', 'Pesce per crudo', true, true, true),
  ('Ricciola a tocchetti', 'g', 'frigo', 'Pesce per crudo', true, true, true)

) as x(nome, um, cons, cat, abbattimento, lotti, interno)
on conflict (organizzazione_id, nome) do nothing;


-- ----------------------------------------------------------------------------
--  Riepilogo
-- ----------------------------------------------------------------------------
select
  coalesce(c.nome, 'senza categoria')                        as categoria,
  count(*)                                                   as ingredienti,
  count(*) filter (where i.prodotto_internamente)            as semilavorati,
  count(*) filter (where i.richiede_abbattimento)            as da_abbattere
from magazzino.ingrediente i
left join magazzino.categoria_ingrediente c on c.id = i.categoria_id
where i.organizzazione_id = '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d'
group by c.nome
order by c.nome;
