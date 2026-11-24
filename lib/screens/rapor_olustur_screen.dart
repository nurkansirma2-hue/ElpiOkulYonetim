import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'package:elpi_okul_yonetim/models/sinif.dart';
import 'package:elpi_okul_yonetim/services/rapor_service.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../models/rapor_sablonu.dart';
import '../services/bireysel_liste_service.dart';
import '../services/ogrenci_rapor_uyarlayici.dart';
import '../raporlama/rapor_modeli.dart';
import '../raporlama/rapor_tasarim_editoru.dart';
import '../widgets/ogrenci_foto_widget.dart';
import 'admin_import_screen.dart';
import 'veli_bilgileri_screen.dart';
import 'bireysel_ogrenci_bilgileri_screen.dart';

class _OgrenciFormBolumBasligi extends StatelessWidget {
  const _OgrenciFormBolumBasligi({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    ]),
  );
}

class RaporOlusturScreen extends StatefulWidget {
  const RaporOlusturScreen({super.key, this.sekmeIcinde = false, this.klavyeAcik = false});
  final bool sekmeIcinde, klavyeAcik;
  @override
  State<RaporOlusturScreen> createState() => _BireyselListeEkraniState();
}

class _BireyselListeEkraniState extends State<RaporOlusturScreen> {
  BireyselListeOturumu? _oturum;
  Sinif? _sinif;
  List<Map<String, Object?>> _ogrenciler = [];
  String _ogrenciArama = '';
  int? _seciliOgrenciId;
  bool _silmeSecimModu = false;
  List<RaporSablonu> _kayitli = [];
  RaporSablonu _tasarim = RaporSablonu.hazirSablonlar().first;
  late RaporTasarimi _ortakTasarim;
  bool _bekle = true;
  String? _hata;
  int _bolum = 0, _surum = 0, _gorunum = 0;
  bool _artan = true;
  bool get _klavyeAcik => widget.klavyeAcik || MediaQuery.viewInsetsOf(context).bottom > 0;
  Future<Uint8List>? _pdf;
  Timer? _onIzlemeZamani;
  Timer? _mudurKayitZamani;
  Future<void> _mudurKaydi = Future<void>.value();
  int _mudurDuzenlemeSurumu = 0;
  bool _mudurKirli = false, _dersElle = false;
  final _ders = TextEditingController();
  final _okul = TextEditingController();
  final _ogretmen = TextEditingController();
  final _mudur = TextEditingController();
  @override
  void initState() {
    super.initState();
    _ortakTasarimiHazirla();
    _hazirla();
  }
  @override
  void dispose() {
    _onIzlemeZamani?.cancel();
    _mudurKayitZamani?.cancel();
    unawaited(_muduruKaydet().catchError((Object _) {}));
    _ders.dispose(); _okul.dispose(); _ogretmen.dispose(); _mudur.dispose();
    super.dispose();
  }

  List<String> get _dersSecenekleri {
    final dersler = _oturum?.sinifDersleri ?? const <int, List<String>>{};
    final secenekler = (_sinif == null
        ? dersler.values.expand((d) => d)
        : dersler[_sinif!.sinifSubeId] ?? const <String>[]).toSet().toList();
    secenekler.sort();
    return secenekler;
  }

  void _dersSeciminiYenile() {
    final secenekler = _dersSecenekleri;
    if (!_dersElle && secenekler.contains(_ders.text)) return;
    _dersElle = false;
    _ders.text = secenekler.length == 1 ? secenekler.single : '';
  }

  Future<void> _muduruKaydet() async {
    final oturum = _oturum;
    if (!_mudurKirli || oturum == null) return _mudurKaydi;
    final metin = _mudur.text;
    final duzenlemeSurumu = _mudurDuzenlemeSurumu;
    _mudurKaydi = _mudurKaydi.then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .then((_) => BireyselListeService.mudurKaydet(oturum, metin));
    await _mudurKaydi;
    if (mounted && identical(_oturum, oturum) && _mudurDuzenlemeSurumu == duzenlemeSurumu &&
        _mudur.text == metin) {
      _mudurKirli = false;
    }
  }

  void _mudurDegisti() {
    _mudurDuzenlemeSurumu++;
    _mudurKirli = true;
    _metinDegisti();
    _mudurKayitZamani?.cancel();
    _mudurKayitZamani = Timer(const Duration(milliseconds: 400), () async {
      try { await _muduruKaydet(); }
      catch (e) { if (mounted) _mesaj('Okul müdürü kaydedilemedi. Orijinal hata: $e'); }
    });
  }

  void _metinDegisti() {
    _pdf = null;
    _onIzlemeZamani?.cancel();
    _onIzlemeZamani = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() { _pdf = null; _surum++; });
    });
  }

  Future<void> _hazirla({bool secimiKoru = false}) async {
    final oncekiOturum = _oturum;
    final oncekiSinifId = _sinif?.sinifSubeId;
    _onIzlemeZamani?.cancel();
    _mudurKayitZamani?.cancel();
    setState(() { _bekle = true; _hata = null; _pdf = null; _surum++;
      _seciliOgrenciId = null; _silmeSecimModu = false; });
    try {
      final oturum = await BireyselListeService.hazirla(ekSiniflariDahilEt: true);
      final kayitli = await BireyselListeService.sablonlar(oturum);
      final ayniOturum = secimiKoru && oncekiOturum != null &&
          oncekiOturum.ogretmenId == oturum.ogretmenId && oncekiOturum.yil == oturum.yil &&
          oncekiOturum.okul == oturum.okul;
      final oncekiSiniflar = ayniOturum
          ? oturum.siniflar.where((s) => s.sinifSubeId == oncekiSinifId).toList()
          : <Sinif>[];
      final sinif = oncekiSiniflar.isNotEmpty ? oncekiSiniflar.first : null;
      final ogrenciler = await BireyselListeService.ogrenciler(oturum, sinif?.sinifSubeId);
      if (!mounted) return;
      _oturum = oturum;
      if (!ayniOturum) {
        _okul.text = oturum.okul;
        _ogretmen.text = oturum.ogretmen;
        _mudur.text = oturum.mudur;
        _mudurKirli = false;
        _ders.clear();
        _dersElle = false;
      }
      _kayitli = kayitli;
      _sinif = sinif;
      if (!ayniOturum || !_dersElle || sinif?.sinifSubeId != oncekiSinifId) _dersSeciminiYenile();
      _ogrenciler = ogrenciler;
    } catch (e) { _hata = 'Liste hazırlanamadı. Orijinal hata: $e'; }
    finally { if (mounted) setState(() => _bekle = false); }
  }

  Future<void> _importAc({bool fotograf = false}) async {
    if (_bekle) return;
    if (fotograf) {
      setState(() => _bekle = true);
      try {
        final oturum = _oturum;
        if (oturum == null) throw StateError('Öğrencilerim listesini yeniden açın.');
        final ogrenciler = await BireyselListeService.ogrenciler(oturum, null);
        if (!mounted) return;
        if (ogrenciler.isEmpty) {
          _mesaj('Fotoğraf eklemek için önce Öğrenci Import ile öğrencileri yükleyin.');
          return;
        }
      } catch (e) {
        if (mounted) _mesaj('Öğrenciler kontrol edilemedi. Orijinal hata: $e');
        return;
      } finally {
        if (mounted) setState(() => _bekle = false);
      }
    }
    if (!mounted) return;
    try { await _muduruKaydet(); }
    catch (e) {
      if (mounted) _mesaj('Okul müdürü kaydedilemedi. Orijinal hata: $e');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminImportScreen(bireyselFoto: fotograf),
      ),
    );
    if (mounted) await _hazirla(secimiKoru: true);
  }

  Future<void> _ogrenciEkle() async {
    final oturum = _oturum;
    if (oturum == null || oturum.siniflar.isEmpty || _bekle) return;
    final no = TextEditingController();
    final ad = TextEditingController();
    final soyad = TextEditingController();
    int sinifId = _sinif?.sinifSubeId ?? oturum.siniflar.first.sinifSubeId;
    String cinsiyet = 'Belirtilmedi';
    final formKey = GlobalKey<FormState>();
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.person_add_alt_1_outlined),
            SizedBox(width: 8),
            Expanded(child: Text('Öğrenci Ekle')),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _OgrenciFormBolumBasligi(
                      icon: Icons.badge_outlined, title: 'Temel Bilgiler'),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: ad,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Ad *'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Ad zorunludur.' : null,
                    ),
                    TextFormField(
                      controller: soyad,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Soyad *'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Soyad zorunludur.' : null,
                    ),
                    TextFormField(
                      controller: no,
                      maxLength: 30,
                      decoration: const InputDecoration(labelText: 'Okul No *'),
                      keyboardType: TextInputType.number,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Okul numarası zorunludur.' : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: cinsiyet,
                      decoration: const InputDecoration(labelText: 'Cinsiyet'),
                      items: const [
                        DropdownMenuItem(value: 'Belirtilmedi', child: Text('Belirtilmedi')),
                        DropdownMenuItem(value: 'Kız', child: Text('Kız')),
                        DropdownMenuItem(value: 'Erkek', child: Text('Erkek')),
                      ],
                      onChanged: (v) {
                        if (v != null) yenile(() => cinsiyet = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    const _OgrenciFormBolumBasligi(
                      icon: Icons.school_outlined, title: 'Sınıf Bilgileri'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: sinifId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sınıf / Şube *'),
                      items: [
                        for (final sn in oturum.siniflar)
                          DropdownMenuItem(
                            value: sn.sinifSubeId,
                            child: Text(sn.sinif, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) yenile(() => sinifId = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Kayıt durumu: Aktif. Ek bilgiler öğrenci detayından '
                      'düzenlenebilir.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('İptal'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(c, true);
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    final okulNo = no.text, isim = ad.text, soyisim = soyad.text;
    // Dialog kapandıktan sonra kontrolcüleri bırak.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    no.dispose(); ad.dispose(); soyad.dispose();
    if (!mounted || onay != true) return;
    try {
      await BireyselListeService.ogrenciEkle(oturum, sinifId: sinifId,
        okulNo: okulNo, ad: isim, soyad: soyisim, cinsiyet: cinsiyet);
      if (mounted) {
        await _hazirla(secimiKoru: true);
        if (mounted) _mesaj('Öğrenci sınıfa kaydedildi.');
      }
    } catch (e) {
      if (mounted) _mesaj('Öğrenci eklenemedi. Orijinal hata: $e');
    }
  }

  Future<void> _ogrenciyiSiniftanCikar(Map<String, Object?> ogrenci) async {
    final oturum = _oturum;
    if (oturum == null || _bekle) return;
    final sinif = oturum.siniflar.where(
      (s) => s.sinif == ogrenci['SinifKodu']).toList();
    if (sinif.length != 1) {
      _mesaj('Öğrencinin sınıfı belirlenemedi. Listeyi yenileyin.');
      return;
    }
    final onay = await showDialog<bool>(context: context,
      builder: (c) => AlertDialog(
        title: const Text('Öğrenciyi listeden çıkar'),
        content: Text(
          '${ogrenci['Ad']} ${ogrenci['Soyad']} (No: ${ogrenci['OkulNo']}) '
          '${sinif.single.sinif} sınıfının ${oturum.yil} listesinden çıkarılacak. '
          'Kimlik, önceki yıllar, formlar ve diğer kayıtlar silinmeyecek. '
          'Aynı sınıfa yeniden eklenebilir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Listeden çıkar')),
        ],
      ));
    if (!mounted || onay != true) return;
    try {
      await BireyselListeService.siniftanCikar(oturum,
        ogrenciId: ogrenci['OgrenciId'] as int,
        sinifId: sinif.single.sinifSubeId);
      if (mounted) {
        setState(() { _seciliOgrenciId = null; _silmeSecimModu = false; });
        await _hazirla(secimiKoru: true);
        if (mounted) _mesaj('Öğrenci sınıf listesinden çıkarıldı.');
      }
    } catch (e) {
      if (mounted) _mesaj('Öğrenci çıkarılamadı. Orijinal hata: $e');
    }
  }

  void _degistir(VoidCallback islem) {
    setState(() { islem(); _pdf = null; _surum++; });
  }
  void _ortakTasarimiHazirla() {
    _ortakTasarim = OgrenciRaporUyarlayici.tasarim(_tasarim);
  }
  void _ortakDegistir(VoidCallback islem) => _degistir(() {
    islem();
    OgrenciRaporUyarlayici.geriAktar(_ortakTasarim, _tasarim, dogrula: false);
  });
  Map<String, String> get _raporBilgileri => {
    'okul': _okul.text, 'ogretmen': _ogretmen.text,
    'sinif': _sinif?.sinif ?? 'Tüm Sınıflar', 'ders': _ders.text,
    'mudur': _mudur.text, 'yil': _oturum!.yil,
    'tarih': DateFormat('dd.MM.yyyy').format(DateTime.now()),
  };
  void _sinifSutununuHazirla() {
    if (_sinif == null && _ortakTasarim.sutunlar.length < 16 &&
        !_ortakTasarim.sutunlar.any((s) => s.alanId == 'sinif')) {
      _ortakTasarim.sutunlar.insert(0, RaporTabloSutunu(alanId: 'sinif', baslik: 'Sınıf'));
      OgrenciRaporUyarlayici.geriAktar(_ortakTasarim, _tasarim, dogrula: false);
    }
  }
  void _bolumSec(int bolum) => _degistir(() {
    _bolum = bolum;
    _seciliOgrenciId = null;
    _silmeSecimModu = false;
    if (bolum == 1) _sinifSutununuHazirla();
  });
  Future<void> _sinifSec(int? sinifId) async {
    if (sinifId == null || _bekle) return;
    final sinif = sinifId == 0 ? null
        : _oturum!.siniflar.firstWhere((s) => s.sinifSubeId == sinifId);
    setState(() {
      _sinif = sinif; _seciliOgrenciId = null;
      _silmeSecimModu = false; _dersSeciminiYenile();
      if (_bolum == 1) _sinifSutununuHazirla();
      _bekle = true; _hata = null; _ogrenciler = []; _pdf = null;
    });
    try { _ogrenciler = await BireyselListeService.ogrenciler(_oturum!, sinif?.sinifSubeId); }
    catch (e) { _hata = 'Öğrenciler okunamadı. Orijinal hata: $e'; }
    finally { if (mounted) setState(() => _bekle = false); }
  }
  Future<void> _kaydet() async {
    final controller = TextEditingController(text: _tasarim.ad);
    final ad = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Şablonu Kaydet'),
      content: TextField(controller: controller, maxLength: 80,
        decoration: const InputDecoration(labelText: 'Şablon adı')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Kaydet'))],
    ));
    // Dialog çıkış animasyonu sırasında TextField hâlâ controller kullanabilir.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (!mounted || ad == null) return;
    if (_kayitli.any((s) => s.ad.trim().toLowerCase() == ad.toLowerCase())) {
      final onay = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Kayıtlı Şablonu Güncelle'), content: Text('“$ad” şablonunun üzerine kaydedilsin mi?'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Güncelle'))]));
      if (!mounted || onay != true) return;
    }
    setState(() => _bekle = true);
    try {
      await _muduruKaydet();
      OgrenciRaporUyarlayici.geriAktar(_ortakTasarim, _tasarim);
      final kopya = RaporSablonu.fromJson({..._tasarim.toJson(), 'ad': ad});
      await BireyselListeService.sablonKaydet(_oturum!, kopya);
      final kayitli = await BireyselListeService.sablonlar(_oturum!);
      if (!mounted) return;
      setState(() { _kayitli = kayitli; _tasarim.ad = ad; _ortakTasarim.ad = ad; });
      _mesaj('Şablon cihazınıza kaydedildi. Diğer sınıflarda da kullanabilirsiniz.');
    } catch (e) { if (mounted) _mesaj('Şablon kaydedilemedi. Orijinal hata: $e'); }
    finally { if (mounted) setState(() => _bekle = false); }
  }
  void _mesaj(String metin) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(metin)));
  Future<Uint8List> _pdfHazirla() async {
    final sablon = _tasarim.kopya();
    final sinif = _sinif;
    if (sinif == null && !sablon.sutunlar.any((s) => s.kaynak == 'sinif')) {
      if (sablon.sutunlar.length >= 16) {
        throw StateError('Tüm sınıfları yazdırmak için tasarıma Sınıf sütunu ekleyin veya bir sütun kaldırın.');
      }
      final ortak = OgrenciRaporUyarlayici.tasarim(sablon);
      ortak.sutunlar.insert(0, RaporTabloSutunu(alanId: 'sinif', baslik: 'Sınıf'));
      OgrenciRaporUyarlayici.geriAktar(ortak, sablon);
    }
    final bilgiler = _raporBilgileri;
    await _muduruKaydet();
    final ogrenciler = await BireyselListeService.ogrenciler(_oturum!, sinif?.sinifSubeId);
    return RaporService.dinamikSinifListesi(sablon: sablon, ogrenciler: ogrenciler, bilgiler: bilgiler);
  }
  Widget _onIzleme() {
    if (_ogrenciler.isEmpty) return const Center(child: Text('Önce öğrenci importu yapın veya öğrencisi bulunan bir sınıf seçin.'));
    _pdf ??= _pdfHazirla();
    return FutureBuilder<Uint8List>(future: _pdf, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20),
        child: Text('PDF hazırlanamadı. Tasarım ayarlarını kontrol edin.\nOrijinal hata: ${snapshot.error}')));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final bytes = snapshot.data!;
      return PdfPreview(key: ValueKey('pdf-$_surum-${_sinif?.sinifSubeId ?? 0}'),
        build: (_) async => bytes, pdfFileName: 'sinif_listesi.pdf',
        initialPageFormat: _tasarim.yatay ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        canChangeOrientation: false, canChangePageFormat: false, canDebug: false,
        allowPrinting: true, allowSharing: true);
    });
  }
  @override
  Widget build(BuildContext context) {
    return OrtakSayfa(
      appBar: widget.sekmeIcinde ? null : ModulUstBar(title: const Text('Öğrencilerim'), actions: [
        if (_bolum == 1) IconButton(onPressed: _bekle ? null : _kaydet,
          tooltip: 'Şablonu kaydet', icon: const Icon(Icons.save_outlined)),
      ]),
      bottomNavigationBar: widget.sekmeIcinde || _klavyeAcik ? null : SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(children: [
            _altIslem(Icons.person_add_outlined, 'Öğrenci Ekle',
              _bekle || _oturum == null || _oturum!.siniflar.isEmpty ? null : _ogrenciEkle),
            _altIslem(Icons.file_upload_outlined, 'Öğrenci Aktar',
              _bekle ? null : () => _importAc()),
            _altIslem(Icons.add_photo_alternate_outlined, 'Fotoğraf',
              _bekle ? null : () => _importAc(fotograf: true)),
            _altIslem(Icons.delete_outline, 'Öğrenci Sil',
              _bekle || _bolum != 0 || _ogrenciler.isEmpty ? null : _ogrenciSil,
              tehlikeli: true),
          ]),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (widget.sekmeIcinde && !_klavyeAcik) _araclar(),
            Expanded(child: _icerik()),
          ],
        ),
      ),
    );
  }

  Future<void> _veliAc({bool excel = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VeliBilgileriScreen(excel: excel)));
    if (mounted) await _hazirla(secimiKoru: true);
  }

  void _seciliDetay() {
    if (_seciliOgrenciId == null) {
      _mesaj('Öğrenciyi seçmek için satırına uzun basın.');
      return;
    }
    _detayAc(_seciliOgrenciId!);
  }

  Future<void> _detayAc(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
      BireyselOgrenciBilgileriScreen(oturum: _oturum!, ogrenciId: id)));
    if (mounted) await _hazirla(secimiKoru: true);
  }

  Future<void> _aktarimMenusu() async {
    final secim = await showModalBottomSheet<String>(context: context, useSafeArea: true,
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('İçe Aktar')),
        ListTile(leading: const Icon(Icons.table_view), title: const Text('Öğrenci Excel dosyası'),
          onTap: () => Navigator.pop(c, 'ogrenci')),
        ListTile(leading: const Icon(Icons.add_photo_alternate_outlined), title: const Text('Fotoğraf aktar'),
          onTap: () => Navigator.pop(c, 'foto')),
        ListTile(leading: const Icon(Icons.family_restroom), title: const Text('Veli Excel İşlemleri'),
          onTap: () => Navigator.pop(c, 'veli')),
      ]));
    if (!mounted || secim == null) return;
    if (secim == 'veli') { await _veliAc(excel: true); }
    else { await _importAc(fotograf: secim == 'foto'); }
  }

  Widget _araclar() {
    final renk = Theme.of(context).colorScheme;
    final ogrenciVar = _oturum != null && _oturum!.siniflar.isNotEmpty;
    final silinebilir = _bolum == 0 && _ogrenciler.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: PopupMenuButton<String>(
          key: const ValueKey('ogrenci-islemler-menusu'),
          tooltip: 'Öğrenci işlemleri',
          enabled: !_bekle,
          onSelected: (secim) async {
            switch (secim) {
              case 'liste':
                _bolumSec(0);
                setState(() => _gorunum = 0);
              case 'kart':
                _bolumSec(0);
                setState(() => _gorunum = 1);
              case 'ekle':
                await _ogrenciEkle();
              case 'duzenle':
              case 'detay':
                _seciliDetay();
              case 'sil':
                _ogrenciSil();
              case 'yenile':
                await _hazirla(secimiKoru: true);
              case 'veli':
                await _veliAc();
              case 'aktar':
                await _aktarimMenusu();
              case 'fotograf':
                await _importAc(fotograf: true);
              case 'disa':
                _bolumSec(2);
              case 'rapor':
                _bolumSec(1);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'liste', child: ListTile(
                dense: true, leading: Icon(Icons.format_list_bulleted),
                title: Text('Öğrenci Listesi'))),
            const PopupMenuItem(value: 'kart', child: ListTile(
                dense: true, leading: Icon(Icons.badge_outlined),
                title: Text('Detay Kartları'))),
            PopupMenuItem(value: 'ekle', enabled: ogrenciVar,
                child: const ListTile(dense: true,
                    leading: Icon(Icons.person_add_alt_1_outlined),
                    title: Text('Öğrenci Ekle'))),
            const PopupMenuItem(value: 'duzenle', child: ListTile(
                dense: true, leading: Icon(Icons.edit_outlined),
                title: Text('Düzenle'))),
            PopupMenuItem(value: 'sil', enabled: silinebilir,
                child: ListTile(dense: true,
                    leading: Icon(Icons.delete_outline, color: renk.error),
                    title: Text('Sil', style: TextStyle(color: renk.error)))),
            const PopupMenuItem(value: 'yenile', child: ListTile(
                dense: true, leading: Icon(Icons.refresh),
                title: Text('Yenile'))),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'detay', child: ListTile(
                dense: true, leading: Icon(Icons.info_outline),
                title: Text('Öğrenci Detayı'))),
            const PopupMenuItem(value: 'veli', child: ListTile(
                dense: true, leading: Icon(Icons.groups_rounded),
                title: Text('Veli Bilgileri'))),
            const PopupMenuItem(value: 'aktar', child: ListTile(
                dense: true, leading: Icon(Icons.table_view),
                title: Text('İçe Aktar'))),
            const PopupMenuItem(value: 'fotograf', child: ListTile(
                dense: true, leading: Icon(Icons.add_photo_alternate_outlined),
                title: Text('Fotoğraf Aktar'))),
            const PopupMenuItem(value: 'disa', child: ListTile(
                dense: true, leading: Icon(Icons.picture_as_pdf_outlined),
                title: Text('Dışa Aktar / Yazdır'))),
            const PopupMenuItem(value: 'rapor', child: ListTile(
                dense: true, leading: Icon(Icons.bar_chart_rounded),
                title: Text('Raporlar / Tasarım'))),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: renk.outlineVariant),
              borderRadius: BorderRadius.circular(12),
              color: renk.surface,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.settings_outlined, size: 18, color: renk.primary),
              const SizedBox(width: 8),
              Text('İşlemler', style: TextStyle(
                fontWeight: FontWeight.w700, color: renk.onSurface)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: renk.onSurface),
            ]),
          ),
        ),
      ),
    );
  }

  void _ogrenciSil() {
    if (_bekle || _bolum != 0 || _ogrenciler.isEmpty) return;
    if (_seciliOgrenciId == null) {
      setState(() => _silmeSecimModu = true);
      _mesaj('Listeden çıkarılacak öğrenciyi seçin. Vazgeçmek için tekrar dokunun.');
      return;
    }
    final eslesen = _ogrenciler.where((o) => o['OgrenciId'] == _seciliOgrenciId).toList();
    if (eslesen.length == 1) {
      _ogrenciyiSiniftanCikar(eslesen.single);
    } else {
      setState(() { _seciliOgrenciId = null; _silmeSecimModu = false; });
      _mesaj('Seçili öğrenci bulunamadı. Listeyi yenileyin.');
    }
  }

  Widget _altIslem(IconData icon, String etiket, VoidCallback? tikla,
      {bool tehlikeli = false}) => Expanded(
    child: Tooltip(
      message: tehlikeli
          ? 'Öğrenci seçmek için liste satırına uzun basın. Geçmiş kayıtlar silinmez.'
          : etiket,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton(
          onPressed: tikla,
          style: TextButton.styleFrom(
            foregroundColor: tehlikeli ? Theme.of(context).colorScheme.error : null,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            OrtakBaslik(etiket, maxLines: 2, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10, letterSpacing: 0, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ),
  );

  int _sinifSeviyesi(String kod) => int.tryParse(RegExp(r'^\d+').stringMatch(kod) ?? '') ?? 0;

  Widget _sinifFiltreleri() {
    final seviye = _sinif == null ? 0 : _sinifSeviyesi(_sinif!.sinif);
    final seviyeler = _oturum!.siniflar.map((s) => _sinifSeviyesi(s.sinif)).toSet().toList()..sort();
    final stil = Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0);
    Widget alan(String etiket, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(etiket,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12, letterSpacing: 0))),
      child,
    ]);
    InputDecoration dekor() => const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9), constraints: BoxConstraints(minHeight: 44));
    return Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: LayoutBuilder(builder: (c, limits) {
      final sinif = alan('Sınıf', DropdownButtonFormField<int>(key: ValueKey('liste-seviye:$seviye'),
        initialValue: seviye, isExpanded: true, style: stil, iconSize: 18, decoration: dekor(),
        items: [const DropdownMenuItem(value: 0, child: Text('Tüm Sınıflar', maxLines: 1, overflow: TextOverflow.ellipsis)),
          for (final n in seviyeler) DropdownMenuItem(value: n, child: Text('$n. Sınıf'))],
        onChanged: (n) => _sinifSec(n == null || n == 0 ? 0 : _oturum!.siniflar.firstWhere((s) => _sinifSeviyesi(s.sinif) == n).sinifSubeId)));
      final sube = alan('Şube', DropdownButtonFormField<int>(key: ValueKey('liste-sube:${_sinif?.sinifSubeId}'),
        initialValue: _sinif?.sinifSubeId ?? 0, isExpanded: true, style: stil, iconSize: 18, decoration: dekor(),
        items: [const DropdownMenuItem(value: 0, child: Text('Tümü')),
          for (final s in _oturum!.siniflar.where((s) => seviye == 0 || _sinifSeviyesi(s.sinif) == seviye))
            DropdownMenuItem(value: s.sinifSubeId, child: Text(s.sinif, maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: _sinifSec));
      final durum = alan('Durum', InputDecorator(decoration: dekor(), child: Text('Aktif', style: stil)));
      final gerekli = (TextPainter(text: TextSpan(text: 'Tüm Sınıflar', style: stil),
        textDirection: Directionality.of(c), textScaler: MediaQuery.textScalerOf(c))..layout()).width + 42;
      if (gerekli > (limits.maxWidth - 16) * .44) {
        return Column(children: [sinif, const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: sube), const SizedBox(width: 8), Expanded(child: durum)])]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 44, child: sinif), const SizedBox(width: 8),
        Expanded(flex: 30, child: sube), const SizedBox(width: 8), Expanded(flex: 26, child: durum)]);
    }));
  }

  Widget _gorunumSecimi() {
    final s = Theme.of(context).colorScheme;
    return Container(key: const ValueKey('ogrenci-gorunumleri'),
      decoration: BoxDecoration(color: s.surface, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: s.outlineVariant)),
      child: Row(children: [for (var i = 0; i < 3; i++)
        Expanded(child: Semantics(selected: _gorunum == i, button: true, child: Material(color: Colors.transparent,
          child: InkWell(key: ValueKey('ogrenci-gorunum-$i'), borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => _gorunum = i),
            child: Ink(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
                gradient: _gorunum == i ? LinearGradient(colors: [Color.lerp(s.primary, Colors.cyan, .35)!, s.primary]) : null),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon([Icons.format_list_bulleted, Icons.grid_view_outlined, Icons.table_chart_outlined][i], size: 18,
                  color: _gorunum == i ? s.onPrimary : s.onSurfaceVariant),
                const SizedBox(width: 6), Flexible(child: Text(['Liste', 'Kart', 'Tablo'][i], maxLines: 1,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, letterSpacing: 0,
                    fontWeight: _gorunum == i ? FontWeight.w700 : FontWeight.w500, color: _gorunum == i ? s.onPrimary : s.onSurface))),
              ])),
          )))),
      ]));
  }

  Widget _icerik() => _bekle ? const Center(child: CircularProgressIndicator()) : _hata != null
        ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_hata!), TextButton(onPressed: _hazirla, child: const Text('Yeniden Dene'))])))
        : _oturum == null || _oturum!.siniflar.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(20),
              child: Text('Önce Ders Programım kartından ders programınızı yükleyin. '
                  'Ardından buradan öğrenci importu yapabilirsiniz.', textAlign: TextAlign.center)))
          : Column(children: [
              if (widget.sekmeIcinde) _sinifFiltreleri() else
              Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<int>(
                key: ObjectKey(_oturum),
                initialValue: _sinif?.sinifSubeId ?? 0, isExpanded: true, decoration: const InputDecoration(labelText: 'Sınıf'),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Tüm Sınıflar', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  for (final s in _oturum!.siniflar)
                    DropdownMenuItem(value: s.sinifSubeId, child: Text(s.sinif, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _sinifSec)),
              if (!widget.sekmeIcinde || _bolum != 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Wrap(spacing: 8, children: [
                for (var i = 0; i < 3; i++) ChoiceChip(label: Text(['Liste', 'Tasarım', 'Yazdır'][i]),
                  selected: _bolum == i, onSelected: (_) => _bolumSec(i)),
              ])),
              const SizedBox(height: 8),
              Expanded(child: _bolum == 0 ? _liste() : _bolum == 1
                ? LayoutBuilder(builder: (_, c) => c.maxWidth >= 900
                  ? Row(children: [SizedBox(width: 420, child: _tasarimAlani()),
                      Expanded(child: _onIzleme())]) : _tasarimAlani()) : _onIzleme()),
            ]);
  Widget _listeOzeti(int adet) => LayoutBuilder(builder: (context, limits) {
    final stil = Theme.of(context).textTheme.titleMedium!.copyWith(
      fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -.4);
    final siraStili = Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11, letterSpacing: 0);
    final sayac = Text('$adet öğrenci', maxLines: 1, style: stil);
    final siralama = TextButton(onPressed: () => setState(() => _artan = !_artan),
      style: TextButton.styleFrom(minimumSize: const Size(48, 36), padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Sırala: Ad Soyad', style: siraStili),
        const SizedBox(width: 4), Icon(_artan ? Icons.arrow_upward : Icons.arrow_downward, size: 14)]));
    double olc(String metin, TextStyle style) => (TextPainter(text: TextSpan(text: metin, style: style),
      textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))..layout()).width;
    if (olc('$adet öğrenci', stil) + olc('Sırala: Ad Soyad', siraStili) + 30 > limits.maxWidth) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [sayac, Align(alignment: Alignment.centerRight, child: siralama)]);
    }
    return Row(children: [Expanded(child: sayac), siralama]);
  });

  Widget _liste() {
    final filtre = _ogrenciArama.trim().toLowerCase();
    final gorunenler = _ogrenciler.where((o) => filtre.isEmpty ||
      '${o['Ad']} ${o['Soyad']} ${o['OkulNo']}'.toLowerCase().contains(filtre)).toList();
    if (widget.sekmeIcinde) gorunenler.sort((a, b) {
      final n = '${a['Ad']} ${a['Soyad']}'.compareTo('${b['Ad']} ${b['Soyad']}');
      return _artan ? n : -n;
    });
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, widget.sekmeIcinde ? 2 : 8), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.sekmeIcinde) ...[
            _gorunumSecimi(), const SizedBox(height: 10),
            _listeOzeti(gorunenler.length),
          ] else Text('${gorunenler.length} öğrenci', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          TextField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, letterSpacing: 0),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search),
              isDense: true, contentPadding: widget.sekmeIcinde ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : null,
              prefixIconConstraints: widget.sekmeIcinde ? const BoxConstraints(minWidth: 40, minHeight: 40) : null,
              hintText: 'Ad, soyad veya okul no ara'), onChanged: (v) => setState(() => _ogrenciArama = v)),
          if (!widget.sekmeIcinde) const SizedBox(height: 8),
          if (!widget.sekmeIcinde) FilledButton.icon(onPressed: _ogrenciler.isEmpty ? null : () => _bolumSec(1),
            icon: const Icon(Icons.print_outlined), label: const Text('Liste Tasarla / Yazdır')),
        ]))),
      if (gorunenler.isEmpty) SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(
        _ogrenciler.isNotEmpty ? 'Arama sonucu yok.' : _sinif == null
          ? 'Önce Öğrenci Import ile öğrencilerinizi yükleyin; ardından fotoğrafları eşleştirin.'
          : 'Bu sınıf için önce Öğrenci Import yapın.')))
      else if (_gorunum == 2) SliverToBoxAdapter(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: DataTable(columns: const [DataColumn(label: Text('Okul No')),
          DataColumn(label: Text('Ad Soyad')), DataColumn(label: Text('Sınıf/Şube'))],
          rows: [for (final o in gorunenler) DataRow(
            selected: o['OgrenciId'] == _seciliOgrenciId,
            onSelectChanged: (_) => setState(() => _seciliOgrenciId = o['OgrenciId'] as int),
            onLongPress: () => _detayAc(o['OgrenciId'] as int),
            cells: [DataCell(Text('${o['OkulNo']}')), DataCell(Text('${o['Ad']} ${o['Soyad']}')),
              DataCell(Text('${o['SinifKodu']}'))])])) )
      else SliverList.builder(itemCount: gorunenler.length, itemBuilder: (_, i) => _ogrenciSatiri(gorunenler[i])),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ]);
  }

  Widget _ogrenciSatiri(Map<String, Object?> o) {
    final secili = o['OgrenciId'] == _seciliOgrenciId;
    return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: widget.sekmeIcinde ? .7 : 0,
      shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: .1),
      color: secili ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
      child: ListTile(selected: secili, isThreeLine: _gorunum == 1, dense: widget.sekmeIcinde,
        minTileHeight: widget.sekmeIcinde && _gorunum == 0 ? 56 : null,
        minVerticalPadding: widget.sekmeIcinde ? 4 : null,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.sekmeIcinde ? 0 : 4),
        onLongPress: () => setState(() {
          _silmeSecimModu = true;
          _seciliOgrenciId = secili ? null : o['OgrenciId'] as int;
        }),
        leading: OgrenciFotoWidget(fotoYolu: o['DosyaYolu'] as String?,
          fotoVerisi: o['FotoVerisi'] as Uint8List?, yerel: true, width: 40, height: 40),
        trailing: widget.sekmeIcinde ? Icon(Icons.chevron_right, size: 22,
          color: Theme.of(context).colorScheme.onSurface) : PopupMenuButton<String>(tooltip: 'Öğrenci işlemleri',
          onSelected: (v) { if (v == 'cikar') _ogrenciyiSiniftanCikar(o); },
          itemBuilder: (_) => const [PopupMenuItem(value: 'cikar', child: ListTile(
            dense: true, leading: Icon(Icons.person_remove_outlined), title: Text('Listeden çıkar')))]),
        onTap: () {
          if (_silmeSecimModu) { setState(() {
            _seciliOgrenciId = secili ? null : o['OgrenciId'] as int;
            if (_seciliOgrenciId == null) _silmeSecimModu = false;
          }); } else { _detayAc(o['OgrenciId'] as int); }
        },
        title: Text('${o['Ad']} ${o['Soyad']}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: 0)),
        subtitle: Text('Sınıf: ${o['SinifKodu']} • No: ${o['OkulNo']}${_gorunum == 1 ? '\nCinsiyet: ${o['Cinsiyet'] ?? "Belirtilmedi"}' : ""}',
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.2, letterSpacing: 0))));
  }
  Widget _tasarimAlani() => ListView(padding: const EdgeInsets.all(12), children: [
    DropdownButtonFormField<String>(key: ValueKey('sablon-$_surum'), isExpanded: true,
      decoration: const InputDecoration(labelText: 'Hazır veya kayıtlı şablon seç'),
      items: [
        for (var i = 0; i < RaporSablonu.hazirSablonlar().length; i++) DropdownMenuItem(value: 'h$i', child: Text(RaporSablonu.hazirSablonlar()[i].ad)),
        for (var i = 0; i < _kayitli.length; i++) DropdownMenuItem(value: 'k$i', child: Text('Kaydım: ${_kayitli[i].ad}')),
      ], onChanged: (v) {
        if (v != null) {
          _degistir(() {
            _tasarim = (v.startsWith('h') ? RaporSablonu.hazirSablonlar() : _kayitli)[int.parse(v.substring(1))].kopya();
            _ortakTasarimiHazirla();
            _sinifSutununuHazirla();
          });
        }
      }),
    const SizedBox(height: 12),
    Text('Tasarım: ${_tasarim.ad}', style: const TextStyle(fontWeight: FontWeight.bold)),
    OrtakGenisleyenBolum(title: const Text('Başlıklar'), initiallyExpanded: true, children: [
      TextField(controller: _okul, decoration: const InputDecoration(labelText: 'Okul adı'), maxLength: 160,
        onChanged: (_) => _metinDegisti()),
      TextField(controller: _ogretmen, decoration: const InputDecoration(labelText: 'Öğretmen'), maxLength: 160,
        onChanged: (_) => _metinDegisti()),
      DropdownButtonFormField<String>(
        key: ValueKey('liste-ders-secimi-${_sinif?.sinifSubeId ?? 0}-${_dersElle ? '__elle__' : _ders.text}'),
        initialValue: _dersElle ? '__elle__' : _ders.text,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Ders seçimi'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Ders seçilmedi')),
          for (final ders in _dersSecenekleri)
            DropdownMenuItem(value: ders, child: Text(ders, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const DropdownMenuItem(value: '__elle__', child: Text('Elle yaz')),
        ],
        onChanged: (v) {
          if (v == null) return;
          _degistir(() { _dersElle = v == '__elle__'; _ders.text = _dersElle ? '' : v; });
        },
      ),
      if (_dersElle) TextField(controller: _ders, decoration: const InputDecoration(labelText: 'Ders'), maxLength: 160,
        onChanged: (_) => _metinDegisti()),
      TextField(controller: _mudur, maxLength: 160,
        decoration: const InputDecoration(labelText: 'Okul müdürü',
          helperText: 'Bu okul için cihazınızda hatırlanır.', helperMaxLines: 2),
        onChanged: (_) => _mudurDegisti()),
    ]),
    RaporTasarimEditoru(
      key: ObjectKey(_ortakTasarim),
      tanim: OgrenciRaporUyarlayici.tanim(_tasarim),
      tasarim: _ortakTasarim,
      veri: OgrenciRaporUyarlayici.veri(_tasarim, _ogrenciler, _raporBilgileri),
      onDegistir: _ortakDegistir,
      onMetinDegisti: _metinDegisti,
    ),
    Wrap(spacing: 8, children: [
      OutlinedButton.icon(onPressed: _kaydet, icon: const Icon(Icons.save_outlined), label: const Text('Şablonu Kaydet')),
      FilledButton.icon(onPressed: () => setState(() { _pdf = null; _bolum = 2; }),
        icon: const Icon(Icons.preview_outlined), label: const Text('Ön İzle / Yazdır')),
    ]),
    const SizedBox(height: 24),
  ]);
}
