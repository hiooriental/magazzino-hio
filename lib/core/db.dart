import 'package:supabase_flutter/supabase_flutter.dart';

/// Punto unico di accesso al database.
///
/// Le tabelle del magazzino NON stanno in `public` ma nello schema
/// `magazzino`: ogni query deve passare da qui, altrimenti PostgREST cerca in
/// `public` e risponde che la tabella non esiste. Lo schema dev'essere anche
/// negli "Exposed schemas" del progetto Supabase.
class Db {
  const Db._();

  static SupabaseClient get client => Supabase.instance.client;

  /// `Db.mag.from('ingrediente')` invece di
  /// `Supabase.instance.client.schema('magazzino').from('ingrediente')`.
  static SupabaseQuerySchema get mag => client.schema('magazzino');

  static User? get utente => client.auth.currentUser;
  static bool get autenticato => utente != null;
}
