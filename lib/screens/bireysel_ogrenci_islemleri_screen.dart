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

  Widget _sekmeDugmesi(
    BuildContext context,
    int index,
    String ad,
    IconData icon,
  ) {
    final s = Theme.of(context).colorScheme;
    final secili = _sekme == index;
    final stil = Theme.of(context).textTheme.labelLarge!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      color: secili ? s.onPrimary : s.onSurface,
    );
    return Expanded(
      child: Semantics(
        selected: secili,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('ogrenci-sekmesi-$index'),
            borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => _sekme = index),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: secili
                    ? LinearGradient(
                        colors: [
                          s.primary,
                          Color.lerp(s.primary, Colors.cyan, .25)!,
                        ],
                      )
                    : null,
              ),
              child: LayoutBuilder(
                builder: (c, limits) {
                  final painter = TextPainter(
                    text: TextSpan(text: ad, style: stil),
                    textDirection: Directionality.of(c),
                    textScaler: MediaQuery.textScalerOf(c),
                  )..layout();
                  final ikonSigiyor = painter.width + 25 <= limits.maxWidth;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (ikonSigiyor) ...[
                        Icon(icon, size: 19, color: stil.color),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: OrtakBaslik(
                          ad,
                          style: stil,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _sekmeYuksekligi(BuildContext context) {
    final stil = Theme.of(context).textTheme.labelLarge!.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    final p = TextPainter(
      text: TextSpan(text: 'Form İşlemleri', style: stil),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final ikiSatir = p.width > (MediaQuery.sizeOf(context).width - 24) / 2 - 12;
    return (p.preferredLineHeight * (ikiSatir ? 2 : 1) + 24).clamp(
      44,
      double.infinity,
    );
  }

  @override
  Widget build(BuildContext context) => OrtakTema(
    child: Builder(
      builder: (context) {
        final s = Theme.of(context).colorScheme;
        final metin = Theme.of(context).textTheme;
        return OrtakSayfa(
          appBar: const ModulUstBar(
            title: Text('Öğrenci İşlemleri'),
            baslikOncelikli: true,
          ),
          body: Column(
            children: [
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        s.primaryContainer.withValues(alpha: .45),
                        s.primaryContainer.withValues(alpha: .7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(OrtakUi.radius),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: s.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: s.shadow.withValues(alpha: .08),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.groups_rounded,
                          color: s.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Öğrenci İşlemleri',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: metin.titleLarge?.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Öğrenci kayıt, bilgi, form ve veli işlemleri.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: metin.bodySmall?.copyWith(
                                fontSize: 12,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                key: const ValueKey('ogrenci-sekmeleri'),
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                decoration: BoxDecoration(
                  color: s.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: s.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: s.shadow.withValues(alpha: .08),
                      blurRadius: 3,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: _sekmeYuksekligi(context),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sekmeDugmesi(
                        context,
                        0,
                        'Öğrenciler',
                        Icons.groups_rounded,
                      ),
                      _sekmeDugmesi(
                        context,
                        1,
                        'Form İşlemleri',
                        Icons.assignment_outlined,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _sekme,
                  children: [
                    widget.ogrenciler ??
                        RaporOlusturScreen(
                          sekmeIcinde: true,
                          klavyeAcik:
                              MediaQuery.viewInsetsOf(context).bottom > 0,
                        ),
                    widget.formlar ??
                        const BireyselBilgiToplamaScreen(sekmeIcinde: true),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
