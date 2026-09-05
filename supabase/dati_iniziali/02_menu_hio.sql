-- ============================================================================
--  Menu HIO — caricamento iniziale dei prodotti venduti
-- ============================================================================
--
--  Generato dal menu del sito (hio/assets/data/menu-it.json), 225 voci
--  in 28 categorie. Battere a mano duecento piatti e' il modo piu' sicuro
--  per sbagliarne dieci e non accorgersene.
--
--  NON e' una migrazione: sono dati. Si esegue a mano, una volta.
--  Idempotente: ON CONFLICT DO NOTHING, si puo' rieseguire dopo che il
--  menu e' cambiato per aggiungere solo le voci nuove.
--
--  Cosa NON porta con se':
--    - il codice di cassa, che arriva da iPratico e qui non c'e'
--    - le ricette, che si costruiscono una per una
--  3 voci sono senza prezzo (sul sito hanno varianti nella descrizione,
--  tipo le patatine con tre condimenti): vanno completate a mano.
-- ============================================================================

set search_path = magazzino, public;

insert into magazzino.prodotto_venduto
  (organizzazione_id, nome, categoria_menu, prezzo_vendita)
values
  -- Birre /the/ Sake Giapponesi (10)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Awamori Sakimoto Shuzo Yonaguny 125cl', 'Birre /the/ Sake Giapponesi', 24.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Katsunuma Aruga Branca Issehara Koshu 125cl', 'Birre /the/ Sake Giapponesi', 36.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Liquore Nihonsakari Kanjuku Umeshu', 'Birre /the/ Sake Giapponesi', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Liquore Sakari Yuzu', 'Birre /the/ Sake Giapponesi', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Sake Asahara Koi Junmai Ginjo 125cl', 'Birre /the/ Sake Giapponesi', 24.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Sake Sakari Junmai Daiginjo 125cl', 'Birre /the/ Sake Giapponesi', 24.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tè in foglie di sakura', 'Birre /the/ Sake Giapponesi', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tè matha cerimonial Shizu', 'Birre /the/ Sake Giapponesi', 9.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tè verde Hojicha', 'Birre /the/ Sake Giapponesi', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tè verde sencha', 'Birre /the/ Sake Giapponesi', 8.00),

  -- Champagne (8)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Dom Pérignon Brut Rosé Vintage 2009', 'Champagne', 800.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Dom Pérignon Brut Vintage', 'Champagne', 500.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Krug Grande Cuvée 171ème Édition', 'Champagne', 550.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Laurent-Perrier Cuvée Rosé', 'Champagne', 130.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Louis Roederer Cristal Brut', 'Champagne', 650.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ruinart Blanc de Blancs', 'Champagne', 180.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ruinart Rosè', 'Champagne', 200.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ruinart Rosé Brut', 'Champagne', null),

  -- DESSERT (3)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bignè di Crema pasticcera aromatizzata all''arancia, Salsa al Cioccolato Bianco e Croccante di Mandorle caramellate', 'DESSERT', 9.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ice Cream Bao fruit', 'DESSERT', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Sorbetto allo yuzu', 'DESSERT', 9.00),

  -- DOLCI (3)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Dolce Hio', 'DOLCI', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ice Cream Bao', 'DOLCI', 20.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Kumo bao', 'DOLCI', 8.00),

  -- Gin (28)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'AKORI SHERRY GIN', 'Gin', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Adamus Gin', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'BIG GINO EXOTIC', 'Gin', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'BROCKMAN GIN', 'Gin', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'CITADELLE', 'Gin', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Cubical London Dry Gin', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'GIN HENDRICK''S FLORA ADORA', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'GIN HENDRICK''S GRAND CABERNET', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'GIN POLI MARCONI 42', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'GIN PRIMO', 'Gin', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'GIN TANQUERAY TEN', 'Gin', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Garnet Gin', 'Gin', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Gin Hendrick''s', 'Gin', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Gin Mare', 'Gin', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Gin Monkey 47', 'Gin', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'J. ROSE', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'KI. NO. BI Kyoto Dry Gin', 'Gin', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Martin Miller''s Original', 'Gin', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Nikka Coffey Gin', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'PORCELAIN MANDARIN', 'Gin', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'PORCELAIN SHANGHAI DRY GIN', 'Gin', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'PORTOFINO DRY GIN', 'Gin', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'PORTOFINO PENISOLA', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Roby Marton', 'Gin', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Roku Gin', 'Gin', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'SCAPGRACE GIN', 'Gin', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'SIR EDMOND', 'Gin', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Silent Pool', 'Gin', 6.00),

  -- Grandi Rossi (12)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Amarone Classico Riserva ''Costasera'' – Masi 2019', 'Grandi Rossi', 130.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Barbaresco Gaja 2022', 'Grandi Rossi', 450.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Barbaresco ‘Serraboella’ – Paitin 2022', 'Grandi Rossi', 75.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Brunello di Montalcino DOCG 2020 – Ciacci Piccolomini d’Aragona', 'Grandi Rossi', 95.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Campofiorin Masi', 'Grandi Rossi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Clos des Papes – Châteauneuf-du-Pape Rouge', 'Grandi Rossi', 280.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Disiato Toto''Navarra', 'Grandi Rossi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Elena walch Pinot nero', 'Grandi Rossi', 35.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Mille e una Notte – Donnafugata 2021', 'Grandi Rossi', 95.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Morgon “Les Delys” – Daniel Bouland 2023', 'Grandi Rossi', 55.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Pavillon Rouge – Château Margaux 2022', 'Grandi Rossi', 650.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Perricone Brugnano', 'Grandi Rossi', 45.00),

  -- HIO APPETIZER (11)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ebi Fry 6pz', 'HIO APPETIZER', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ebi harumaki 2pz', 'HIO APPETIZER', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Edamame lessi / Spicy', 'HIO APPETIZER', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'French fries', 'HIO APPETIZER', null),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Gambero rosso "Sicilia-Tokio"', 'HIO APPETIZER', 24.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Korokke 2pz', 'HIO APPETIZER', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Lobster - Sando 4pz', 'HIO APPETIZER', 20.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Quesadilla oriental 2pz', 'HIO APPETIZER', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Spring Rolls Hio scampi e yuzu 2pz', 'HIO APPETIZER', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Taco tuna spicy 2pz', 'HIO APPETIZER', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Wagyu - Sando 2 pz', 'HIO APPETIZER', 20.00),

  -- HIO BAO (4)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bao burger spicy 1pz', 'HIO BAO', 9.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bao burger tartufo 1pz', 'HIO BAO', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bao smash pastrami spicy 1pz', 'HIO BAO', 9.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bao super HIO 1pz', 'HIO BAO', 10.00),

  -- HIO ORIENTAL (5)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'GINZA', 'HIO ORIENTAL', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'KISO', 'HIO ORIENTAL', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Mediterranea sour', 'HIO ORIENTAL', 13.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'TOKYO TOWER', 'HIO ORIENTAL', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'YUBI', 'HIO ORIENTAL', 15.00),

  -- HIO PIZZA (2)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Pizza Hio pastrami', 'HIO PIZZA', 20.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Pizza hio jamon pata negra', 'HIO PIZZA', 24.00),

  -- Hio Best Seller (10)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'COSMOPOLITAN', 'Hio Best Seller', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'HIO AVIATION', 'Hio Best Seller', 13.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'HIO MARTINI', 'Hio Best Seller', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'HIO STAR MARTINI', 'Hio Best Seller', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'IL Bomber''''20', 'Hio Best Seller', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'IL Johnsen''''', 'Hio Best Seller', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'MAI TAI', 'Hio Best Seller', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'OLD FASCIONED', 'Hio Best Seller', 13.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'PINA COLADA', 'Hio Best Seller', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'ZACAPA 23 MACCHIATO', 'Hio Best Seller', 14.00),

  -- Hio Mocktail (4)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'KIKU', 'Hio Mocktail', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'MOMO', 'Hio Mocktail', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'SAKURA', 'Hio Mocktail', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'UME', 'Hio Mocktail', 10.00),

  -- Hio twist on classic (4)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'HONO', 'Hio twist on classic', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'MIKAN', 'Hio twist on classic', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'SHINKU', 'Hio twist on classic', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'SHINRIN', 'Hio twist on classic', 15.00),

  -- I Bianchi (24)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Alta Mora Arrigo 2022', 'I Bianchi', 100.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Altamora Etna Bianco', 'I Bianchi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Alteni di Brassica – Gaja', 'I Bianchi', 280.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Chardonnay Hoffstatter', 'I Bianchi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Chiarandà, Chardonnay Donna Fugata', 'I Bianchi', 50.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Damarino Ansonico Donna Fugata', 'I Bianchi', 30.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Donna fugata Passiperduti, Grillo', 'I Bianchi', 33.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Elena walch Chardonnay', 'I Bianchi', 30.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Elena walch Gewurztraminer', 'I Bianchi', 33.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Elena walch Pinot grigio', 'I Bianchi', 30.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Elena walch Sauvignon', 'I Bianchi', 30.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Etna Bianco Doc Contrada Arcuria "Baglio Di Pianeto"', 'I Bianchi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Gaja & Rey', 'I Bianchi', 490.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Gewurstraminer Hofstatter', 'I Bianchi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Grillo Cavallo delle fate', 'I Bianchi', 30.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Grillo Lunario', 'I Bianchi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Grillo di mozia', 'I Bianchi', 45.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Inama Carbonare 2023', 'I Bianchi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Inama Sauvignon', 'I Bianchi', 35.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Inama chardonnay', 'I Bianchi', 30.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Lighea, Zibibbo secco Donna Fugata', 'I Bianchi', 30.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Pietra Nera Marco de Bartoli', 'I Bianchi', 55.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Sauvignon Jerman', 'I Bianchi', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Viafrancia "Baglio Di Pianeto"', 'I Bianchi', 40.00),

  -- PASTA/NOODLES (6)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Calamarata HIO', 'PASTA/NOODLES', 28.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Carbonara di patanegra al tartufo', 'PASTA/NOODLES', 25.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'HIO E IL RAMEN', 'PASTA/NOODLES', 35.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Minestra hamachi', 'PASTA/NOODLES', 22.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Noodles tenerumi e ricci', 'PASTA/NOODLES', 35.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ragout di wagyu', 'PASTA/NOODLES', 26.00),

  -- PER INIZIARE (11)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bao burger 1pz', 'PER INIZIARE', 9.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bao burger wagyu tartufo 1pz', 'PER INIZIARE', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bao lobster 1pz', 'PER INIZIARE', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Edamame lessi con sale marino', 'PER INIZIARE', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Empanada con ragout di wagyu spicy 1pz', 'PER INIZIARE', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Gyoza di wagyu a5 4pz', 'PER INIZIARE', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Mazzancolle giganti 4pz', 'PER INIZIARE', 28.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ostrica Gillardeau n4 e perle di yuzu 1pz', 'PER INIZIARE', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Spring Rolls Hio scampi e caviar 2pz', 'PER INIZIARE', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tartare di Salmone e riso giapponese', 'PER INIZIARE', 16.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tartare di Tonno e riso giapponese', 'PER INIZIARE', 25.00),

  -- RAVIOLI (6)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ebi Gyoza spicy 4pz', 'RAVIOLI', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ebi Gyoza yuzu', 'RAVIOLI', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Wagyu Gyoza 4pz', 'RAVIOLI', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Wagyu Gyoza truffle 4pz', 'RAVIOLI', 16.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Wonton miso 6pz', 'RAVIOLI', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Wonton spicy 6pz', 'RAVIOLI', 16.00),

  -- Rum/Ron/Rhum (11)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Clarin Communail', 'Rum/Ron/Rhum', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'El Dorado 12Y', 'Rum/Ron/Rhum', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Flor de Cana', 'Rum/Ron/Rhum', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Legendario Elisir', 'Rum/Ron/Rhum', 6.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Plantation Barbados 2007', 'Rum/Ron/Rhum', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Plantation Isole Fiji', 'Rum/Ron/Rhum', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Planteray Pineapple', 'Rum/Ron/Rhum', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ron Dictador 12Y', 'Rum/Ron/Rhum', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'The Kraken', 'Rum/Ron/Rhum', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Zacapa 23y', 'Rum/Ron/Rhum', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Zacapa XO', 'Rum/Ron/Rhum', 18.00),

  -- SECONDI (6)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Cotoletta di wagyu', 'SECONDI', 25.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Filetto di wagyu a5 con salsa miso al pepe verde', 'SECONDI', 60.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Pancetta di maialino iberico alla koreana', 'SECONDI', 20.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ribeye di wagyu australiano a5 200gr', 'SECONDI', 50.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Salmone ora king', 'SECONDI', 28.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tagliata di tonno fuentes', 'SECONDI', 25.00),

  -- SUSHI (2)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Sushi sashimi 18 pz', 'SUSHI', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Sushi selection 24pz', 'SUSHI', 50.00),

  -- Selezione Clase Azul (4)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Clase Azul GOLD', 'Selezione Clase Azul', 55.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Clase Azul Mezcal Durango', 'Selezione Clase Azul', 50.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Clase Azul Plata', 'Selezione Clase Azul', 22.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Clase Azul Reposado', 'Selezione Clase Azul', 30.00),

  -- Soft Drink (5)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Acqua Filette 60cl Naturale', 'Soft Drink', 4.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Acqua Filette 60cl frizzante', 'Soft Drink', 4.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Acqua ferrarelle 75cl', 'Soft Drink', 4.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Coca Cola 33cl', 'Soft Drink', 4.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Coca Cola Zero 33cl', 'Soft Drink', 4.00),

  -- Spumanti Italiani (10)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bellavista Cuvee Assemblage 1', 'Spumanti Italiani', 60.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bellavista Cuvee Rosè', 'Spumanti Italiani', 70.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Bellavista Vittorio Moretti 2018', 'Spumanti Italiani', 180.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ca del Bosco Cuveè Prestige', 'Spumanti Italiani', 75.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Cusumano 700', 'Spumanti Italiani', 50.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Cusumano 700 Lost Edition', 'Spumanti Italiani', 65.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Federico II Gran Cuvee', 'Spumanti Italiani', 170.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ferrari Perlé', 'Spumanti Italiani', 95.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ferrari Perlé Rosé', 'Spumanti Italiani', 110.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Giulio Ferrari Riserva del Fondatore', 'Spumanti Italiani', 400.00),

  -- Tequila & Mezcal (12)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'CASAMIGOS ANEJO', 'Tequila & Mezcal', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'CASAMIGOS BLANCO', 'Tequila & Mezcal', 7.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'CASAMIGOS MEZCAL', 'Tequila & Mezcal', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'CASAMIGOS REPOSADO', 'Tequila & Mezcal', 9.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'DOS ARMADILLOS PLATA', 'Tequila & Mezcal', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'DOS ARMADILLOS REPOSADO', 'Tequila & Mezcal', 18.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'MEZCAL APRENDIZ', 'Tequila & Mezcal', 9.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'TEQUILA FORTALEZA', 'Tequila & Mezcal', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tequila Don Julio 1942', 'Tequila & Mezcal', 30.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tequila Don Julio Anejo', 'Tequila & Mezcal', 9.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tequila Don Julio Blanco', 'Tequila & Mezcal', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tequila Don Julio Reposado', 'Tequila & Mezcal', 9.00),

  -- Vini alla mescita (4)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Alta Mora Etna Bianco', 'Vini alla mescita', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Gewürztraminer Hofstatter', 'Vini alla mescita', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Lunario', 'Vini alla mescita', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Pinot Grigio Jerman', 'Vini alla mescita', 8.00),

  -- Vini da meditazione (1)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Passito ben riè donnafugata RISERVA 2017', 'Vini da meditazione', 12.00),

  -- Vodka (8)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Beluga Transatlantic Racing', 'Vodka', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Belvedere Vodka', 'Vodka', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'CIROC', 'Vodka', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Grey Goose ALTIUS', 'Vodka', 16.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Grey Goose Vodka', 'Vodka', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Ketel One Vodka', 'Vodka', 5.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tito''s Vodka', 'Vodka', 8.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Vodka Elite', 'Vodka', 10.00),

  -- Whisky (11)
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Caol Ila 12 yo', 'Whisky', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Glenfiddich 18y', 'Whisky', 14.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'JOHNNIE WALKER Year of the Dragon 2024 "LIMITED EDITION"', 'Whisky', null),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Johnnie Walker Blue Label Elusive Umami Blended Scotch Whisky Limited Release', 'Whisky', 40.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Lagavulin 16y', 'Whisky', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Laphroaig 10y', 'Whisky', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Nikka Coffey Grain', 'Whisky', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Nikka From The Barrel', 'Whisky', 12.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Singleton Glen Ord Aged 15Y', 'Whisky', 15.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Tokinoka Blended Whisky', 'Whisky', 10.00),
  ('7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d', 'Woodford Reserve', 'Whisky', 8.00)
on conflict (organizzazione_id, nome) do nothing;

-- Riepilogo di cio' che e' entrato.
select categoria_menu as categoria, count(*) as prodotti,
       count(prezzo_vendita) as con_prezzo
from magazzino.prodotto_venduto
where organizzazione_id = '7f3a1c2e-9b4d-4e5a-8c6f-1d2e3a4b5c6d'
group by categoria_menu order by categoria_menu;
