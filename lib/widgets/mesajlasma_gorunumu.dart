import 'ortak_ui.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/mesajlasma.dart';

/// Gönderim anındaki alıcı görüntüsünü kullanır; güncel öğretmen listesini
/// buraya taşımadığı için başka alıcıların adları/dersleri özete karışmaz.
class MesajTakipAliciOzeti extends StatelessWidget {
  const MesajTakipAliciOzeti({super.key, required this.alici, this.sira});
  final MesajAlicisi alici;
  final String? sira;

  @override
  Widget build(BuildContext context) {
    final ogretmenler = alici.baglar
        .where((b) => b['Tur'] == 'Ogretmen')
        .toList();
    final kayitlar = (jsonDecode(alici.ogrenciler) as List)
        .whereType<Map>()
        .toList();
    final eskiOgretmenler = kayitlar
        .where((r) => r['tur'] == 'Ogretmen')
        .toList();
    final ogretmen = ogretmenler.isNotEmpty || eskiOgretmenler.isNotEmpty;
    var ad = alici.ad;
    var ders = kayitlar.map((r) => r['aciklama']).join('\n');
    var kisiSayisi = 1;
    if (ogretmen) {
      final ilk = ogretmenler.firstOrNull;
      final ham = ilk?['AnlikGoruntu'];
      final cozulmus = ham is String ? jsonDecode(ham) : ham;
      final anlik = cozulmus is Map ? cozulmus : null;
      ad = '${anlik?['ad'] ?? alici.ad.split(' / ').first}';
      ders =
          '${anlik?['aciklama'] ?? eskiOgretmenler.firstOrNull?['aciklama'] ?? ''}';
      kisiSayisi =
          (ogretmenler.isNotEmpty
                  ? ogretmenler.map((b) => b['KisiId'])
                  : eskiOgretmenler.map((r) => r['kisiId']))
              .toSet()
              .length;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: ad,
          child: Text(
            '${sira == null ? '' : '$sira • '}$ad',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 6),
        Text('+${alici.telefon}', style: Theme.of(context).textTheme.bodySmall),
        if (ders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Tooltip(
              message: ders,
              child: Text(
                ders,
                maxLines: ogretmen ? 2 : null,
                overflow: ogretmen ? TextOverflow.ellipsis : null,
              ),
            ),
          ),
        if (ogretmen && kisiSayisi > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Aynı numaraya bağlı $kisiSayisi öğretmen var. Onay bu gruba uygulanır.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

const mesajSinifRengi = Color(0xff12a786);
const mesajGrupRengi = Color(0xff9357e9);
const mesajVeliRengi = Color(0xffec4086);
const mesajListeRengi = Color(0xff1675ed);
const mesajSablonRengi = Color(0xffff8a12);

/// Mesajlaşma alanıyla sınırlı görünüm; diğer ekranların temasını değiştirmez.
class MesajlasmaGorunumu extends StatelessWidget {
  const MesajlasmaGorunumu({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => OrtakTema(child: child);
}

class MesajRenkliSimge extends StatelessWidget {
  const MesajRenkliSimge({super.key, required this.icon, required this.renk});
  final IconData icon;
  final Color renk;
  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: renk.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, color: renk, size: 20),
  );
}

class MesajSecimYuzeyi extends StatelessWidget {
  const MesajSecimYuzeyi({
    super.key,
    required this.icon,
    required this.renk,
    required this.child,
  });
  final IconData icon;
  final Color renk;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: renk.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .13 : .045,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: renk.withValues(alpha: .16)),
    ),
    child: Row(
      children: [
        MesajRenkliSimge(icon: icon, renk: renk),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    ),
  );
}

class MesajAdimBasligi extends StatelessWidget {
  const MesajAdimBasligi({
    super.key,
    required this.adim,
    required this.baslik,
    required this.aciklama,
  });
  final int adim;
  final String baslik, aciklama;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            '$adim',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                baslik,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                aciklama,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MesajAciliKarti extends StatelessWidget {
  const MesajAciliKarti({
    super.key,
    required this.renk,
    required this.child,
    this.margin = const EdgeInsets.only(top: 8),
    this.clipBehavior = Clip.antiAlias,
  });
  final Color renk;
  final Widget child;
  final EdgeInsetsGeometry margin;
  final Clip clipBehavior;
  @override
  Widget build(BuildContext context) => Card(
    margin: margin,
    clipBehavior: clipBehavior,
    color: Color.alphaBlend(
      renk.withValues(alpha: .045),
      Theme.of(context).colorScheme.surface,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: renk.withValues(alpha: .17)),
    ),
    child: child,
  );
}

class MesajOnizlemeButonu extends StatelessWidget {
  const MesajOnizlemeButonu({super.key, required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.preview_outlined, size: 20),
        label: const Text('Ön İzle ve Onayla'),
      ),
    ),
  );
}

class MesajGecmisKarti extends StatelessWidget {
  const MesajGecmisKarti({
    super.key,
    required this.tarih,
    required this.kanal,
    required this.child,
    this.durum,
    this.tamMetin,
  });
  final String tarih, kanal;
  final String? durum, tamMetin;
  final Widget child;
  String get tarihYazisi {
    final d = DateTime.tryParse(tarih)?.toLocal();
    if (d == null) return tarih;
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${iki(d.day)}.${iki(d.month)}.${d.year} ${iki(d.hour)}:${iki(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final renkler = Theme.of(context).colorScheme;
    final hata =
        durum?.contains('açılamadı') == true ||
        durum?.contains('belirsiz') == true;
    final renk = hata ? renkler.error : renkler.primary;
    final kart = Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OrtakUi.bosluk,
              0,
              OrtakUi.bosluk,
              OrtakUi.bosluk,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: renkler.primaryContainer,
                    borderRadius: BorderRadius.circular(OrtakUi.radius),
                  ),
                  child: Text(
                    kanal,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: renkler.onPrimaryContainer,
                    ),
                  ),
                ),
                if (durum != null)
                  Text(
                    durum!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: renk),
                  ),
                Text(
                  tarihYazisi,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: renkler.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return tamMetin == null ? kart : Tooltip(message: tamMetin!, child: kart);
  }
}
