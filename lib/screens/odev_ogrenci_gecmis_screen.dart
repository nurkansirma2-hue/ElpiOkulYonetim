import '../widgets/ortak_ui.dart';
import 'package:flutter/material.dart';
import '../models/odev_kontrol.dart';
import '../widgets/odev_gorunum.dart';
import '../services/bireysel_liste_service.dart';
import '../services/bireysel_odev_kontrol_service.dart';

class OdevOgrenciGecmisScreen extends StatefulWidget {
  const OdevOgrenciGecmisScreen({
    super.key,
    required this.oturum,
    required this.ogrenciId,
  });
  final BireyselListeOturumu oturum;
  final int ogrenciId;
  @override
  State<OdevOgrenciGecmisScreen> createState() => _GecmisState();
}

class _GecmisState extends State<OdevOgrenciGecmisScreen> {
  late final _future = BireyselOdevKontrolService.ogrenciGecmisi(
    widget.oturum,
    widget.ogrenciId,
  );
  Widget _satir(Map<String, Object?> r) {
    final sonuc = r['OdevKontrolSonucId'] == null
        ? null
        : OdevKontrolSonuc.fromMap(r);
    final durum = sonuc?.durum ?? OdevKontrolDurumu.kontrolEdilmedi;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: odevDurumZemini(durum),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(Icons.description_outlined, color: odevDurumRengi(durum)),
        ),
        title: Text(
          '${r['Baslik']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Kontrol tarihi: ${r['KontrolTarihi'] ?? '—'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          decoration: BoxDecoration(
            color: odevDurumZemini(durum),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            durum.bekliyor
                ? '—'
                : sonuc?.puan == null
                    ? durum.sembol
                    : '${durum.sembol} • ${sonuc!.puan!.toStringAsFixed(sonuc.puan! % 1 == 0 ? 0 : 1)}/10',
            style: TextStyle(
              color: odevDurumRengi(durum),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OdevTema(
    child: OrtakSayfa(
      appBar: const OdevBaslik(title: Text('Öğrenci Ödev Geçmişi')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _future,
        builder: (c, s) {
          if (s.hasError) {
            return Center(
              child: Text('Geçmiş okunamadı. Orijinal hata: ${s.error}'),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = s.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('Bu yıl için ödev kaydı yok.'));
          }
          return ListView(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: odevBaslikMavi, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${rows.first['Ad']} ${rows.first['Soyad']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${rows.first['SinifKodu']} • ${rows.first['OkulNo']}',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'Öğrenci Ödev Geçmişi',
                  style: TextStyle(
                    color: odevMavi,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final r in rows) _satir(r),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    ),
  );
}
