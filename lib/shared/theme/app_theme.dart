import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colori del marchio HIO, ripresi dal gestionale prenotazioni.
///
/// Non e' riuso per pigrizia: quel file porta con se' un lavoro sui contrasti
/// gia' fatto e verificato (vedi `goldDark` e `textMuted` piu' sotto), e
/// personale che passa dalle prenotazioni al magazzino deve avere la
/// sensazione di restare nello stesso posto.
class AppColors {
  static const background = Color(0xFFF5F0E7); // Fondo caldo di pagina
  static const surface = Color(0xFFFFFDF8); // Bianco caldo, schede e barre
  static const card = Color(0xFFFFFDF8);
  static const surfaceElevated = Color(0xFFFFFFFF); // Bianco pieno, in evidenza
  static const cardLight = Color(0xFFEFE8DA); // Tinta sotto le schede

  static const nero = Color(0xFF160E0A);

  static const accent = Color(0xFFB9172A); // Rosso HIO
  static const accentDark = Color(0xFF8E1220);
  static const accentLight = Color(0xFFFBEAE9);

  static const gold = Color(0xFFCAB16F); // Oro HIO
  static const goldLight = Color(0xFFF8F1E1);
  // L'oro HIO su fondo chiaro sta intorno a 2,2:1, sotto il minimo leggibile
  // di 4,5:1. Per i testi piccoli si usa questa versione scura (~5,4:1),
  // lasciando l'oro pieno a bordi, filetti e riempimenti.
  static const goldDark = Color(0xFF8A6D1F);

  static const textPrimary = Color(0xFF18130F);
  static const textSecondary = Color(0xFF655D54);
  static const textMuted = Color(0xFF7C7366);

  static const divider = Color(0xFFD9CCB7);
  static const badgeGreen = Color(0xFF2E7D52);
  static const accentGreen = Color(0xFF2E7D52);
  static const badgeGrey = Color(0xFF6B7280);

  // ── Stati del magazzino ─────────────────────────────────────────────────
  // Sostituiscono gli stati delle prenotazioni. Stessa logica cromatica:
  // oro per "aspetta qualcosa", verde per "a posto", rosso per "guarda qui".
  static const statoBozza = Color(0xFF6B7280); // appena creato
  static const statoRevisione = gold; // letto, da controllare
  static const statoConfermato = Color(0xFF2E7D52); // merce entrata
  static const statoAnnullato = accent;

  static const statoBozzaSfondo = Color(0xFFF0EFEC);
  static const statoRevisioneSfondo = goldLight;
  static const statoConfermatoSfondo = Color(0xFFEAF5EF);
  static const statoAnnullatoSfondo = accentLight;

  // ── Stati di una riga ───────────────────────────────────────────────────
  // Il colore dice quanto lavoro serve: verde niente, oro un tocco,
  // rosso una decisione.
  static const rigaAutomatica = Color(0xFF2E7D52); // riconosciuta da sola
  static const rigaProposta = Color(0xFF8A6D1F); // da confermare
  static const rigaDaRisolvere = Color(0xFFB9172A); // da abbinare a mano

  // ── Scorte ──────────────────────────────────────────────────────────────
  static const sottoScorta = Color(0xFFB9172A);
  static const inScadenza = Color(0xFFB06E00);
}

class AppTheme {
  /// Fraunces per i titoli, Manrope per il testo corrente: la coppia
  /// tipografica del sito hiooriental.com.
  static TextTheme _testo(TextTheme base) {
    final corpo = GoogleFonts.manropeTextTheme(base);
    TextStyle titolo(TextStyle? s) => GoogleFonts.fraunces(
          textStyle: s,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        );
    return corpo.copyWith(
      displayLarge: titolo(base.displayLarge),
      displayMedium: titolo(base.displayMedium),
      displaySmall: titolo(base.displaySmall),
      headlineLarge: titolo(base.headlineLarge),
      headlineMedium: titolo(base.headlineMedium),
      headlineSmall: titolo(base.headlineSmall),
      titleLarge: titolo(base.titleLarge),
    );
  }

  static ThemeData get light => _componi(ThemeData.light());

  static ThemeData _componi(ThemeData base) => ThemeData(
        brightness: Brightness.light,
        textTheme: _testo(base.textTheme),
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(
          primary: AppColors.accent,
          secondary: AppColors.gold,
          surface: AppColors.surface,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          // Gli stili in linea non ereditano dal textTheme: il font va qui.
          titleTextStyle: GoogleFonts.fraunces(
            color: AppColors.accent,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        cardTheme: CardTheme(
          color: AppColors.card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: AppColors.textPrimary,
          iconColor: AppColors.accent,
        ),
        dividerTheme: const DividerThemeData(color: AppColors.divider),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cardLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintStyle: const TextStyle(color: AppColors.textMuted),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
        ),
        dialogTheme: DialogTheme(
          backgroundColor: AppColors.surface,
          titleTextStyle: GoogleFonts.fraunces(
              color: AppColors.accent,
              fontSize: 18,
              fontWeight: FontWeight.w600),
          contentTextStyle: GoogleFonts.manrope(color: AppColors.textPrimary),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surface,
        ),
        useMaterial3: true,
      );
}
