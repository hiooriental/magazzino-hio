import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/db.dart';
import '../theme/app_theme.dart';
import 'logo_hio.dart';

/// Il menu laterale.
///
/// Le voci sono in ordine di quanto spesso si usano, non di importanza
/// concettuale: il cruscotto e i documenti si aprono ogni giorno, le ricette
/// una volta al mese.
class AppDrawer extends StatelessWidget {
  final String attiva;
  const AppDrawer({super.key, required this.attiva});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: LogoHio(larghezza: 170),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _Voce(
                    icona: Icons.speed_outlined,
                    testo: 'Cruscotto',
                    rotta: '/',
                    attiva: attiva,
                  ),
                  _Voce(
                    icona: Icons.receipt_long_outlined,
                    testo: 'Documenti',
                    rotta: '/documenti',
                    attiva: attiva,
                  ),
                  _Voce(
                    icona: Icons.inventory_2_outlined,
                    testo: 'Scorte',
                    rotta: '/scorte',
                    attiva: attiva,
                  ),
                  _Voce(
                    icona: Icons.content_cut,
                    testo: 'Lavorazioni',
                    rotta: '/lavorazioni',
                    attiva: attiva,
                  ),
                  _Voce(
                    icona: Icons.eco_outlined,
                    testo: 'Ingredienti',
                    rotta: '/ingredienti',
                    attiva: attiva,
                  ),
                  _Voce(
                    icona: Icons.menu_book_outlined,
                    testo: 'Ricette',
                    rotta: '/ricette',
                    attiva: attiva,
                  ),
                  _Voce(
                    icona: Icons.euro_outlined,
                    testo: 'Food cost',
                    rotta: '/food-cost',
                    attiva: attiva,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.textSecondary),
              title: const Text('Esci'),
              onTap: () => Db.client.auth.signOut(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Voce extends StatelessWidget {
  final IconData icona;
  final String testo;
  final String rotta;
  final String attiva;

  const _Voce({
    required this.icona,
    required this.testo,
    required this.rotta,
    required this.attiva,
  });

  @override
  Widget build(BuildContext context) {
    final selezionata = attiva == rotta;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selezionata,
        selectedTileColor: AppColors.accentLight,
        leading: Icon(icona,
            color: selezionata ? AppColors.accent : AppColors.textSecondary),
        title: Text(
          testo,
          style: TextStyle(
            color: selezionata ? AppColors.accent : AppColors.textPrimary,
            fontWeight: selezionata ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onTap: () {
          Navigator.of(context).pop();
          if (!selezionata) context.go(rotta);
        },
      ),
    );
  }
}
