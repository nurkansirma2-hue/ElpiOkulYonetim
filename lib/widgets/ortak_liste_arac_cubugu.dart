import 'package:flutter/material.dart';

/// Arama ve filtre verileri ekranın sorumluluğundadır. Bu çubuk yalnızca
/// ortak görünümü ve işlemleri sağlar; veri okumaz veya değiştirmez.
class OrtakListeAracCubugu<T> extends StatelessWidget {
  const OrtakListeAracCubugu({
    super.key,
    required this.ara,
    required this.filtrele,
    required this.siralama,
    required this.siralamaSecenekleri,
    required this.sirala,
    this.aramaAktif = false,
    this.filtreAktif = false,
    this.etkin = true,
    this.ekIslemler = const [],
  });

  final VoidCallback ara, filtrele;
  final T siralama;
  final Map<T, String> siralamaSecenekleri;
  final ValueChanged<T> sirala;
  final bool aramaAktif, filtreAktif, etkin;
  final List<Widget> ekIslemler;

  @override
  Widget build(BuildContext context) {
    final renk = Theme.of(context).colorScheme.primary;
    Widget icerik(IconData ikon, String ad, bool secili) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 21),
          const SizedBox(height: 4),
          Text(
            ad,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: secili ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
    Widget dugme(String ad, IconData ikon, VoidCallback islem, bool secili) =>
        Expanded(
          child: Tooltip(
            message: ad,
            child: TextButton(
              onPressed: etkin ? islem : null,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: secili
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              child: icerik(ikon, ad, secili),
            ),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            dugme('Ara', Icons.search, ara, aramaAktif),
            dugme('Filtrele', Icons.filter_alt_outlined, filtrele, filtreAktif),
            Expanded(
              child: PopupMenuButton<T>(
                tooltip: 'Sırala',
                enabled: etkin,
                initialValue: siralama,
                onSelected: sirala,
                itemBuilder: (_) => [
                  for (final e in siralamaSecenekleri.entries)
                    CheckedPopupMenuItem<T>(
                      value: e.key,
                      checked: e.key == siralama,
                      child: Text(e.value),
                    ),
                ],
                child: IconTheme(
                  data: IconThemeData(
                    color: etkin ? renk : Theme.of(context).disabledColor,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: etkin ? renk : Theme.of(context).disabledColor,
                    ),
                    child: icerik(Icons.swap_vert, 'Sırala', false),
                  ),
                ),
              ),
            ),
            for (final islem in ekIslemler) Expanded(child: islem),
          ],
        ),
      ),
    );
  }
}

/// Türkçe büyük/küçük harfler ve aksansız klavye ile aramayı eşleştirir.
String listeAramaMetni(String metin) {
  var sonuc = metin.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
  for (final e in const {
    'ç': 'c',
    'ğ': 'g',
    'ı': 'i',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
  }.entries) {
    sonuc = sonuc.replaceAll(e.key, e.value);
  }
  return sonuc.trim();
}

int listeTurkceKarsilastir(String a, String b) {
  const alfabe = 'abcçdefgğhıijklmnoöprsştuüvyz';
  String anahtar(String s) => s
      .replaceAll('I', 'ı')
      .replaceAll('İ', 'i')
      .toLowerCase()
      .split('')
      .map((c) {
        final i = alfabe.indexOf(c);
        return i < 0 ? c : String.fromCharCode(0x100 + i);
      })
      .join();
  return anahtar(a).compareTo(anahtar(b));
}
