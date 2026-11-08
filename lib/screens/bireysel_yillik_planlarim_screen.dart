import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';

import 'bireysel_yillik_plan_import_screen.dart';
import 'bireysel_gunluk_plan_screen.dart';
import 'bireysel_dbf_import_screen.dart';
import '../database/local_database.dart';
import '../services/bireysel_profil_service.dart';
import '../services/bireysel_yillik_plan_service.dart';

Future<void> bireyselHaftalikKazanimAc(
  BuildContext context, {
  required int ogretmenProfilId,
  required String egitimOgretimYili,
  required int dersId,
  required String dersAdi,
  required int sinifSeviyesi,
  DateTime? tarih,
  String? sinif,
  String? takvimUyarisi,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => InheritedTheme.captureAll(
        context,
        _YillikPlanDetayScreen(
          ogretmenProfilId: ogretmenProfilId,
          egitimOgretimYili: egitimOgretimYili,
          dersId: dersId,
          dersAdi: dersAdi,
          sinifSeviyesi: sinifSeviyesi,
          tarih: tarih ?? DateTime.now(),
          sinif: sinif ?? '',
          takvimUyarisi: takvimUyarisi ?? '',
        ),
      ),
    ),
  );
}

class BireyselYillikPlanlarimScreen extends StatefulWidget {
  const BireyselYillikPlanlarimScreen({super.key});

  @override
  State<BireyselYillikPlanlarimScreen> createState() =>
      _BireyselYillikPlanlarimScreenState();
}

class _YillikPlanDurumu {
  const _YillikPlanDurumu({
    required this.dersId,
    required this.dersAdi,
    required this.sinifSeviyesi,
    required this.yillikPlanId,
    required this.aciklama,
    required this.detaySayisi,
  });

  final int dersId;
  final String dersAdi;
  final int sinifSeviyesi;
  final int? yillikPlanId;
  final String aciklama;
  final int detaySayisi;

  bool get planYuklu => yillikPlanId != null && yillikPlanId! > 0;
}

class _BireyselYillikPlanlarimScreenState
    extends State<BireyselYillikPlanlarimScreen> {
  Map<String, dynamic>? _profil;
  List<_YillikPlanDurumu> _planDurumlari = const <_YillikPlanDurumu>[];
  bool _yukleniyor = true;
  String? _hataMesaji;

  @override
  void initState() {
    super.initState();
    _sayfayiYukle();
  }

  Future<void> _sayfayiYukle() async {
    if (mounted) {
      setState(() {
        _yukleniyor = true;
        _hataMesaji = null;
      });
    }

    try {
      final profil = await BireyselProfilService.getir();

      if (profil == null) {
        throw Exception(
          'Bireysel öğretmen profili bulunamadı. '
          'Önce öğretmen bilgilerini tamamlayın.',
        );
      }

      final profilId = profil['OgretmenProfilId'] as int?;
      final yil = (profil['EgitimOgretimYili'] ?? '').toString().trim();

      if (profilId == null || profilId <= 0) {
        throw Exception('Geçerli öğretmen profil kimliği bulunamadı.');
      }

      if (yil.isEmpty) {
        throw Exception('Eğitim öğretim yılı bilgisi boş.');
      }

      final durumlar = await _planDurumlariniGetir(
        ogretmenProfilId: profilId,
        egitimOgretimYili: yil,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _profil = profil;
        _planDurumlari = durumlar;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _hataMesaji =
            'Yıllık planlarınız yüklenirken hata oluştu.\n'
            'Orijinal hata: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _yukleniyor = false;
        });
      }
    }
  }

  Future<List<_YillikPlanDurumu>> _planDurumlariniGetir({
    required int ogretmenProfilId,
    required String egitimOgretimYili,
  }) async {
    try {
      final db = await LocalDatabase.instance.database;

      final sonuc = await db.rawQuery(
        '''
        WITH Derslerim AS (
          SELECT DISTINCT
            d.DersId,
            d.DersAdi,
            s.SinifSeviyesi
          FROM GecerliDersProgrami dp
          INNER JOIN Ders d
            ON d.DersId = dp.DersId
          INNER JOIN SinifSube s
            ON s.SinifSubeId = dp.SinifSubeId
          WHERE dp.OgretmenProfilId = ?
            AND dp.EgitimOgretimYili = ?
            AND dp.Aktif = 1
            AND d.Aktif = 1
            AND s.Aktif = 1
            AND s.SinifSeviyesi IS NOT NULL
        )
        SELECT
          dm.DersId,
          dm.DersAdi,
          dm.SinifSeviyesi,
          yp.YillikPlanId,
          yp.Aciklama,
          COALESCE(
            (
              SELECT COUNT(*)
              FROM YillikPlanDetay ypd
              WHERE ypd.YillikPlanId = yp.YillikPlanId
                AND ypd.Aktif = 1
            ),
            0
          ) AS DetaySayisi
        FROM Derslerim dm
        LEFT JOIN YillikPlan yp
          ON yp.YillikPlanId = (
            SELECT MAX(yp2.YillikPlanId)
            FROM YillikPlan yp2
            WHERE yp2.DersId = dm.DersId
              AND yp2.SinifSeviyesi = dm.SinifSeviyesi
              AND yp2.OgretmenProfilId = ?
              AND yp2.EgitimOgretimYili IN (?, ?)
              AND yp2.Aktif = 1
          )
        ORDER BY dm.SinifSeviyesi, dm.DersAdi
        ''',
        [
          ogretmenProfilId,
          egitimOgretimYili,
          ogretmenProfilId,
          egitimOgretimYili,
          BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
            egitimOgretimYili,
          ),
        ],
      );

      return sonuc
          .map(
            (satir) => _YillikPlanDurumu(
              dersId: (satir['DersId'] as int?) ?? 0,
              dersAdi: (satir['DersAdi'] ?? '').toString().trim(),
              sinifSeviyesi: (satir['SinifSeviyesi'] as int?) ?? 0,
              yillikPlanId: satir['YillikPlanId'] as int?,
              aciklama: (satir['Aciklama'] ?? '').toString().trim(),
              detaySayisi: (satir['DetaySayisi'] as int?) ?? 0,
            ),
          )
          .where(
            (e) =>
                e.dersId > 0 &&
                e.dersAdi.isNotEmpty &&
                e.sinifSeviyesi > 0,
          )
          .toList(growable: false);
    } catch (e) {
      throw Exception(
        'Derslere ait yıllık plan durumları SQLite veritabanından '
        'okunurken hata oluştu.\n'
        'Orijinal hata: $e',
      );
    }
  }

  Future<void> _yillikPlanImportAc({_YillikPlanDurumu? durum}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BireyselYillikPlanImportScreen(
          baslangicDersId: durum?.dersId,
          baslangicSinifSeviyesi: durum?.sinifSeviyesi,
        ),
      ),
    );

    if (mounted) {
      await _sayfayiYukle();
    }
  }

  Future<void> _dbfImportAc(_YillikPlanDurumu durum) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => InheritedTheme.captureAll(context, BireyselDbfImportScreen(
        profilId: _profil!['OgretmenProfilId'] as int,
        egitimYili: _profil!['EgitimOgretimYili'].toString(),
        dersId: durum.dersId, dersAdi: durum.dersAdi,
        sinifSeviyesi: durum.sinifSeviyesi,
      )),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final yil = (_profil?['EgitimOgretimYili'] ?? '').toString().trim();

    return OrtakSayfa(
      appBar: ModulUstBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yıllık Planlarım'),
            if (yil.isNotEmpty)
              Text(
                '$yil Eğitim Öğretim Yılı',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _yukleniyor ? null : _sayfayiYukle,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _icerik(),
    );
  }

  Widget _icerik() {
    if (_yukleniyor) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_hataMesaji != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 58,
                color: Colors.red,
              ),
              const SizedBox(height: 14),
              Text(
                _hataMesaji!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _sayfayiYukle,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    if (_planDurumlari.isEmpty) {
      return _bosDersListesi();
    }

    return Column(
      children: [
        _ozetKarti(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _sayfayiYukle,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              children: _planListesiWidgetlari(),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  _yillikPlanImportAc();
                },
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Yeni Yıllık Plan Yükle / Güncelle'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ozetKarti() {
    final yukluSayisi = _planDurumlari.where((e) => e.planYuklu).length;
    final toplam = _planDurumlari.length;
    final adSoyad = (_profil?['AdSoyad'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.indigo.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.indigo.withValues(alpha: 0.12),
            child: const Icon(
              Icons.event_note_outlined,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Yıllık Plan Durumu',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (adSoyad.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    adSoyad,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  '$yukluSayisi / $toplam ders için yıllık plan yüklendi',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _planListesiWidgetlari() {
    final widgetlar = <Widget>[];
    int? sonSinif;

    for (final durum in _planDurumlari) {
      if (sonSinif != durum.sinifSeviyesi) {
        if (sonSinif != null) {
          widgetlar.add(const SizedBox(height: 8));
        }

        widgetlar.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text(
              '${durum.sinifSeviyesi}. Sınıf',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );

        sonSinif = durum.sinifSeviyesi;
      }

      widgetlar.add(_planKarti(durum));
    }

    return widgetlar;
  }

  Widget _planKarti(_YillikPlanDurumu durum) {
    final yuklu = durum.planYuklu;
    final dosyaAdi = _dosyaAdiniGetir(durum.aciklama);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: ValueKey('dbf-yukle-${durum.dersId}-${durum.sinifSeviyesi}'),
                onPressed: () => _dbfImportAc(durum),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Ders Bilgi Formu Yükle / Görüntüle'),
              )),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: yuklu
                      ? Colors.green.withValues(alpha: 0.10)
                      : Colors.orange.withValues(alpha: 0.10),
                  child: Icon(
                    yuklu
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: yuklu ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: yuklu
                            ? () {
                                bireyselHaftalikKazanimAc(
                                  context,
                                  dersId: durum.dersId,
                                  dersAdi: durum.dersAdi,
                                  sinifSeviyesi: durum.sinifSeviyesi,
                                  ogretmenProfilId:
                                      _profil!['OgretmenProfilId'] as int,
                                  egitimOgretimYili:
                                      _profil!['EgitimOgretimYili']
                                          .toString().trim(),
                                );
                              }
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  durum.dersAdi,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: yuklu ? Colors.indigo : null,
                                  ),
                                ),
                              ),
                              if (yuklu) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.indigo,
                                  semanticLabel: 'Yıllık planı aç',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        yuklu
                            ? 'Yıllık plan yüklendi'
                            : 'Yıllık plan yüklenmemiş',
                        style: TextStyle(
                          color: yuklu
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (yuklu && dosyaAdi.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          'Dosya: $dosyaAdi',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (yuklu && durum.detaySayisi > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${durum.detaySayisi} plan satırı kayıtlı',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  _yillikPlanImportAc(durum: durum);
                },
                icon: Icon(
                  yuklu
                      ? Icons.refresh_outlined
                      : Icons.upload_file_outlined,
                ),
                label: Text(
                  yuklu ? 'Güncelle / Yeniden Yükle' : 'Yıllık Plan Yükle',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bosDersListesi() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_busy_outlined,
                size: 72,
                color: Colors.grey.shade500,
              ),
              const SizedBox(height: 18),
              const Text(
                'Yıllık plan için ders bulunamadı',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Önce Ders Programım bölümünden ders programınızı '
                'yükleyin. Yıllık planlar, ders programındaki derslerle '
                'eşleştirilir.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dosyaAdiniGetir(String aciklama) {
    const onEk = 'Import dosyası:';
    final temiz = aciklama.trim();

    if (temiz.toLowerCase().startsWith(onEk.toLowerCase())) {
      return temiz.substring(onEk.length).trim();
    }

    return temiz;
  }
}

class _YillikPlanDetayScreen extends StatefulWidget {
  const _YillikPlanDetayScreen({
    required this.ogretmenProfilId,
    required this.egitimOgretimYili,
    required this.dersId,
    required this.dersAdi,
    required this.sinifSeviyesi,
    required this.tarih,
    required this.sinif,
    required this.takvimUyarisi,
  });

  final int ogretmenProfilId;
  final String egitimOgretimYili;
  final int dersId;
  final String dersAdi;
  final int sinifSeviyesi;
  final DateTime tarih;
  final String sinif;
  final String takvimUyarisi;

  @override
  State<_YillikPlanDetayScreen> createState() => _YillikPlanDetayScreenState();
}

class _YillikPlanDetayScreenState extends State<_YillikPlanDetayScreen> {
  static const _alanlar = <String, String>{
    'HaftaNo': 'Hafta',
    'Ay': 'Ay',
    'TarihAraligi': 'Tarih aralığı',
    'Saat': 'Saat',
    'Unite': 'Ünite',
    'OgrenmeBirimi': 'Öğrenme birimi',
    'Konu': 'Konu',
    'IcerikCercevesi': 'İçerik çerçevesi',
    'Kazanim': 'Kazanım',
    'KazanimAciklamasi': 'Kazanım açıklaması',
    'OgrenmeCiktisi': 'Öğrenme çıktısı',
    'SurecBilesenleri': 'Süreç bileşenleri',
    'YontemTeknik': 'Yöntem ve teknik',
    'AracGerec': 'Araç ve gereç',
    'Degerlendirme': 'Değerlendirme',
  };

  final _yatayController = ScrollController();
  final _dikeyController = ScrollController();
  late Future<BireyselYillikPlanIcerigi> _icerik;
  late DateTime _seciliTarih;
  bool _tumYil = false;

  @override
  void initState() {
    super.initState();
    _seciliTarih = DateUtils.dateOnly(widget.tarih);
    _icerik = _detaylariGetir();
  }

  @override
  void dispose() {
    _yatayController.dispose();
    _dikeyController.dispose();
    super.dispose();
  }

  Future<BireyselYillikPlanIcerigi> _detaylariGetir() =>
      BireyselYillikPlanService.icerigiGetir(
        ogretmenProfilId: widget.ogretmenProfilId,
        egitimOgretimYili: widget.egitimOgretimYili,
        dersId: widget.dersId,
        sinifSeviyesi: widget.sinifSeviyesi,
      );

  String _metin(Map<String, Object?> satir, String alan) {
    final metin = (satir[alan] ?? '').toString().trim();
    if (alan != 'TarihAraligi' || metin.isNotEmpty) {
      return metin;
    }
    return ['BaslangicTarihi', 'BitisTarihi']
        .map((alan) => (satir[alan] ?? '').toString().trim())
        .where((deger) => deger.isNotEmpty)
        .map((deger) {
          final tarih = DateTime.tryParse(deger);
          if (tarih == null) return deger;
          final iso = '${tarih.year.toString().padLeft(4, '0')}-'
              '${tarih.month.toString().padLeft(2, '0')}-'
              '${tarih.day.toString().padLeft(2, '0')}';
          if (iso != deger) return deger;
          return '${tarih.day.toString().padLeft(2, '0')}.'
              '${tarih.month.toString().padLeft(2, '0')}.${tarih.year}';
        })
        .join(' – ');
  }

  void _yenile() {
    setState(() {
      _icerik = _detaylariGetir();
    });
  }

  String _tarihYaz(DateTime tarih) =>
      '${tarih.day.toString().padLeft(2, '0')}.'
      '${tarih.month.toString().padLeft(2, '0')}.${tarih.year}';

  Future<void> _tarihSec() async {
    final yil = BireyselYillikPlanService.egitimOgretimYiliniNormalizeEt(
      widget.egitimOgretimYili,
    ).split('-');
    final basYil = int.tryParse(yil.first) ?? _seciliTarih.year;
    final bitYil = yil.length == 2
        ? int.tryParse(yil.last) ?? basYil + 1
        : basYil + 1;
    final bas = DateTime(basYil, 1, 1);
    final bit = DateTime(bitYil < basYil ? basYil : bitYil, 12, 31);
    final ilk = _seciliTarih.isBefore(bas)
        ? bas
        : _seciliTarih.isAfter(bit)
        ? bit
        : _seciliTarih;
    final tarih = await showDatePicker(
      context: context,
      initialDate: ilk,
      firstDate: bas,
      lastDate: bit,
      helpText: 'Plan tarihi',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (!mounted || tarih == null) return;
    setState(() => _seciliTarih = tarih);
  }

  @override
  Widget build(BuildContext context) {
    return OrtakSayfa(
      appBar: ModulUstBar(
        title: Text(_tumYil ? 'Yıllık Plan' : 'Haftalık kazanım'),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<BireyselYillikPlanIcerigi>(
          future: _icerik,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _baslik(),
                  Text(snapshot.error.toString()),
                  TextButton.icon(
                    onPressed: _yenile,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tekrar Dene'),
                  ),
                ],
              );
            }
            final icerik = snapshot.data!;
            if (_tumYil && icerik.detaylar.isNotEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _baslik(),
                  ),
                  _gorunumDugmesi(),
                  Expanded(child: _tablo(icerik.detaylar)),
                ],
              );
            }
            return _haftalikGorunum(icerik);
          },
        ),
      ),
    );
  }

  Widget _baslik() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.dersAdi,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 4),
      Text(
        '${widget.sinifSeviyesi}. Sınıf'
        '${widget.sinif.trim().isEmpty ? '' : ' • ${widget.sinif.trim()}'}'
        ' • ${widget.egitimOgretimYili}',
      ),
    ],
  );

  Widget _gorunumDugmesi() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => setState(() => _tumYil = !_tumYil),
      icon: Icon(_tumYil ? Icons.view_agenda_outlined : Icons.table_chart_outlined),
      label: Text(_tumYil ? 'Haftalık karta dön' : 'Tüm yıl tablosu'),
    ),
  );

  Widget _haftalikGorunum(BireyselYillikPlanIcerigi icerik) {
    final satirlar = icerik.tariheAitDetaylar(_seciliTarih);
    return ListView(
      key: const ValueKey('haftalik-kazanim-listesi'),
      padding: const EdgeInsets.all(16),
      children: [
        _baslik(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Önceki gün',
              onPressed: () => setState(() {
                _seciliTarih = _seciliTarih.subtract(const Duration(days: 1));
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            OutlinedButton.icon(
              key: const ValueKey('haftalik-kazanim-tarih'),
              onPressed: _tarihSec,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_tarihYaz(_seciliTarih)),
            ),
            IconButton(
              tooltip: 'Sonraki gün',
              onPressed: () => setState(() {
                _seciliTarih = _seciliTarih.add(const Duration(days: 1));
              }),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () => setState(() {
                _seciliTarih = DateUtils.dateOnly(DateTime.now());
              }),
              child: const Text('Bugün'),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('gunluk-plan-hazirla'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => InheritedTheme.captureAll(
                  context,
                  BireyselGunlukPlanScreen(
                    ogretmenProfilId: widget.ogretmenProfilId,
                    egitimOgretimYili: widget.egitimOgretimYili,
                    dersId: widget.dersId,
                    dersAdi: widget.dersAdi,
                    sinifSeviyesi: widget.sinifSeviyesi,
                    tarih: _seciliTarih,
                    baslangicSinifKodu: widget.sinif,
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Günlük Plan Hazırla'),
          ),
        ),
        if (widget.takvimUyarisi.trim().isNotEmpty &&
            DateUtils.isSameDay(_seciliTarih, widget.tarih))
          _bilgi(widget.takvimUyarisi.trim()),
        if (icerik.yillikPlanId == null)
          _bilgi('Bu ders ve sınıf seviyesi için bu eğitim yılında yıllık plan bulunamadı.')
        else if (icerik.detaylar.isEmpty)
          _bilgi('Yıllık plan var; kayıtlı ayrıntı bulunamadı.')
        else ...[
          _gorunumDugmesi(),
          if (icerik.tarihsizDetayVar)
            _bilgi(
              'Bazı plan satırlarının tarih aralığı eksik veya geçersiz. '
              'Bu satırlar tarihe göre eşleştirilemedi; tüm yıl tablosunda görülebilir.',
            ),
          if (satirlar.isEmpty)
            _bilgi('Seçili tarih için plan bilgisi bulunamadı.')
          else
            for (var i = 0; i < satirlar.length; i++)
              _haftaKarti(satirlar[i], i, satirlar.length),
        ],
      ],
    );
  }

  Widget _bilgi(String metin) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(metin, style: Theme.of(context).textTheme.bodyMedium),
  );

  Widget _alan(Map<String, Object?> satir, String alan) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _alanlar[alan]!,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(_metin(satir, alan), style: const TextStyle(height: 1.5)),
      ],
    ),
  );

  Widget _haftaKarti(Map<String, Object?> satir, int sira, int toplam) {
    final onAlanlar = <String>[
      'Unite', 'OgrenmeBirimi', 'Konu',
      if (_metin(satir, 'Konu').isEmpty) 'IcerikCercevesi',
      'Kazanim', 'OgrenmeCiktisi',
    ].where((alan) => _metin(satir, alan).isNotEmpty).toList();
    final digerAlanlar = _alanlar.keys.where((alan) =>
      alan != 'HaftaNo' && alan != 'TarihAraligi' &&
      !onAlanlar.contains(alan) && _metin(satir, alan).isNotEmpty,
    ).toList();
    final hafta = _metin(satir, 'HaftaNo');
    final tarih = _metin(satir, 'TarihAraligi');
    return Card(
      key: ValueKey('haftalik-kazanim-karti-$sira'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hafta.isEmpty ? 'Hafta numarası belirtilmemiş' : '$hafta. hafta',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (tarih.isNotEmpty) Text(tarih),
            if (toplam > 1) Text('Plan satırı ${sira + 1} / $toplam'),
            for (final alan in onAlanlar) _alan(satir, alan),
            if (digerAlanlar.isNotEmpty)
              OrtakGenisleyenBolum(
                key: PageStorageKey('plan-diger-${satir['YillikPlanDetayId']}'),
                tilePadding: EdgeInsets.zero,
                title: const Text('Diğer plan bilgileri'),
                children: [
                  for (final alan in digerAlanlar) _alan(satir, alan),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _tablo(List<Map<String, Object?>> satirlar) {
    final renkler = Theme.of(context).colorScheme;
    final alanlar = _alanlar.keys.where((alan) {
      return alan == 'HaftaNo' ||
          alan == 'TarihAraligi' ||
          satirlar.any((satir) => _metin(satir, alan).isNotEmpty);
    }).toList(growable: false);
    final genislikler = alanlar.map((alan) {
      if (alan == 'HaftaNo' || alan == 'Saat') return 80.0;
      if (alan == 'Ay') return 120.0;
      if (alan == 'TarihAraligi') return 180.0;
      return 280.0;
    }).toList(growable: false);

    return Scrollbar(
      controller: _yatayController,
      thumbVisibility: true,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _yatayController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: SizedBox(
          width: genislikler.fold<double>(0, (toplam, deger) => toplam + deger),
          child: Scrollbar(
            controller: _dikeyController,
            child: SingleChildScrollView(
              controller: _dikeyController,
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.top,
                columnWidths: {
                  for (var i = 0; i < genislikler.length; i++)
                    i: FixedColumnWidth(genislikler[i]),
                },
                border: TableBorder.all(color: renkler.outlineVariant),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: renkler.primaryContainer),
                    children: [
                      for (final alan in alanlar)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _alanlar[alan]!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  for (var i = 0; i < satirlar.length; i++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: i.isEven ? renkler.surface : renkler.surfaceContainerLow,
                      ),
                      children: [
                        for (final alan in alanlar)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _metin(satirlar[i], alan).isEmpty
                                  ? '—'
                                  : _metin(satirlar[i], alan),
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
