import 'package:flutter/material.dart';

class OdevMenuIslemi {
  const OdevMenuIslemi(
    this.deger,
    this.baslik,
    this.ikon, {
    this.ayrac = false,
    this.arsiv = false,
    this.basarili = false,
    this.enabled = true,
    this.altIslemler = const [],
  });
  final String deger, baslik;
  final IconData ikon;
  final bool ayrac, arsiv, basarili, enabled;
  final List<OdevMenuIslemi> altIslemler;
}

class OdevIslemMenusu extends StatelessWidget {
  const OdevIslemMenusu({
    super.key,
    required this.islemler,
    required this.onSelected,
    this.enabled = true,
  });
  final List<OdevMenuIslemi> islemler;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Diğer işlemler',
    icon: const Icon(Icons.more_vert),
    onPressed: !enabled
        ? null
        : () async {
            final sonuc = await showGeneralDialog<String>(
              context: context,
              barrierDismissible: true,
              barrierLabel: MaterialLocalizations.of(
                context,
              ).modalBarrierDismissLabel,
              barrierColor: Colors.black26,
              transitionDuration: const Duration(milliseconds: 180),
              transitionBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              pageBuilder: (ctx, _, __) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 60, 12, 76),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Material(
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? Theme.of(ctx).colorScheme.surface
                            : Colors.white,
                        elevation: 12,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                                child: Text(
                                  'Ödev işlemleri',
                                  style: Theme.of(ctx).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          ctx,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                              for (final i in islemler) ...[
                                if (i.ayrac) const Divider(height: 16),
                                _OdevMenuSatiri(islem: i),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            if (sonuc != null && context.mounted) onSelected(sonuc);
          },
  );
}

class _OdevMenuSatiri extends StatefulWidget {
  const _OdevMenuSatiri({required this.islem});
  final OdevMenuIslemi islem;
  @override
  State<_OdevMenuSatiri> createState() => _OdevMenuSatiriState();
}

class _OdevMenuSatiriState extends State<_OdevMenuSatiri> {
  bool acik = false;
  @override
  Widget build(BuildContext context) {
    final i = widget.islem, renk = Theme.of(context).colorScheme;
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final vurgu = i.arsiv
        ? (koyu ? Colors.amber.shade200 : Colors.brown.shade700)
        : i.basarili
        ? (koyu ? Colors.green.shade200 : Colors.green.shade700)
        : i.ikon == Icons.person_remove_outlined
        ? (koyu ? Colors.orange.shade200 : Colors.deepOrange.shade700)
        : renk.primary;
    final zemin = (i.arsiv ? Colors.amber : vurgu).withValues(
      alpha: koyu ? .20 : .10,
    );
    final grup = i.altIslemler.isNotEmpty;
    return Material(
      color: i.arsiv || grup && acik ? zemin : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            enabled: i.enabled,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 2,
            ),
            minLeadingWidth: 32,
            horizontalTitleGap: 12,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: zemin,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                i.ikon,
                size: 22,
                color: i.enabled
                    ? vurgu
                    : renk.onSurface.withValues(alpha: .38),
              ),
            ),
            title: Text(
              i.baslik,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: i.arsiv ? const Text('Kayıtlar korunur') : null,
            trailing: grup
                ? Icon(acik ? Icons.expand_less : Icons.expand_more)
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onTap: !i.enabled
                ? null
                : () {
                    if (grup) {
                      setState(() => acik = !acik);
                    } else {
                      Navigator.pop(context, i.deger);
                    }
                  },
          ),
          if (grup && acik)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final alt in i.altIslemler) _OdevMenuSatiri(islem: alt),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
