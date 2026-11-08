import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';
import '../core/calisma_modu.dart';
import '../services/calisma_modu_service.dart';
import '../services/mesajlasma_service.dart';
import '../services/import_kurulum_service.dart';
import '../services/ogrenci_import_tanimi.dart';
import '../services/fotograf_import_tanimi.dart';
import 'ogretmen_ders_import_screen.dart';
import 'ortak_import_screen.dart';
import 'bireysel_ders_programi_import_screen.dart';
import 'bireysel_yillik_plan_import_screen.dart';
import 'bireysel_yillik_planlarim_screen.dart';
import 'bireysel_rehberlik_screen.dart';

/// Tek giriş, mevcut okuyucular ve modül onayları.
class ImportMerkeziScreen extends StatefulWidget {
  const ImportMerkeziScreen({
    super.key,
    this.mesajService,
    this.sinifId,
    this.ogrenciIslemleri = false,
  });
  final MesajlasmaService? mesajService;
  final int? sinifId;
  final bool ogrenciIslemleri;
  @override
  State<ImportMerkeziScreen> createState() => _ImportMerkeziState();
}

typedef _ImportBolumu = ({
  String ad,
  String bilgi,
  IconData ikon,
  Color renk,
  Widget ekran,
});

class _ImportMerkeziState extends State<ImportMerkeziScreen> {
  final _kurulum = ImportKurulumService();
  bool? _izin;
  bool _sihirbaz = false, _mesgul = false;
  int _adim = 0;
  String? _hata;
  ImportKurulumDurumu? _durum;

  List<_ImportBolumu> get _bolumler => [
    (
      ad: 'Ders programım',
      bilgi:
          'Kendi derslerinizi, sınıflarınızı ve haftalık saatlerinizi hazırlayın.',
      ikon: Icons.calendar_month_outlined,
      renk: Colors.indigo,
      ekran: const BireyselDersProgramiImportScreen(),
    ),
    (
      ad: 'Öğrenci listeleri',
      bilgi:
          'Ders verdiğiniz sınıfların öğrencilerini aktarın. Mükerrer kayıtlar ön izlemede kontrol edilir.',
      ikon: Icons.groups_outlined,
      renk: Colors.teal,
      ekran: const OrtakImportScreen(
        tanim: OgrenciImportTanimi.tanim,
        birlesikKaynakSecimi: true,
      ),
    ),
    (
      ad: 'Sınıf öğretmenleri ve dersleri',
      bilgi:
          'Mesajlaşma için öğretmen–sınıf–ders ilişkilerini PDF, Word veya Excel programından aktarın.',
      ikon: Icons.school_outlined,
      renk: Colors.deepOrange,
      ekran: OgretmenDersImportScreen(
        service: widget.mesajService,
        sinifId: widget.sinifId,
      ),
    ),
    (
      ad: 'Öğrenci fotoğrafları',
      bilgi:
          'Öğrenci listesinden sonra fotoğraflı e-Okul XLS dosyasını yükleyin.',
      ikon: Icons.photo_library_outlined,
      renk: Colors.purple,
      ekran: const OrtakImportScreen(
        tanim: FotografImportTanimi.tanim,
        birlesikKaynakSecimi: true,
        kayitGorseli: FotografImportTanimi.gorsel,
        ozelOnIzlemeyiHazirla: FotografImportTanimi.onIzlemeyiHazirla,
        alternatifOnIzlemeyiHazirla:
            FotografImportTanimi.hucrelerdenOnIzlemeyiHazirla,
        alternatifOnIzlemeAdi: 'Hücrelerden fotoğraf seç',
      ),
    ),
    (
      ad: 'Yıllık plan ve çalışma takvimi',
      bilgi: 'Yıllık planınızı yükleyin ve derslerinizle eşleştirin.',
      ikon: Icons.event_note_outlined,
      renk: Colors.blue,
      ekran: const BireyselYillikPlanImportScreen(),
    ),
    (
      ad: 'DBF / ders bilgi formları',
      bilgi: 'Dersi ve sınıf seviyesini seçerek ilgili DBF belgesini yükleyin.',
      ikon: Icons.description_outlined,
      renk: Colors.brown,
      ekran: const BireyselYillikPlanlarimScreen(),
    ),
    (
      ad: 'Rehberlik planı ve öğrenci tanıma formları',
      bilgi:
          'Rehberlik sınıfınızı seçerek plan ve öğrenci tanıma dosyalarını aktarın.',
      ikon: Icons.diversity_3_outlined,
      renk: Colors.pink,
      ekran: const BireyselRehberlikScreen(),
    ),
  ];

  // Katalog indeksleri: program, yıllık plan, liste, fotoğraf, öğretmenler.
  static const _kurulumSirasi = [0, 4, 1, 3, 2];

  static const _aciklamalar = [
    'Önce kendi haftalık ders programınızı yükleyin. Böylece ders verdiğiniz sınıflar ve dersler belirlenir; sonraki aktarımlar bu kapsamı kullanır.',
    'Programınızdaki sınıfların öğrenci listesini yükleyin. Ön izlemede okul numaralarını ve sınıfları kontrol edip kayıtları onaylayın.',
    'Sınıflarda derse giren diğer öğretmenleri ve derslerini yükleyin. Mesajlaşmada sınıfın öğretmenlerine ulaşmak için kullanılır. Kendi ders programınız değiştirilmez. Bu adım isteğe bağlıdır.',
    'Kayıtlı öğrencileri fotoğraflarıyla eşleştirmek için fotoğraflı e-Okul XLS dosyasını yükleyin. Önce öğrenci listeleri kaydedilmiş olmalıdır. Bu adım isteğe bağlıdır.',
    'Ders programınızdan sonra yıllık planınızı ve çalışma takvimini yükleyin. Ön izlemede ders eşleştirmelerini ve eğitim yılını kontrol ederek kaydedin.',
  ];
  static const _birimler = [
    'ders saati',
    'öğrenci',
    'öğretmen–sınıf–ders ilişkisi',
    'fotoğraflı öğrenci',
  ];

  @override
  void initState() {
    super.initState();
    _kontrol(ilk: true);
  }

  Future<void> _kontrol({bool ilk = false}) async {
    try {
      final izin =
          await CalismaModuService.getir() == CalismaModu.bireyselOgretmen;
      final durum = izin ? await _kurulum.getir() : null;
      if (!mounted) return;
      setState(() {
        _izin = izin;
        _durum = durum;
        _hata = null;
        if (ilk &&
            durum?.otomatik == true &&
            widget.sinifId == null &&
            !widget.ogrenciIslemleri) {
          _sihirbaz = true;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Import durumu okunamadı. Orijinal hata: $e');
      }
    }
  }

  Future<void> _ac(Widget ekran) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      if (await CalismaModuService.getir() != CalismaModu.bireyselOgretmen) {
        if (mounted) setState(() => _izin = false);
        return;
      }
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ekran));
      if (mounted) await _kontrol();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ekran açılamadı. Orijinal hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _bitir() async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      await _kurulum.kapat(_durum);
      if (mounted) setState(() => _sihirbaz = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tercih kaydedilemedi. Orijinal hata: $e')),
        );
      }
      if (mounted) setState(() => _sihirbaz = false);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Widget _kart(_ImportBolumu b, {String? ad}) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: _mesgul ? null : () => _ac(b.ekran),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: b.renk.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(b.ikon, color: b.renk, size: 32),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              ad ?? b.ad,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(b.bilgi),
          ],
        ),
      ),
    ),
  );

  Widget _ogrenciKarti() => KeyedSubtree(
    key: const ValueKey('import-ogrenciler-karti'),
    child: _kart((
      ad: 'Öğrenci listeleri',
      bilgi: 'Öğrenci listesi veya resimli liste yükleme işlemini seçin.',
      ikon: Icons.groups_outlined,
      renk: Colors.teal,
      ekran: const ImportMerkeziScreen(ogrenciIslemleri: true),
    )),
  );

  Widget _ogrenciIslemleri() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _kart(_bolumler[1], ad: 'Öğrenci listesi'),
      const SizedBox(height: 12),
      _kart(_bolumler[3], ad: 'Resimli liste'),
    ],
  );

  Widget _sihirbazGovdesi() {
    final bolumIndex = _kurulumSirasi[_adim];
    final b = _bolumler[bolumIndex];
    // Yıllık planın doğrulaması kendi import ekranında yapılır.
    final sayi = bolumIndex == 4 ? null : _durum?.sayilar[bolumIndex] ?? 0;
    final gerekliHazir = bolumIndex == 0 || (_durum?.sayilar[0] ?? 0) > 0;
    final yuklenebilir =
        gerekliHazir && (bolumIndex != 3 || (_durum?.sayilar[1] ?? 0) > 0);
    return ListView(
      key: ValueKey('kurulum-adim-$_adim'),
      padding: const EdgeInsets.all(20),
      children: [
        Text('Temel kurulum', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Dosyalarınızı sırayla yükleyin. Her yüklemede ön izleme ve onay adımları korunur. İstediğiniz zaman çıkıp kartlardan devam edebilirsiniz.',
        ),
        const SizedBox(height: 20),
        Text('Adım ${_adim + 1} / ${_kurulumSirasi.length}'),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: (_adim + 1) / _kurulumSirasi.length),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(b.ikon, size: 56, color: b.renk),
                const SizedBox(height: 16),
                Text(b.ad, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(_aciklamalar[bolumIndex]),
                const SizedBox(height: 16),
                Text(
                  sayi == null
                      ? 'Mevcut planlarınızı ve eşleştirmeleri yükleme ekranında kontrol edebilirsiniz.'
                      : sayi > 0
                      ? '$sayi ${_birimler[bolumIndex]} mevcut. Eksikleri kontrol ederek devam edebilirsiniz.'
                      : 'Henüz kayıt bulunmuyor.',
                ),
                if (!yuklenebilir)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Önce ders programını; fotoğraf için ayrıca öğrenci listesini yükleyin.',
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _mesgul || !yuklenebilir
                      ? null
                      : () => _ac(b.ekran),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Dosya seç ve yükle'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: [
            if (_adim > 0)
              OutlinedButton(
                onPressed: _mesgul ? null : () => setState(() => _adim--),
                child: const Text('Geri'),
              ),
            FilledButton(
              onPressed: _mesgul
                  ? null
                  : () {
                      if (_adim == _kurulumSirasi.length - 1) {
                        _bitir();
                      } else {
                        setState(() => _adim++);
                      }
                    },
              child: Text(
                _adim == _kurulumSirasi.length - 1
                    ? 'Import Merkezi’ne dön'
                    : sayi == null || sayi > 0
                    ? 'Sonraki adım'
                    : 'Şimdilik atla',
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: _mesgul ? null : _bitir,
          child: const Text('Sihirbazdan çık ve Import Merkezi’ne dön'),
        ),
      ],
    );
  }

  Widget _merkez() => ListView(
    key: const ValueKey('import-kartlar'),
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Verilerinizi hazırlayın',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        widget.sinifId == null
            ? 'Yüklemek istediğiniz bilgiyi seçin veya adım adım kurulumla başlayın.'
            : 'Seçili sınıfın bilgileri için Sınıf öğretmenleri ve dersleri kartını kullanın.',
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _mesgul
            ? null
            : () => setState(() {
                _adim = 0;
                _sihirbaz = true;
              }),
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('Adım adım kurulum'),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final sutun = constraints.maxWidth >= 650 ? 2 : 1;
          final genislik = (constraints.maxWidth - (sutun - 1) * 12) / sutun;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final kart in [
                _kart(_bolumler[0]),
                _kart(_bolumler[4]),
                _ogrenciKarti(),
                _kart(_bolumler[2]),
                _kart(_bolumler[5]),
                _kart(_bolumler[6]),
              ])
                SizedBox(width: genislik, child: kart),
            ],
          );
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sihirbaz || _izin != true,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _bitir();
    },
    child: OrtakSayfa(
      appBar: ModulUstBar(
        title: Text(
          _sihirbaz && _izin == true
              ? 'Import • İlk adımlar'
              : widget.ogrenciIslemleri
              ? 'Öğrenci listeleri'
              : 'Import Merkezi',
        ),
        leading: _sihirbaz && _izin == true
            ? IconButton(
                tooltip: 'Import Merkezi’ne dön',
                onPressed: _mesgul ? null : _bitir,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: _hata != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_hata!),
                    TextButton(
                      onPressed: () => _kontrol(ilk: true),
                      child: const Text('Yeniden dene'),
                    ),
                  ],
                ),
              ),
            )
          : _izin == null
          ? const Center(child: CircularProgressIndicator())
          : _izin == false
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Import oturumu kullanılamıyor. Uygulamayı yeniden başlatın.',
                ),
              ),
            )
          : widget.ogrenciIslemleri
          ? _ogrenciIslemleri()
          : _sihirbaz
          ? _sihirbazGovdesi()
          : _merkez(),
    ),
  );
}
