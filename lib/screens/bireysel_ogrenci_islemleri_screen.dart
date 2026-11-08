import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import 'rapor_olustur_screen.dart';
import 'bireysel_bilgi_toplama_screen.dart';

/// Öğrenci listesi ve bilgi formlarına tek ekrandan erişim.
class BireyselOgrenciIslemleriScreen extends StatefulWidget {
  const BireyselOgrenciIslemleriScreen({
    super.key,
    this.ogrenciler,
    this.formlar,
  });

  final Widget? ogrenciler, formlar;

  @override
  State<BireyselOgrenciIslemleriScreen> createState() =>
      _BireyselOgrenciIslemleriScreenState();
}

class _BireyselOgrenciIslemleriScreenState
    extends State<BireyselOgrenciIslemleriScreen> {
  int _sekme = 0;

  @override
  Widget build(BuildContext context) {
    final renkler = Theme.of(context).colorScheme;
    final metinler = Theme.of(context).textTheme;
    return OrtakSayfa(
    appBar: const ModulUstBar(title: Text('Öğrenci İşlemleri')),
    body: Column(children: [
      Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.all(OrtakUi.bosluk),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [renkler.primaryContainer, renkler.primaryContainer.withValues(alpha: .7)],
            begin: Alignment.centerLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(OrtakUi.radius),
        ),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: renkler.surface,
            child: Icon(Icons.groups_outlined, color: renkler.primary),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Öğrenci İşlemleri', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: metinler.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text('Öğrencileri yönetin, formlarla bilgi toplayın.',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: metinler.bodySmall),
            ],
          )),
        ]),
      ),
      Material(
        color: renkler.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(backgroundColor: renkler.surface,
                foregroundColor: renkler.onSurface,
                selectedBackgroundColor: renkler.primary,
                selectedForegroundColor: renkler.onPrimary,
                side: BorderSide(color: renkler.outlineVariant)),
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.groups_outlined),
                  label: Text('Öğrencilerim'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.assignment_outlined),
                  label: Text('Formlar'),
                ),
              ],
              selected: {_sekme},
              onSelectionChanged: (secim) =>
                  setState(() => _sekme = secim.first),
            ),
          ),
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: _sekme,
          children: [
            widget.ogrenciler ?? const RaporOlusturScreen(sekmeIcinde: true),
            widget.formlar ?? const BireyselBilgiToplamaScreen(sekmeIcinde: true),
          ],
        ),
      ),
    ],
    ),
  );
  }
}
