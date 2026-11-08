import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:flutter/material.dart';

import 'bireysel_ders_programi_import_screen.dart';
import '../services/bireysel_ders_programi_service.dart';
import '../services/bireysel_profil_service.dart';
import '../services/bireysel_program_gorev_atama_service.dart';
import '../services/bireysel_ders_tasima_service.dart';
import '../services/bireysel_ders_saati_service.dart';
import '../services/bireysel_ders_hucresi_ekle_service.dart';

class BireyselDersProgramimScreen extends StatefulWidget {
  const BireyselDersProgramimScreen({super.key, this.seflikRehberi = false});

  final bool seflikRehberi;

  @override
  State<BireyselDersProgramimScreen> createState() =>
      _BireyselDersProgramimScreenState();
}

class _BireyselDersProgramimScreenState
    extends State<BireyselDersProgramimScreen> {
  static const List<String> _gunler = <String>[
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
  ];

  static const double _saatSutunGenislik = 78;
  static const double _gunSutunGenislik = 168;
  static const double _hucreYukseklik = 142;

  // Bir satırdaki bütün günler aynı yükseklikte kalır. Telefonun
  // erişilebilirlik yazı ölçeği hücre içeriğini taşırmaz.
  double _uyarlanmisHucreYuksekligi(BuildContext context) {
    final olcek = MediaQuery.textScalerOf(context);
    final kucukYaziOrani = olcek.scale(11) / 11;
    final ortaYaziOrani = olcek.scale(14) / 14;
    final oran = kucukYaziOrani > ortaYaziOrani
        ? kucukYaziOrani
        : ortaYaziOrani;
    return _hucreYukseklik * (oran < 1 ? 1 : oran);
  }

  static const _mavi = Color(0xFF0756AA);
  static const _acikMavi = Color(0xFFEAF3FF);
  static const _yesil = Color(0xFFD9F4E8);
  static const _mor = Color(0xFFF0E2FF);
  static const _sari = Color(0xFFFFEFC9);

  Map<String, dynamic>? _profil;
  List<BireyselHaftalikDers> _dersler = <BireyselHaftalikDers>[];
  bool _yukleniyor = true;
  bool _rehberAcik = true;
  Map<int, ({String bas, String bit})> _okulSaatleri = {};
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

      final okulSaatleri = await BireyselDersSaatiService.getir();
      final dersler =
          await BireyselDersProgramiService.haftalikProgramiGetir(
        ogretmenProfilId: profilId,
        egitimOgretimYili: yil,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _profil = profil;
        _dersler = dersler;
        _okulSaatleri = okulSaatleri;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _hataMesaji =
            'Ders programınız yüklenirken hata oluştu.\nOrijinal hata: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _yukleniyor = false;
        });
      }
    }
  }

  Future<void> _saatEkle({int? istenenNo}) async {
    final yeniNo = [
      for (var i = 1; i <= 20; i++) i,
    ].firstWhere((n) => !_okulSaatleri.containsKey(n) &&
        !_dersler.any((d) => d.dersSaatiNo == n), orElse: () => 0);
    final secilenNo = istenenNo ?? yeniNo;
    if (secilenNo == 0 || secilenNo > 20 ||
        _okulSaatleri.containsKey(secilenNo) ||
        _dersler.any((d) => d.dersSaatiNo == secilenNo)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Yeni ders saati için boş sıra bulunamadı.')));
      return;
    }
    String basSaat = '';
    String bitSaat = '';
    final kaydet = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$secilenNo. ders saatini ekle'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Okulun gerçek başlangıç ve bitiş saatlerini girin. '
              'Mevcut ders saatleri değişmeyecek.'),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: '',
              onChanged: (value) => basSaat = value,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Başlangıç (SS:DD)',
                hintText: '16:00', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: '',
              onChanged: (value) => bitSaat = value,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Bitiş (SS:DD)',
                hintText: '16:40', border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Ders saatini ekle')),
        ],
      ),
    );
    basSaat = basSaat.trim();
    bitSaat = bitSaat.trim();
    if (kaydet != true || !mounted) return;
    try {
      await BireyselDersSaatiService.ekle(
        no: secilenNo, bas: basSaat, bit: bitSaat);
      await _sayfayiYukle();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ders saati eklenemedi. Orijinal hata: $e')));
    }
  }

  Future<void> _programiGuncelle() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BireyselDersProgramiImportScreen(),
      ),
    );

    if (mounted) {
      await _sayfayiYukle();
    }
  }

  Future<void> _hucreyeDersEkle(String gun, int saat) async {
    try {
      final secenekler = await BireyselDersHucresiEkleService.secenekler();
      if (!mounted) return;
      String ders = '', sinif = '', derslik = '';
      final onay = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(builder: (c, yenile) {
          Widget alan(String baslik, List<String> secenekler,
              String deger, ValueChanged<String> degistir,
              {bool zorunlu = true}) {
            return Autocomplete<String>(
              optionsBuilder: (v) => v.text.trim().isEmpty
                  ? secenekler
                  : secenekler.where((e) => e.toLowerCase()
                      .contains(v.text.toLowerCase())),
              onSelected: degistir,
              fieldViewBuilder: (ctx, controller, focus, submit) {
                return TextField(
                  controller: controller, focusNode: focus,
                  onChanged: degistir,
                  decoration: InputDecoration(
                    labelText: baslik,
                    hintText: zorunlu ? 'Listeden seç veya yeni yaz'
                      : 'İsteğe bağlı; boş bırakılabilir',
                    border: const OutlineInputBorder()),
                );
              },
            );
          }
          return AlertDialog(
            title: Text('$gun • $saat. ders: Ders Ekle'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                alan('Ders', secenekler.dersler, ders,
                  (v) => yenile(() => ders = v)),
                const SizedBox(height: 12),
                alan('Sınıf / Şube', secenekler.siniflar, sinif,
                  (v) => yenile(() => sinif = v)),
                const SizedBox(height: 12),
                alan('Derslik', secenekler.derslikler, derslik,
                  (v) => yenile(() => derslik = v), zorunlu: false),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false),
                child: const Text('Vazgeç')),
              FilledButton(
                onPressed: ders.trim().isEmpty || sinif.trim().isEmpty
                  ? null : () => Navigator.pop(c, true),
                child: const Text('Dersi kaydet')),
            ],
          );
        }),
      );
      if (onay != true || !mounted) return;
      await BireyselDersHucresiEkleService.kaydet(
        gun: gun, saat: saat, dersAdi: ders,
        sinifKodu: sinif, derslik: derslik);
      await _sayfayiYukle();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ders eklenemedi. Orijinal hata: $e')));
    }
  }

  Future<void> _hucreGoreviSec(String gun, int saat) async {
    final secim = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(Icons.add_circle_outline,
                  color: Theme.of(c).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('$gun • $saat. ders',
                  style: Theme.of(c).textTheme.titleMedium)),
              ]),
            ),
            Card(child: Column(children: [
              ListTile(
                leading: Icon(Icons.school_outlined,
                  color: Theme.of(c).colorScheme.primary),
                title: const Text('Ders Ekle'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, 'Ders')),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.groups_outlined,
                  color: Theme.of(c).colorScheme.primary),
                title: const Text('Şeflik olarak ata'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, 'Şeflik')),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.account_tree_outlined,
                  color: Theme.of(c).colorScheme.primary),
                title: const Text('Koordinatörlük olarak ata'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, 'Koordinatörlük')),
            ])),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
                label: const Text('Vazgeç'),
              ),
            ),
          ]),
        ),
      ),
    );
    if (secim == null || !mounted) return;
    if (secim == 'Ders') {
      await _hucreyeDersEkle(gun, saat);
      return;
    }
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Görev atamasını onayla'),
        content: Text('$gun • $saat. ders saati $secim olarak kaydedilecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Kaydet')),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    try {
      await BireyselProgramGorevAtamaService.ata(
        gun: gun, dersSaatiNo: saat, gorev: secim);
      await _sayfayiYukle();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Görev atanamadı. Orijinal hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final yil = (_profil?['EgitimOgretimYili'] ?? '').toString().trim();

    return OrtakSayfa(
      appBar: ModulUstBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ders Programım'),
            if (yil.isNotEmpty)
              Text(
                '$yil Eğitim Öğretim Yılı',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
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

    if (_dersler.isEmpty) {
      return _bosProgram();
    }

    return Column(
      children: [
        if (widget.seflikRehberi && _rehberAcik)
          Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Card(child: Padding(padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.tips_and_updates_outlined),
                const SizedBox(width: 10),
                const Expanded(child: Text(
                  'Şeflik saatini belirlemek için boş bir hücreye uzun basın. '
                  'Bilgisayarda sağ tıklayın. Açılan menüden '
                  '“Şeflik olarak ata” seçeneğini seçip onaylayın. '
                  'Haftalık 6 saatinizi belirledikten sonra yıllık plana dönün.')),
                IconButton(tooltip: 'Açıklamayı kapat',
                  onPressed: () => setState(() => _rehberAcik = false),
                  icon: const Icon(Icons.close)),
              ])))),
        _ustBilgiKarti(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(OrtakUi.radius),
                ),
                child: Row(children: [
                  Icon(Icons.schedule_outlined, size: 20,
                    color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 7),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Okul ders saatleri:',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${_okulSaatleri.length}',
                        style: Theme.of(context).textTheme.titleMedium),
                    ],
                  )),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: _programYapisiniYonet,
                icon: const Icon(Icons.tune_outlined, size: 19),
                label: const Text('Program Yapısını Yönet',
                  maxLines: 2, textAlign: TextAlign.center),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _haftalikProgramTablosu(),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: Row(children: [
              Expanded(child: FilledButton.icon(
                onPressed: _saatEkle,
                icon: const Icon(Icons.more_time_outlined, size: 19),
                label: const Text('Ders saati ekle', maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: _programiGuncelle,
                icon: const Icon(Icons.upload_file_outlined, size: 19),
                label: const Text('Programı yükle', maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              )),
            ]),
          ),
        ),
      ],
    );
  }

  Future<void> _saatSilSec() async {
    final saatler = <int>{..._okulSaatleri.keys, ..._dersler.map((d) => d.dersSaatiNo)}.toList()..sort();
    if (saatler.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silinecek ders saati bulunamadı.')));
      return;
    }
    final secilen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Ders Saati Sil'),
              subtitle: Text('Yalnızca boş ders saatleri silinebilir.')),
          ...saatler.map((no) {
            final dolu = _dersler.any((d) => d.dersSaatiNo == no);
            return ListTile(
              leading: Icon(dolu ? Icons.lock_outline : Icons.delete_outline),
              title: Text('$no. Ders'),
              subtitle: Text(dolu ? 'Bu saatte ders/görev var' : 'Boş ders saati'),
              enabled: !dolu,
              onTap: () => Navigator.pop(c, no),
            );
          }),
        ],
      )),
    );
    if (secilen != null && mounted) await _saatMenusu(secilen);
  }

  Future<void> _programYapisiniYonet() async {
    int secim = 0;
    final sonuc = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Icon(Icons.calendar_month_outlined,
                  color: Theme.of(c).colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Program Yapısını Yönet',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.pop(c),
                  icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 8),
              _programYonetimSecenegi(c, Icons.add, 'Yeni Ders Saati Ekle',
                'Haftalık programa yeni bir ders saati ekle',
                () => yenile(() => secim = 0), secili: secim == 0),
              _programYonetimSecenegi(c, Icons.edit_outlined,
                'Ders Saatlerini Düzenle', 'Başlangıç-bitiş saatlerini güncelle',
                () => yenile(() => secim = 1), secili: secim == 1),
              _programYonetimSecenegi(c, Icons.swap_vert,
                'Ders Sırasını Değiştir',
                'Dersi basılı tutup hedef hücreye sürükleyerek taşı',
                () => yenile(() => secim = 2), secili: secim == 2),
              _programYonetimSecenegi(c, Icons.delete_outline,
                'Ders Saatini Sil', 'Yalnızca boş ders saatlerini kaldır',
                () => yenile(() => secim = 3),
                secili: secim == 3, tehlikeli: true),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Vazgeç'),
                )),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(
                  onPressed: () => Navigator.pop(c, secim),
                  icon: const Icon(Icons.check),
                  label: const Text('Kaydet'),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (!mounted || sonuc == null) return;
    // Kaydet, seçili yönetim işlemini başlatır. Gerçek veri değişikliği
    // ilgili işlemin kendi doğrulama ve onay adımında gerçekleşir.
    switch (sonuc) {
      case 0:
        await _saatEkle();
      case 1:
        await _saatSecVeYonet();
      case 2:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Dersi taşımak için ders kartına basılı tutup hedef hücreye sürükleyin.'),
        ));
      case 3:
        await _saatSilSec();
    }
  }

  Widget _programYonetimSecenegi(
    BuildContext c, IconData icon, String baslik, String aciklama,
    VoidCallback sec, {bool secili = false, bool tehlikeli = false}
  ) {
    final renk = tehlikeli
        ? Theme.of(c).colorScheme.error
        : Theme.of(c).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: secili ? Theme.of(c).colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: secili ? Theme.of(c).colorScheme.primary
              : Theme.of(c).colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: sec,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            Icon(icon, color: renk),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(aciklama, style: Theme.of(c).textTheme.bodySmall),
              ],
            )),
            Icon(secili ? Icons.check_circle : Icons.chevron_right,
              color: secili ? Theme.of(c).colorScheme.primary : null),
          ]),
        ),
      ),
    );
  }

  Future<void> _saatSecVeYonet() async {
    final saatler = <int>{..._okulSaatleri.keys, ..._dersler.map((d) => d.dersSaatiNo)}.toList()..sort();
    final secilen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Ders Saatini Seç')),
          ...saatler.map((no) => ListTile(
            leading: const Icon(Icons.schedule),
            title: Text('$no. Ders'),
            onTap: () => Navigator.pop(c, no))),
        ],
      )),
    );
    if (secilen != null && mounted) await _saatMenusu(secilen);
  }

  Widget _ustBilgiKarti() {
    final adSoyad = (_profil?['AdSoyad'] ?? '').toString().trim();
    final yil = (_profil?['EgitimOgretimYili'] ?? '').toString().trim();
    final dersGunuSayisi = _dersler.map((e) => e.gun).toSet().length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(OrtakUi.bosluk),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: .70),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(OrtakUi.radius),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).colorScheme.surface,
            child: Icon(
              Icons.calendar_month_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Haftalık Ders Programı',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  <String>[
                    if (adSoyad.isNotEmpty) adSoyad,
                    if (yil.isNotEmpty) yil,
                  ].join(' • '),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$dersGunuSayisi gün • ${_dersler.length} ders/görev kaydı',
                  style: TextStyle(
                    color: Colors.grey.shade600,
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

  Widget _bosProgram() {
    final yil = (_profil?['EgitimOgretimYili'] ?? '').toString().trim();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_view_week_outlined,
                size: 72,
                color: Colors.grey.shade500,
              ),
              const SizedBox(height: 18),
              const Text(
                'Henüz ders programı yüklenmedi',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                yil.isEmpty
                    ? 'Ders programınızı Excel dosyasından yükleyebilirsiniz.'
                    : '$yil eğitim öğretim yılı için ders programı '
                        'bulunamadı.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _programiGuncelle,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Ders Programı Yükle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _haftalikProgramTablosu() {
    final dersSaatleri = [..._dersler.map((e) => e.dersSaatiNo),
        ..._okulSaatleri.keys]
        .where((e) => e > 0)
        .toSet()
        .toList()
      ..sort();

    final toplamGenislik =
        _saatSutunGenislik + (_gunSutunGenislik * _gunler.length);

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child: SizedBox(
          width: toplamGenislik,
          child: Column(
            children: [
              _baslikSatiri(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: dersSaatleri
                        .map((dersSaatiNo) => _dersSatiri(dersSaatiNo))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _baslikSatiri() {
    return Row(
      children: [
        _tabloKutusu(
          width: _saatSutunGenislik,
          height: 54,
          child: Center(
            child: Text(
              'Ders',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
          arkaPlan: Theme.of(context).colorScheme.primary,
        ),
        ..._gunler.map(
          (gun) {
            final bugun = _bugunGunAdi() == gun;

            return _tabloKutusu(
              width: _gunSutunGenislik,
              height: 54,
              arkaPlan: Theme.of(context).colorScheme.primary,
              child: Center(
                child: Text(
                  gun.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _saatMenusu(int no) async {
    final secim = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text('$no. ders saati'),
            subtitle: const Text('Ders saati işlemleri')),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: Text('${no + 1}. ders saatini ekle'),
            onTap: () => Navigator.pop(c, 'ekle')),
          ListTile(
            leading: Icon(Icons.delete_outline,
              color: Theme.of(c).colorScheme.error),
            title: const Text('Bu ders saatini sil'),
            onTap: () => Navigator.pop(c, 'sil')),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Vazgeç'),
            onTap: () => Navigator.pop(c)),
        ],
      )),
    );
    if (!mounted || secim == null) return;
    if (secim == 'ekle') {
      await _saatEkle(istenenNo: no + 1);
      return;
    }
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$no. ders saatini sil?'),
        content: const Text('Yalnızca ders veya görev kaydı bulunmayan '
          'boş saatler silinebilir. Mevcut derslere dokunulmaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    try {
      await BireyselDersSaatiService.sil(no);
      await _sayfayiYukle();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ders saati silinemedi. Orijinal hata: $e')));
    }
  }

  Widget _dersSatiri(int dersSaatiNo) {
    final saatReferansi = _dersler
        .where((e) => e.dersSaatiNo == dersSaatiNo)
        .cast<BireyselHaftalikDers?>()
        .firstOrNull;

    final tanimliSaat = _okulSaatleri[dersSaatiNo];
    final saat = saatReferansi == null
        ? (tanimliSaat == null ? '' : '${tanimliSaat.bas}\n${tanimliSaat.bit}')
        : '${_saatKisalt(saatReferansi.baslangic)}\n'
            '${_saatKisalt(saatReferansi.bitis)}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _saatMenusu(dersSaatiNo),
          onLongPress: () => _saatMenusu(dersSaatiNo),
          onSecondaryTap: () => _saatMenusu(dersSaatiNo),
          child: _tabloKutusu(
          width: _saatSutunGenislik,
          height: _uyarlanmisHucreYuksekligi(context),
          arkaPlan: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$dersSaatiNo. Ders',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (saat.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    saat.replaceFirst('\n', ' – '),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        ),
        ..._gunler.map(
          (gun) => _dersHucresi(
            gun: gun,
            dersSaatiNo: dersSaatiNo,
          ),
        ),
      ],
    );
  }

  Future<void> _dersBirak(BireyselHaftalikDers kaynak,
      String hedefGun, int hedefSaat) async {
    if (kaynak.dersProgramiId == null) return;
    final hedef = _dersler.where(
      (d) => d.gun == hedefGun && d.dersSaatiNo == hedefSaat).toList();
    if (hedef.length > 1 || hedef.any((d) => d.gorevMi)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Birden fazla ders veya görev olan hedefe taşıma yapılamaz.')));
      return;
    }
    final onay = await showDialog<bool>(context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ders programını değiştir'),
        content: Text('${kaynak.dersAdi}: ${kaynak.gun} ${kaynak.dersSaatiNo}. ders'
            ' → $hedefGun $hedefSaat. ders. '
            '${hedef.isEmpty ? "Taşınacak." : "İki dersin yeri değiştirilecek."}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Onayla')),
        ],
      ));
    if (onay != true || !mounted) return;
    try {
      await BireyselDersTasimaService.tasi(
        kaynakId: kaynak.dersProgramiId!,
        hedefGun: hedefGun,
        hedefSaatNo: hedefSaat);
      await _sayfayiYukle();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ders taşınamadı. Orijinal hata: $e')));
    }
  }

  Widget _dersHucresi({
    required String gun,
    required int dersSaatiNo,
  }) {
    final eslesenler = _dersler
        .where(
          (e) => e.gun == gun && e.dersSaatiNo == dersSaatiNo,
        )
        .toList(growable: false);

    if (eslesenler.isEmpty) {
      return DragTarget<BireyselHaftalikDers>(
        onWillAcceptWithDetails: (d) => d.data.dersProgramiId != null,
        onAcceptWithDetails: (d) => _dersBirak(d.data, gun, dersSaatiNo),
        builder: (context, candidates, rejected) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _hucreGoreviSec(gun, dersSaatiNo),
        onLongPress: () => _hucreGoreviSec(gun, dersSaatiNo),
        onSecondaryTap: () => _hucreGoreviSec(gun, dersSaatiNo),
        child: _tabloKutusu(
          width: _gunSutunGenislik,
          height: _uyarlanmisHucreYuksekligi(context),
          arkaPlan: _acikMavi,
          child: const Center(child: Icon(Icons.add,
            color: _mavi, size: 25)),
        ),
        ),
      );
    }

    final ders = eslesenler.first;
    final aktif = _aktifDersMi(ders);
    final bugun = _bugunGunAdi() == gun;

    final hucresel = _tabloKutusu(
      width: _gunSutunGenislik,
      height: _uyarlanmisHucreYuksekligi(context),
      arkaPlan: aktif
          ? const Color(0xFFCAF2D3)
          : ders.seflikMi
              ? _sari
              : ders.gorevMi
                  ? _mor
                  : (ders.dersSaatiNo.isEven ? _yesil : _mor),
      kenarlikRengi: aktif ? Colors.green.shade400 : null,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (aktif)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.play_circle_fill,
                      size: 14,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'ŞU AN',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              ders.dersAdi,
              maxLines: 3,
              softWrap: true,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            if (ders.gorevMi) Icon(ders.seflikMi ? Icons.people_outline : Icons.account_tree_outlined, size: 16, color: _mavi),
            Text(
              ders.gorevMi ? (ders.seflikMi ? 'Şeflik' : 'Görev') : ders.sinif,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (ders.derslik.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.room_outlined, size: 12),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      ders.derslik,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (eslesenler.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '+${eslesenler.length - 1} kayıt',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return DragTarget<BireyselHaftalikDers>(
      onWillAcceptWithDetails: (d) => d.data.dersProgramiId != null &&
          eslesenler.length == 1 && !ders.gorevMi,
      onAcceptWithDetails: (d) => _dersBirak(d.data, gun, dersSaatiNo),
      builder: (context, candidates, rejected) =>
          ders.dersProgramiId == null || eslesenler.length != 1 || ders.gorevMi
              ? hucresel
              : LongPressDraggable<BireyselHaftalikDers>(
                  data: ders,
                  feedback: Material(
                    elevation: 5,
                    child: SizedBox(width: _gunSutunGenislik,
                      child: ListTile(title: Text(ders.dersAdi, maxLines: 2))),
                  ),
                  childWhenDragging: Opacity(opacity: 0.35, child: hucresel),
                  child: hucresel,
                ),
    );
  }

  Widget _tabloKutusu({
    required double width,
    required double height,
    required Widget child,
    Color? arkaPlan,
    Color? kenarlikRengi,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: arkaPlan ?? Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: kenarlikRengi ?? Theme.of(context).colorScheme.outlineVariant,
          width: kenarlikRengi == null ? 0.7 : 1.3,
        ),
      ),
      child: child,
    );
  }

  bool _aktifDersMi(BireyselHaftalikDers ders) {
    final simdi = DateTime.now();

    if (ders.gunNo != simdi.weekday) {
      return false;
    }

    final baslangic = _dakikayaCevir(ders.baslangic);
    final bitis = _dakikayaCevir(ders.bitis);

    if (baslangic == null || bitis == null) {
      return false;
    }

    final simdiDakika = simdi.hour * 60 + simdi.minute;
    return simdiDakika >= baslangic && simdiDakika < bitis;
  }

  int? _dakikayaCevir(String saat) {
    final parcalar = saat.split(':');

    if (parcalar.length < 2) {
      return null;
    }

    final saatDegeri = int.tryParse(parcalar[0]);
    final dakikaDegeri = int.tryParse(parcalar[1]);

    if (saatDegeri == null || dakikaDegeri == null) {
      return null;
    }

    return saatDegeri * 60 + dakikaDegeri;
  }

  String _bugunGunAdi() {
    final gunNo = DateTime.now().weekday;

    if (gunNo < DateTime.monday || gunNo > DateTime.friday) {
      return '';
    }

    return _gunler[gunNo - 1];
  }

  String _saatKisalt(String saat) {
    final parcalar = saat.split(':');

    if (parcalar.length < 2) {
      return saat;
    }

    return '${parcalar[0]}:${parcalar[1]}';
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;

    if (!iterator.moveNext()) {
      return null;
    }

    return iterator.current;
  }
}
