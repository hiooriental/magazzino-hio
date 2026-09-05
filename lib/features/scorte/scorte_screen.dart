import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sessione.dart';
import '../../data/magazzino_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/contenuto_centrato.dart';

enum _Vista { daOrdinare, tutte, scadenze, abbattimento }

final scorteProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, soloUrgenti) async {
  await ref.watch(sessioneProvider.future);
  return repo.statoScorte(
      stati: soloUrgenti ? const ['esaurito', 'critico', 'basso'] : null);
});

final scadenzeProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(sessioneProvider.future);
  return repo.scadenze();
});

final abbattimentoProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(sessioneProvider.future);
  return repo.daAbbattere();
});

/// Scorte: quanto c'è, quanto dura, cosa ordinare.
///
/// La colonna che conta non è la giacenza ma i GIORNI DI COPERTURA. Due chili
/// di riso sono una settimana, due chili di salmone sono un servizio: senza
/// il consumo alla mano, un numero in chili non dice se c'è un problema.
class ScorteScreen extends ConsumerStatefulWidget {
  const ScorteScreen({super.key});

  @override
  ConsumerState<ScorteScreen> createState() => _ScorteScreenState();
}

class _ScorteScreenState extends ConsumerState<ScorteScreen> {
  _Vista _vista = _Vista.daOrdinare;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(attiva: '/scorte'),
      appBar: AppBar(
        title: const Text('Scorte'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(scorteProvider);
              ref.invalidate(scadenzeProvider);
              ref.invalidate(abbattimentoProvider);
            },
          ),
        ],
      ),
      body: ContenutoCentrato(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<_Vista>(
                  segments: const [
                    ButtonSegment(
                        value: _Vista.daOrdinare, label: Text('Da ordinare')),
                    ButtonSegment(value: _Vista.tutte, label: Text('Tutte')),
                    ButtonSegment(
                        value: _Vista.scadenze, label: Text('Scadenze')),
                    ButtonSegment(
                        value: _Vista.abbattimento,
                        label: Text('Abbattimento')),
                  ],
                  selected: {_vista},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _vista = s.first),
                ),
              ),
            ),
            Expanded(child: _corpo()),
          ],
        ),
      ),
    );
  }

  Widget _corpo() => switch (_vista) {
        _Vista.scadenze => _Elenco(
            provider: scadenzeProvider,
            vuoto: 'Nessun lotto in scadenza nei prossimi sette giorni.',
            costruisci: (r) => _RigaScadenza(r),
          ),
        _Vista.abbattimento => _Elenco(
            provider: abbattimentoProvider,
            vuoto: 'Nessun pesce in attesa di abbattimento.',
            costruisci: (r) => _RigaAbbattimento(r),
          ),
        _ => _Elenco(
            provider: scorteProvider(_vista == _Vista.daOrdinare),
            vuoto: _vista == _Vista.daOrdinare
                ? 'Nessun ingrediente sotto soglia. Non c\'è niente da ordinare.'
                : 'Nessun ingrediente in anagrafica.',
            costruisci: (r) => _RigaScorta(r),
          ),
      };
}

class _Elenco extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<Map<String, dynamic>>>> provider;
  final String vuoto;
  final Widget Function(Map<String, dynamic>) costruisci;

  const _Elenco({
    required this.provider,
    required this.vuoto,
    required this.costruisci,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(provider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('$e', textAlign: TextAlign.center),
            ),
          ),
          data: (righe) {
            if (righe.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    vuoto,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: righe.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => costruisci(righe[i]),
            );
          },
        );
  }
}

const _coloriStato = {
  'esaurito': AppColors.accent,
  'critico': AppColors.sottoScorta,
  'basso': AppColors.inScadenza,
  'ok': AppColors.statoConfermato,
};

class _RigaScorta extends StatelessWidget {
  final Map<String, dynamic> r;
  const _RigaScorta(this.r);

  @override
  Widget build(BuildContext context) {
    final stato = r['stato'] as String? ?? 'ok';
    final colore = _coloriStato[stato] ?? AppColors.badgeGrey;
    final um = r['um_base'] as String? ?? '';
    final giorni = r['giorni_copertura'] as num?;
    final daOrdinare = r['da_ordinare'] as num?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 38,
              margin: const EdgeInsets.only(right: 12, top: 2),
              decoration: BoxDecoration(
                  color: colore, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r['ingrediente'] as String? ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      'in casa ${quantitaLeggibile(r['giacenza'] as num?, um)}',
                      if (r['categoria'] != null) r['categoria'] as String,
                    ].join(' · '),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  if (daOrdinare != null && daOrdinare > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'da ordinare: ${quantitaLeggibile(daOrdinare, um)}',
                      style: TextStyle(color: colore, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Il numero che decide. Senza consumo storico non si può
                // calcolare, e allora è più onesto non mostrarlo che
                // mostrarne uno finto.
                if (giorni != null) ...[
                  Text(numeroIt(giorni),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colore)),
                  const Text('giorni',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ] else
                  Text(
                    stato == 'esaurito' ? 'esaurito' : 'consumo\nsconosciuto',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11.5, color: colore),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RigaScadenza extends StatelessWidget {
  final Map<String, dynamic> r;
  const _RigaScadenza(this.r);

  @override
  Widget build(BuildContext context) {
    final stato = r['stato'] as String? ?? '';
    final colore = stato == 'scaduto' ? AppColors.accent : AppColors.inScadenza;
    final giorni = (r['giorni'] as num?)?.toInt() ?? 0;

    return Card(
      child: ListTile(
        leading: Icon(
            stato == 'scaduto' ? Icons.dangerous_outlined : Icons.schedule,
            color: colore),
        title: Text(r['ingrediente'] as String? ?? ''),
        subtitle: Text(
          'lotto ${r['codice']} · '
          '${quantitaLeggibile(r['quantita'] as num?, r['um_base'] as String? ?? '')}',
          style: const TextStyle(fontSize: 12.5),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              giorni < 0
                  ? 'scaduto da ${-giorni} g'
                  : giorni == 0
                      ? 'scade oggi'
                      : 'fra $giorni g',
              style: TextStyle(color: colore, fontWeight: FontWeight.w600),
            ),
            Text(dataIt(DateTime.tryParse(r['data_scadenza'] as String? ?? '')),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _RigaAbbattimento extends ConsumerWidget {
  final Map<String, dynamic> r;
  const _RigaAbbattimento(this.r);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final giorni = (r['giorni_in_casa'] as num?)?.toInt() ?? 0;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.ac_unit, color: AppColors.accent),
        title: Text(r['ingrediente'] as String? ?? ''),
        subtitle: Text(
          'lotto ${r['codice']} · '
          '${quantitaLeggibile(r['quantita'] as num?, r['um_base'] as String? ?? '')} · '
          'in casa da $giorni ${giorni == 1 ? 'giorno' : 'giorni'}',
          style: const TextStyle(fontSize: 12.5),
        ),
        // Non è un promemoria di comodo: è l'obbligo del Reg. CE 853/2004
        // sul pesce destinato al consumo crudo.
        trailing: TextButton(
          onPressed: () => _registra(context, ref),
          child: const Text('Registra'),
        ),
      ),
    );
  }

  Future<void> _registra(BuildContext context, WidgetRef ref) async {
    // I due soli trattamenti ammessi dalla norma. Offrirli come pulsanti
    // invece che come campi liberi evita di registrare come conforme un
    // trattamento che non lo è.
    final scelta = await showDialog<(num, int)>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Abbattimento di ${r['ingrediente']}'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Reg. CE 853/2004: sono ammessi solo questi due trattamenti.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, (-20, 24)),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('−20 °C per 24 ore'),
              subtitle: Text('Abbattitore o congelatore domestico adeguato'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, (-35, 15)),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('−35 °C per 15 ore'),
              subtitle: Text('Abbattitore rapido'),
            ),
          ),
        ],
      ),
    );
    if (scelta == null) return;

    final (temperatura, ore) = scelta;
    final fine = DateTime.now();
    final inizio = fine.subtract(Duration(hours: ore));

    try {
      await repo.registraAbbattimento(
        lottoId: r['lotto_id'] as String,
        inizio: inizio,
        fine: fine,
        temperatura: temperatura,
      );
      ref.invalidate(abbattimentoProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.accentGreen,
          content: Text('Abbattimento registrato: '
              '${numeroIt(temperatura)} °C per $ore ore.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: AppColors.accent));
      }
    }
  }
}
