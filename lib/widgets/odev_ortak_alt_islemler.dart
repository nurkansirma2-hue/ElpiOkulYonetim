import 'package:flutter/material.dart';

/// Tüm ödev değerlendirme ekranlarında sabit kalan üç temel işlem.
class OdevOrtakAltIslemler extends StatelessWidget {
  const OdevOrtakAltIslemler({
    super.key,
    this.ogrenciEkle,
    this.ogrenciCikar,
    this.kaydet,
    this.sadeceKaydet = false,
  });

  final VoidCallback? ogrenciEkle;
  final VoidCallback? ogrenciCikar;
  final VoidCallback? kaydet;
  final bool sadeceKaydet;

  Widget _dugme(
    BuildContext context,
    String ad,
    IconData ikon,
    VoidCallback? islem, {
    bool kayit = false,
  }) {
    final renk = Theme.of(context).colorScheme;
    final mavi = renk.brightness == Brightness.dark
        ? Colors.blue.shade200
        : Colors.blue.shade700;
    return Expanded(
      flex: kayit ? 3 : 4,
      child: Tooltip(
        message: ad,
        child: OutlinedButton(
          onPressed: islem,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: kayit ? Colors.white : mavi,
            backgroundColor: kayit ? Colors.green.shade700 : renk.surface,
            disabledBackgroundColor: kayit ? Colors.green.shade100 : null,
            disabledForegroundColor: kayit ? Colors.green.shade800 : null,
            side: BorderSide(
              color: kayit ? Colors.green.shade700 : renk.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(ikon, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  ad,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => sadeceKaydet ? SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: FilledButton.icon(
        onPressed: kaydet,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.save_outlined),
        label: const Text('Kaydet'),
      ),
    ),
  ) : SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SizedBox(
        height: 48,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dugme(
              context,
              'Öğrenci Ekle',
              Icons.person_add_alt_1_outlined,
              ogrenciEkle,
            ),
            const SizedBox(width: 5),
            _dugme(
              context,
              'Öğrenci Çıkar',
              Icons.person_remove_outlined,
              ogrenciCikar,
            ),
            const SizedBox(width: 5),
            _dugme(context, 'Kaydet', Icons.save_outlined, kaydet, kayit: true),
          ],
        ),
      ),
    ),
  );
}
