import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bireysel_belge.dart';
import '../services/bireysel_belge_service.dart';
import '../services/baslangic_belgeleri_service.dart';
import '../models/ortak_import.dart';
import '../services/belge_analiz_service.dart';
import '../services/belge_disari_aktar_service.dart';
import '../services/ogrenci_import_tanimi.dart';
import '../services/fotograf_import_tanimi.dart';
import 'ortak_import_screen.dart';
import 'bireysel_ders_programi_import_screen.dart';
import 'bireysel_yillik_plan_import_screen.dart';
import 'belge_veri_rehberi_screen.dart';
import 'belge_on_izleme_screen.dart';
import 'ders_belgeleri_screen.dart';

class BireyselBelgelerimScreen extends StatefulWidget {
  const BireyselBelgelerimScreen({
    super.key,
    this.service,
    this.secimUzantilari,
  });
  final BireyselBelgeService? service;
  final Set<String>? secimUzantilari;

  @override
  State<BireyselBelgelerimScreen> createState() =>
      _BireyselBelgelerimScreenState();
}

class _BireyselBelgelerimScreenState extends State<BireyselBelgelerimScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? BireyselBelgeService.instance;
  final _arama = TextEditingController();
  Timer? _aramaBekleme;
  BelgeArsivListesi? _arsivler;
  String? _arsivId, _hata;
  List<BireyselBelge> _belgeler = [];
  bool _yukleniyor = true, _islem = false, _devamiVar = false;
  int _istek = 0;
  double? _ilerleme;
  String _islemMetni = '';
  List<BelgeKlasoru> _klasorler = [];
  List<String> _yillar = [];
  String? _klasorId, _tur, _yil;
  bool _tumKlasorler = true, _copKutusu = false;
  bool _rehberOner = false;
  bool get _secimModu => widget.secimUzantilari != null;

  bool get _eskiArsiv => _arsivId != _arsivler?.aktif.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _yenile();
  }

  @override
  void dispose() {
    _istek++;
    WidgetsBinding.instance.removeObserver(this);
    _aramaBekleme?.cancel();
    _arama.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_islem) _yenile();
  }

  Future<void> _yenile() async {
    final istek = ++_istek;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final arsivler = await _service.arsivleriGetir();
      if (widget.service == null) {
        await BaslangicBelgeleriService.instance.yukle(
          _service,
          arsivler.aktif.id,
        );
      }
      if (!mounted || istek != _istek) return;
      final secili = arsivler.arsivler.any((a) => a.id == _arsivId)
          ? _arsivId!
          : arsivler.aktif.id;
      setState(() {
        _arsivler = arsivler;
        _arsivId = secili;
      });
      final klasorler = await _service.klasorleriGetir(secili);
      final yillar = await _service.yillariGetir(secili);
      final prefs = widget.service == null && !_secimModu
          ? await SharedPreferences.getInstance()
          : null;
      if (!mounted || istek != _istek) return;
      setState(() {
        _klasorler = klasorler;
        _yillar = yillar;
        if (!_klasorler.any((k) => k.id == _klasorId)) _klasorId = null;
        if (!_yillar.contains(_yil)) _yil = null;
        _rehberOner =
            prefs != null &&
            prefs.getBool('belge_rehber_${arsivler.aktif.id}') != true;
      });
      await _listeYukle();
    } catch (e) {
      if (mounted && istek == _istek) {
        setState(() {
          _belgeler = [];
          _hata = 'Belgeler okunamadı.\nOrijinal hata: $e';
          _yukleniyor = false;
        });
      }
    }
  }

  Future<void> _listeYukle({bool devam = false}) async {
    final arsiv = _arsivId;
    if (arsiv == null) return;
    final istek = ++_istek;
    final offset = devam ? _belgeler.length : 0;
    setState(() {
      _yukleniyor = true;
      _hata = null;
      if (!devam) _belgeler = [];
    });
    try {
      final rows = await _service.listele(
        arsivId: arsiv,
        arama: _arama.text,
        offset: offset,
        klasorId: _klasorId,
        tumKlasorler: _tumKlasorler,
        tur: _tur,
        yil: _yil,
        copKutusu: _copKutusu,
      );
      if (!mounted || istek != _istek) return;
      setState(() {
        _belgeler = devam ? [..._belgeler, ...rows] : rows;
        _devamiVar = rows.length == 50;
      });
    } catch (e) {
      if (mounted && istek == _istek) {
        setState(() => _hata = 'Belgeler listelenemedi.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted && istek == _istek) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ekle() async {
    if (_islem || _yukleniyor || _eskiArsiv || _arsivId == null) return;
    _aramaBekleme?.cancel();
    setState(() {
      _islem = true;
      _hata = null;
      _ilerleme = null;
      _islemMetni = 'Dosya seçiliyor...';
    });
    try {
      final secim = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: BireyselBelgeService.uzantilar.toList(),
        withData: false,
        withReadStream: true,
      );
      if (!mounted || secim == null || secim.files.isEmpty) return;
      setState(() => _islemMetni = 'Belge ekleniyor...');
      final sonuc = await _service.ekle(
        arsivId: _arsivId!,
        dosya: secim.files.single,
        klasorId: _klasorId,
        ilerleme: (okunan, toplam) {
          final oran = okunan / toplam;
          if (mounted &&
              (_ilerleme == null ||
                  (oran * 100).floor() != (_ilerleme! * 100).floor())) {
            setState(() {
              _ilerleme = oran;
              if (okunan == toplam) _islemMetni = 'Dosya kontrol ediliyor...';
            });
          }
        },
      );
      if (!mounted) return;
      if (!sonuc.zatenVar) {
        try {
          setState(() => _islemMetni = 'Belge türü analiz ediliyor...');
          await _analizEt(sonuc.belge);
        } catch (e) {
          if (mounted) {
            setState(
              () => _hata =
                  'Belge eklendi; analiz tamamlanamadı.\nOrijinal hata: $e',
            );
          }
        }
      }
      _arama.clear();
      await _yenile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sonuc.zatenVar
                  ? 'Bu dosya zaten kayıtlı: ${sonuc.belge.dosyaAdi}'
                  : 'Belge eklendi: ${sonuc.belge.dosyaAdi}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Belge eklenemedi.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _islem = false;
          _ilerleme = null;
        });
      }
    }
  }

  Future<void> _ac(BireyselBelge belge, {bool harici = false}) async {
    if (_islem || _yukleniyor) return;
    _aramaBekleme?.cancel();
    setState(() {
      _islem = true;
      _hata = null;
      _ilerleme = null;
      _islemMetni = 'Belge açılıyor...';
    });
    try {
      final yol = await _service.acmaYolunuGetir(
        arsivId: belge.arsivId,
        belgeId: belge.id,
      );
      if (!harici && BelgeOnIzlemeScreen.uzantilar.contains(belge.uzanti)) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BelgeOnIzlemeScreen(
              yol: yol,
              ad: belge.dosyaAdi,
              uzanti: belge.uzanti,
            ),
          ),
        );
        return;
      }
      final sonuc = await OpenFile.open(yol);
      if (sonuc.type != ResultType.done) {
        throw StateError(
          'Belge açılamadı. Cihazda bu dosya türünü açan bir '
          'uygulama bulunduğunu kontrol edin.\nOrijinal hata: ${sonuc.message}',
        );
      }
    } catch (e) {
      if (mounted) {
        await _listeYukle();
        if (mounted) {
          setState(() => _hata = 'Belge açılamadı.\nOrijinal hata: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _calistir(String metin, Future<void> Function() action) async {
    if (_islem || _yukleniyor) return;
    _aramaBekleme?.cancel();
    setState(() {
      _islem = true;
      _hata = null;
      _ilerleme = null;
      _islemMetni = metin;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'İşlem tamamlanamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<String?> _adSor(String baslik, String mevcut) async {
    final c = TextEditingController(text: mevcut);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(baslik),
          content: TextField(controller: c, autofocus: true, maxLength: 240),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    }
  }

  Future<void> _klasorDuzenle([BelgeKlasoru? klasor]) =>
      _calistir('Klasör düzenleniyor...', () async {
        final ad = await _adSor(
          klasor == null ? 'Klasör Oluştur' : 'Klasör Adını Değiştir',
          klasor?.ad ?? '',
        );
        if (ad == null) return;
        await _service.klasorKaydet(_arsivId!, ad, id: klasor?.id);
        if (mounted) await _yenile();
      });

  Future<void> _analizEt(BireyselBelge belge, {bool yeniden = false}) async {
    if (!yeniden && BelgeAnalizi.fromJson(belge.analiz) != null) return;
    final yol = await _service.dosyaYolunuGetir(
      arsivId: belge.arsivId,
      belgeId: belge.id,
    );
    final analiz = await BelgeAnalizService.analizEt(
      ImportDosya(belge.dosyaAdi, await File(yol).readAsBytes()),
    );
    await _service.analizKaydet(belge, analiz.toJson(), analiz.tur);
  }

  Future<ImportDosya> _importDosyasi(BireyselBelge belge) async {
    final kaynak = await _service.importKaynaginiGetir(belge);
    final yol = await _service.dosyaYolunuGetir(
      arsivId: belge.arsivId,
      belgeId: belge.id,
    );
    final file = ImportDosya(
      belge.dosyaAdi,
      await File(yol).readAsBytes(),
      belgeKaynagi: kaynak,
    );
    await _service.importKapsaminiDogrula(kaynak);
    return file;
  }

  Future<void> _sec(BireyselBelge belge) =>
      _calistir('Dosya import için hazırlanıyor...', () async {
        if (!belge.acilabilir ||
            !widget.secimUzantilari!.contains(belge.uzanti)) {
          throw StateError(
            'Bu dosya türü seçilen import modülünde desteklenmiyor.',
          );
        }
        final file = await _importDosyasi(belge);
        if (!mounted) return;
        setState(() => _islem = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, file);
      });

  Future<void> _importEt(
    BireyselBelge belge,
  ) => _calistir('Import hazırlanıyor...', () async {
    final secenekler = <String, String>{
      if (const {'xls', 'xlsx', 'csv'}.contains(belge.uzanti))
        'ogrenci': 'Öğrenci Listesi',
      if (belge.uzanti == 'xls') 'fotograf': 'Öğrenci Fotoğrafları',
      if (const {'xls', 'xlsx', 'csv'}.contains(belge.uzanti))
        'program': 'Ders Programı',
      if (const {'xls', 'xlsx', 'csv', 'doc', 'docx'}.contains(belge.uzanti))
        'plan': 'Yıllık Plan',
    };
    if (secenekler.isEmpty) {
      throw StateError(
        'Bu belge saklanıp açılabilir. Mevcut bireysel import okuyucuları bu biçimi desteklemiyor.',
      );
    }
    final secim = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Hedef Import Modülü'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Belge türü: ${belge.belgeTuru}\nİçerik, seçtiğiniz modülün ön izlemesinde doğrulanacak.',
            ),
          ),
          for (final e in secenekler.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Text(e.value),
            ),
        ],
      ),
    );
    if (secim == null || !mounted) return;
    final file = await _importDosyasi(belge);
    if (!mounted) return;
    final ogrenciKayitAkisi = OgrenciImportKayitAkisi();
    final Widget ekran = switch (secim) {
      'ogrenci' => OrtakImportScreen(
        tanim: OgrenciImportTanimi.tanim,
        baslangicDosyasi: file,
        secimOnayi: ogrenciKayitAkisi.onayla,
        secimiKaydet: ogrenciKayitAkisi.kaydet,
        bosSecimleAktarilabilir: ogrenciKayitAkisi.bosSecimleAktarilabilir,
        sonucIleDon: false,
      ),
      'fotograf' => OrtakImportScreen(
        tanim: FotografImportTanimi.tanim,
        baslangicDosyasi: file,
        kayitGorseli: FotografImportTanimi.gorsel,
        ozelOnIzlemeyiHazirla: FotografImportTanimi.onIzlemeyiHazirla,
        alternatifOnIzlemeyiHazirla: FotografImportTanimi.hucrelerdenOnIzlemeyiHazirla,
        alternatifOnIzlemeAdi: 'Excel Hücrelerinden Elle Eşleştir',
      ),
      'program' => BireyselDersProgramiImportScreen(baslangicDosyasi: file),
      _ => BireyselYillikPlanImportScreen(baslangicDosyasi: file),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ekran));
    if (mounted) await _yenile();
  });

  Future<void> _detay(
    BireyselBelge belge,
  ) => _calistir('Belge bilgileri okunuyor...', () async {
    final gecmis = await _service.gecmis(belge);
    final analiz = BelgeAnalizi.fromJson(belge.analiz);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(belge.dosyaAdi),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${belge.belgeTuru}\n${belge.egitimOgretimYili}\n${_boyut(belge.boyut)}',
                ),
                const SizedBox(height: 12),
                Text(
                  analiz?.aciklama ??
                      'Henüz içerik analizi yapılmadı. Menüden Analiz Et seçebilirsiniz.',
                ),
                if (analiz != null && analiz.adaylar.length > 1)
                  Text('Adaylar: ${analiz.adaylar.join(', ')}'),
                const Divider(),
                const Text(
                  'Import Geçmişi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Geçmiş işlemleri gösterir; veritabanındaki kayıtların bugünkü durumunu göstermez.',
                ),
                if (gecmis.isEmpty) const Text('Henüz aktarım kaydı yok.'),
                for (final g in gecmis)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'İçe aktarıldı • ${g.modul}\n${DateFormat('dd.MM.yyyy HH:mm').format(g.tarih.toLocal())} • ${g.yil}\n'
                      'Eklenen: ${g.eklenen} • Güncellenen: ${g.guncellenen}\n${g.mesaj}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  });

  Future<void> _belgeIslemi(BireyselBelge belge, String islem) async {
    if (islem == 'import') return _importEt(belge);
    if (islem == 'detay') return _detay(belge);
    if (islem == 'ac') return _ac(belge, harici: true);
    await _calistir('Belge işlemi sürüyor...', () async {
      if (islem == 'ad') {
        final ad = await _adSor('Dosya Adını Değiştir', belge.dosyaAdi);
        if (ad != null) await _service.belgeyiDuzenle(belge, ad: ad);
      } else if (islem == 'tur') {
        final tur = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Belge Türü'),
            children: [
              for (final t in BireyselBelgeService.belgeTurleri)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, t),
                  child: Text(t),
                ),
            ],
          ),
        );
        if (tur != null) await _service.belgeyiDuzenle(belge, tur: tur);
      } else if (islem == 'tasi') {
        final id = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Hedef Klasör'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('Ana Dizin'),
              ),
              for (final k in _klasorler)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, k.id),
                  child: Text(k.ad),
                ),
            ],
          ),
        );
        if (id != null) {
          await _service.belgeyiDuzenle(
            belge,
            tasi: true,
            klasorId: id.isEmpty ? null : id,
          );
        }
      } else if (islem == 'sil') {
        final onay = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Çöp Kutusuna Taşı'),
            content: Text(
              '${belge.dosyaAdi}\nBelge listeden kaldırılacak. Çöp kutusundan geri alabilirsiniz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Çöp Kutusuna Taşı'),
              ),
            ],
          ),
        );
        if (onay == true) await _service.belgeyiDuzenle(belge, sil: true);
      } else if (islem == 'geri') {
        await _service.belgeyiDuzenle(belge, sil: false);
      } else if (islem == 'kalici') {
        final onay = await _adSor(
          'Kalıcı Silme • Geri Alınamaz\n${belge.dosyaAdi}\nOnay için SİL yazın',
          '',
        );
        if (onay == null) return;
        await _service.kaliciSil(belge, onay: onay);
      } else if (islem == 'analiz') {
        await _analizEt(belge, yeniden: true);
      } else if (islem == 'paylas') {
        final yol = await _service.acmaYolunuGetir(
          arsivId: belge.arsivId,
          belgeId: belge.id,
        );
        await BelgeDisariAktarService.paylas(yol, belge.dosyaAdi);
      }
      if (mounted) await _yenile();
    });
  }

  Widget _belgeMenusu(BireyselBelge belge) => PopupMenuButton<String>(
    tooltip: 'Belge İşlemleri',
    enabled: !_islem && !_yukleniyor,
    onSelected: (action) => _belgeIslemi(belge, action),
    itemBuilder: (_) => [
      const PopupMenuItem(
        value: 'detay',
        child: Text('Bilgiler ve Import Geçmişi'),
      ),
      if (belge.acilabilir)
        const PopupMenuItem(value: 'ac', child: Text('Dış Uygulamada Aç')),
      if (belge.acilabilir)
        const PopupMenuItem(
          value: 'paylas',
          child: Text('Paylaş / Dışa Aktar'),
        ),
      if (!_eskiArsiv && !_copKutusu) ...[
        if (belge.acilabilir)
          const PopupMenuItem(value: 'import', child: Text('İçe Aktar')),
        const PopupMenuItem(value: 'ad', child: Text('Adını Değiştir')),
        const PopupMenuItem(value: 'tur', child: Text('Türünü Değiştir')),
        const PopupMenuItem(value: 'tasi', child: Text('Klasöre Taşı')),
        if (belge.acilabilir)
          const PopupMenuItem(
            value: 'analiz',
            child: Text('İçeriği Analiz Et'),
          ),
        const PopupMenuItem(value: 'sil', child: Text('Çöp Kutusuna Taşı')),
      ],
      if (!_eskiArsiv && _copKutusu)
        const PopupMenuItem(value: 'geri', child: Text('Geri Al')),
      if (!_eskiArsiv && _copKutusu)
        const PopupMenuItem(
          value: 'kalici',
          child: Text('Kalıcı Sil • Onay için SİL yazın'),
        ),
    ],
  );

  Widget _filtreler() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: OrtakGenisleyenBolum(
      title: Text(
        'Filtreler${_tur != null || _yil != null || !_tumKlasorler ? ' • Etkin' : ''}',
      ),
      children: [
        SizedBox(
          height: 210,
          child: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('klasor:$_arsivId:$_klasorId:$_tumKlasorler'),
                  initialValue: _tumKlasorler ? '*' : _klasorId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Klasör'),
                  items: [
                    const DropdownMenuItem(
                      value: '*',
                      child: Text('Tüm Klasörler'),
                    ),
                    const DropdownMenuItem(value: '', child: Text('Ana Dizin')),
                    for (final k in _klasorler)
                      DropdownMenuItem(
                        value: k.id,
                        child: Text(k.ad, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _islem
                      ? null
                      : (id) {
                          setState(() {
                            _tumKlasorler = id == '*';
                            _klasorId = id == '*' || id == '' ? null : id;
                          });
                          _listeYukle();
                        },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _tur ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Belge Türü'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Tümü')),
                    for (final t in BireyselBelgeService.belgeTurleri)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: _islem
                      ? null
                      : (t) {
                          setState(() => _tur = t == '' ? null : t);
                          _listeYukle();
                        },
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('yil:$_arsivId:$_yil'),
                  initialValue: _yil ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Eğitim Yılı'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Tümü')),
                    for (final y in _yillar)
                      DropdownMenuItem(value: y, child: Text(y)),
                  ],
                  onChanged: _islem
                      ? null
                      : (y) {
                          setState(() => _yil = y == '' ? null : y);
                          _listeYukle();
                        },
                ),
                if (!_secimModu && !_eskiArsiv && _klasorId != null)
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: _islem
                            ? null
                            : () => _klasorDuzenle(
                                _klasorler.firstWhere((k) => k.id == _klasorId),
                              ),
                        child: const Text('Klasör Adını Değiştir'),
                      ),
                      TextButton(
                        onPressed: _islem
                            ? null
                            : () =>
                                  _calistir('Klasör kaldırılıyor...', () async {
                                    await _service.klasorSil(
                                      _arsivId!,
                                      _klasorId!,
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _klasorId = null;
                                        _tumKlasorler = true;
                                      });
                                      await _yenile();
                                    }
                                  }),
                        child: const Text('Klasörü Kaldır • Belgeler Korunur'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  IconData _simge(String uzanti) => switch (uzanti) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'xls' || 'xlsx' || 'csv' || 'ods' => Icons.table_chart_outlined,
    'jpg' || 'jpeg' || 'png' => Icons.image_outlined,
    _ => Icons.description_outlined,
  };

  String _boyut(int value) => value >= 1024 * 1024
      ? '${(value / (1024 * 1024)).toStringAsFixed(1)} MB'
      : value >= 1024
      ? '${(value / 1024).toStringAsFixed(1)} KB'
      : '$value B';

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_islem,
    child: OrtakSayfa(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: ModulUstBar(
        title: Text(_secimModu ? 'Belgelerimden Seç' : 'Belgelerim'),
        actions: [
          if (!_secimModu)
            IconButton(
              tooltip: 'Veri Hazırlama Rehberi',
              onPressed: _islem
                  ? null
                  : () async {
                      await Navigator.of(this.context).push(
                        MaterialPageRoute(
                          builder: (_) => const BelgeVeriRehberiScreen(),
                        ),
                      );
                      if (mounted) _yenile();
                    },
              icon: const Icon(Icons.checklist),
            ),
          if (!_secimModu && !_eskiArsiv)
            PopupMenuButton<String>(
              enabled: !_islem && !_yukleniyor,
              onSelected: (action) {
                if (action == 'klasor') _klasorDuzenle();
                if (action == 'cop') {
                  setState(() => _copKutusu = !_copKutusu);
                  _listeYukle();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'klasor',
                  child: Text('Klasör Oluştur'),
                ),
                PopupMenuItem(
                  value: 'cop',
                  child: Text(_copKutusu ? 'Belgelere Dön' : 'Çöp Kutusu'),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Yenile',
            onPressed: _islem || _yukleniyor ? null : _yenile,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton:
          _arsivler == null || _eskiArsiv || _secimModu || _copKutusu
          ? null
          : FloatingActionButton.extended(
              onPressed: _islem || _yukleniyor ? null : _ekle,
              icon: const Icon(Icons.add),
              label: const Text('Belge Ekle'),
            ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .60,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (_arsivler != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: _arsivler!.arsivler.length == 1
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _arsivler!.aktif.okulAdi,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                )
                              : DropdownButtonFormField<String>(
                                  key: ValueKey(_arsivId),
                                  initialValue: _arsivId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Belge arşivi',
                                  ),
                                  items: [
                                    for (final a in _arsivler!.arsivler)
                                      DropdownMenuItem(
                                        value: a.id,
                                        child: Text(
                                          '${a.id == _arsivler!.aktif.id ? 'Güncel' : 'Önceki'} • '
                                          '${a.okulAdi} • ${a.ogretmenAdi}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: _islem || _yukleniyor || _secimModu
                                      ? null
                                      : (id) {
                                          if (id == null) return;
                                          _aramaBekleme?.cancel();
                                          _arama.clear();
                                          setState(() {
                                            _arsivId = id;
                                            _klasorId = null;
                                            _tumKlasorler = true;
                                            _yil = null;
                                            _copKutusu = false;
                                          });
                                          _yenile();
                                        },
                                ),
                        ),
                      if (_eskiArsiv && _arsivler != null)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            'Önceki kurulumun belgeleri korunmuştur. Bu arşiv yalnız '
                            'görüntülenir; güncel okulun belgeleriyle birleştirilmez.',
                          ),
                        ),
                      if (_copKutusu)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Çöp kutusu • Belgeler geri alınabilir; dosyalar korunur.',
                          ),
                        ),
                      if (_rehberOner && !_secimModu)
                        MaterialBanner(
                          content: const Text(
                            'Verilerinizi hazırlamak için isteğe bağlı rehberi kullanabilirsiniz.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool(
                                  'belge_rehber_${_arsivler!.aktif.id}',
                                  true,
                                );
                                if (mounted) {
                                  setState(() => _rehberOner = false);
                                }
                              },
                              child: const Text('Kapat'),
                            ),
                            TextButton(
                              onPressed: () async {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool(
                                  'belge_rehber_${_arsivler!.aktif.id}',
                                  true,
                                );
                                if (!mounted) return;
                                setState(() => _rehberOner = false);
                                await Navigator.of(this.context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const BelgeVeriRehberiScreen(),
                                  ),
                                );
                                if (mounted) _yenile();
                              },
                              child: const Text('Rehberi Aç'),
                            ),
                          ],
                        ),
                      if (_arsivler != null && !_secimModu && !_eskiArsiv && !_copKutusu)
                        ListTile(
                          leading: const Icon(Icons.folder_copy_outlined),
                          title: const Text('Ders Belgelerim'),
                          subtitle: const Text('Derslere göre: Yıllık Plan → Günlük Plan → Ders Bilgi Formu'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _islem || _yukleniyor ? null : () async {
                            await Navigator.of(context).push<void>(MaterialPageRoute(
                              builder: (_) => const DersBelgeleriScreen()));
                            if (mounted) _yenile();
                          },
                        ),
                      if (_arsivler != null) _filtreler(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _arama,
                          enabled: !_islem && _arsivler != null,
                          decoration: InputDecoration(
                            hintText: 'Belge ara',
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: 'Aramayı temizle',
                              onPressed: _islem
                                  ? null
                                  : () {
                                      _aramaBekleme?.cancel();
                                      _arama.clear();
                                      _listeYukle();
                                    },
                              icon: const Icon(Icons.clear),
                            ),
                          ),
                          onChanged: (_) {
                            _aramaBekleme?.cancel();
                            _istek++; // Önceki aramanın geciken cevabı yeni sonuçları ezmez.
                            _aramaBekleme = Timer(
                              const Duration(milliseconds: 300),
                              _listeYukle,
                            );
                          },
                        ),
                      ),
                      if (_islem)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            children: [
                              Text(_islemMetni),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(value: _ilerleme),
                            ],
                          ),
                        ),
                      if (_hata != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: SingleChildScrollView(
                              child: Text(
                                _hata!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_yukleniyor) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _belgeler.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _yukleniyor
                                ? 'Belgeler yükleniyor...'
                                : _hata != null
                                ? 'Yenile düğmesiyle tekrar deneyebilirsiniz.'
                                : _arama.text.trim().isNotEmpty
                                ? 'Aramanıza uygun belge bulunamadı.'
                                : 'Henüz belge yok. Belge Ekle ile cihazınızdan dosya seçin.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                        itemCount: _belgeler.length + (_devamiVar ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _belgeler.length) {
                            return TextButton(
                              onPressed: _islem || _yukleniyor
                                  ? null
                                  : () => _listeYukle(devam: true),
                              child: const Text('Daha fazla belge göster'),
                            );
                          }
                          final belge = _belgeler[i];
                          return Card(
                            elevation: 0,
                            child: ListTile(
                              key: ValueKey(belge.id),
                              leading: Icon(
                                _simge(belge.uzanti),
                                color: const Color(0xFF254B78),
                              ),
                              title: Text(
                                belge.dosyaAdi,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${belge.belgeTuru} • ${belge.egitimOgretimYili}\n${belge.uzanti.toUpperCase()} • ${_boyut(belge.boyut)} • '
                                '${DateFormat('dd.MM.yyyy').format(belge.eklenmeTarihi.toLocal())}'
                                '${belge.sonImport == null ? '' : '\nİçe aktarıldı • Ayrıntılar menüde'}'
                                '${belge.acilabilir ? '' : '\nDosya eksik veya değişmiş; yeniden ekleyin.'}',
                              ),
                              trailing: _secimModu
                                  ? Icon(
                                      widget.secimUzantilari!.contains(
                                                belge.uzanti,
                                              ) &&
                                              belge.acilabilir
                                          ? Icons.check_circle_outline
                                          : Icons.block,
                                    )
                                  : _belgeMenusu(belge),
                              onTap: _islem || _yukleniyor
                                  ? null
                                  : () => _secimModu ? _sec(belge) : _ac(belge),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
