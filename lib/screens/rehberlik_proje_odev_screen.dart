import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../models/mesajlasma.dart';
import '../models/ortak_import.dart';
import '../services/bireysel_rehberlik_service.dart';
import '../services/bireysel_bilgi_toplama_service.dart';
import '../services/bilgi_toplama_google_service.dart';
import '../services/ortak_google_oturum_service.dart';
import '../services/mesajlasma_service.dart';
import '../services/bireysel_belge_service.dart';
import '../services/belge_disari_aktar_service.dart';
import '../services/proje_odev_rapor_service.dart';
import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import '../widgets/mesaj_alici_secim_sliver.dart';
import 'bireysel_bilgi_toplama_screen.dart';
import 'mesajlasma_screen.dart';

/// Mevcut Forms API, kimlik anlık görüntüsü, alıcı seçimi ve mesaj motorunun
/// proje tercihlerine özgü üç aşamalı görünümü. Ayrı Google adaptörü yoktur.
class RehberlikProjeOdevScreen extends StatefulWidget {
  const RehberlikProjeOdevScreen({
    super.key,
    required this.service,
    required this.baglam,
    required this.atama,
    this.saltOkunur = false,
    this.formService,
    this.google,
    this.hesapBagla,
    this.belgeService,
  });
  final BireyselRehberlikService service;
  final BireyselRehberlikBaglami baglam;
  final Map<String, Object?> atama;
  final bool saltOkunur;
  final BireyselBilgiToplamaService? formService;
  final BilgiToplamaGoogleService? google;
  final Future<String> Function()? hesapBagla;
  final BireyselBelgeService? belgeService;
  @override
  State<RehberlikProjeOdevScreen> createState() => _ProjeState();
}

class _ProjeState extends State<RehberlikProjeOdevScreen> {
  late final fs = widget.formService ?? BireyselBilgiToplamaService.instance;
  late final google = widget.google ?? BilgiToplamaGoogleService();
  BilgiToplamaOturumu? fb;
  int get atama => widget.atama['RehberlikAtamaId'] as int;
  int get sinif => widget.atama['SinifSubeId'] as int;
  BireyselRehberlikBaglami get b => widget.baglam;
  final baslik = TextEditingController(text: 'Proje Ödevi Ders Tercih Formu');
  final aciklama = TextEditingController(
    text:
        'Sevgili öğrenciler, proje ödevi almak istediğiniz üç farklı dersi öncelik sırasına göre seçiniz.',
  );
  final mesaj = TextEditingController();
  final arama = TextEditingController();
  List<Map<String, dynamic>> talepler = [], tercihler = [];
  List<Map<String, Object?>> dersler = [], ogrenciler = [], ogretmenler = [];
  List<MesajKisi> kisiler = [];
  final secili = <String, MesajKisi>{};
  final dersSecimi = <int, String>{};
  final onaySecimi = <int, String>{};
  final yanitSecimi = <int, String>{};
  bool yanitSecimModu = false;
  String? silmeIlerleme;
  bool silmeDurdur = false;
  List<Map<String, Object?>> hamYanitlar = [];
  final kapasite = <int, int>{};
  Map<String, dynamic>? proje, plan;
  Map<String, dynamic>? analiz;
  Map<String, Object?>? form;
  String? hata, sonuc, link;
  bool busy = true, yeni = false, kontenjan = false, sadeceHata = false;
  int adim = 0, ekran = 0, sekme = 0;
  int? yerelForm;
  DateTime? sonGun;
  String istek = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  bool get salt => widget.saltOkunur;
  String _tarihYaz(String? v) {
    final t = DateTime.tryParse(v ?? '')?.toLocal();
    if (t == null) return 'Belirlenmedi';
    String iki(int n) => '$n'.padLeft(2, '0');
    return '${iki(t.day)}.${iki(t.month)}.${t.year} • ${iki(t.hour)}:${iki(t.minute)}';
  }

  String _davetMetni(Map p) =>
      '${p['aciklama']}${p['sonGun'] == null ? '' : '\nSon Gün: ${_tarihYaz(p['sonGun'] as String)}'}';
  Set<int> get hedefler =>
      secili.values.map((k) => int.parse(k.kisiId)).toSet();
  int get formId => proje!['formId'] as int;
  Map<int, String> get projeDersleri => {
    for (final e in (proje!['dersler'] as Map).entries)
      int.parse(e.key as String): e.value as String,
  };
  bool get dagitimGuncel {
    if (proje?['dagitimOnayli'] != true) return false;
    final imzalar = proje!['dagitimImzalari'] as Map? ?? {};
    return tercihler.where((r) => r['onayli'] == true).length ==
            imzalar.length &&
        imzalar.entries.every(
          (e) => tercihler.any(
            (r) =>
                '${r['OgrenciId']}' == e.key &&
                r['onayli'] == true &&
                r['imza'] == e.value,
          ),
        );
  }

  @override
  void initState() {
    super.initState();
    _is(_yukle);
  }

  @override
  void dispose() {
    baslik.dispose();
    aciklama.dispose();
    mesaj.dispose();
    arama.dispose();
    if (widget.google == null) google.dispose();
    super.dispose();
  }

  Future<void> _kontrol({bool yazma = true}) async {
    if (yazma) {
      await widget.service.googleYazmaYetkisiniKontrol(b, atama);
    } else {
      await widget.service.projeTalepleri(b, atama);
    }
    final t = await fs.hazirla();
    if (t.okulId != b.okulId ||
        t.profilId != b.ogretmenProfilId ||
        t.yil != b.egitimOgretimYili) {
      throw StateError('Okul, profil veya yıl değişti. Bölümü yeniden açın.');
    }
    fb = t;
  }

  Future<void> _is(Future<void> Function() f) async {
    if (mounted) {
      setState(() {
        busy = true;
        hata = null;
        sonuc = null;
      });
    }
    try {
      await f();
    } catch (e) {
      if (mounted) {
        setState(() => hata = 'İşlem tamamlanamadı. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _yukle() async {
    await _kontrol(yazma: false);
    talepler = await widget.service.projeTalepleri(b, atama);
    dersler = await widget.service.projeDersleri(b, atama);
    ogrenciler = await widget.service.sinifOgrencileri(b, atama);
    if (proje != null) {
      proje = talepler.singleWhere((p) => p['formId'] == formId);
      form = await fs.formGetir(fb!, formId);
      link = proje!['formLinki'] as String?;
      tercihler = await widget.service.projeTercihleri(b, atama, formId);
      hamYanitlar = await fs.yanitlar(fb!, formId);
      yanitSecimi.removeWhere(
        (id, surum) =>
            !hamYanitlar.any((y) => y['Id'] == id && y['KaynakSurum'] == surum),
      );
      ogretmenler = await widget.service.projeDersOgretmenleri(b, atama);
      analiz = await widget.service.projeAnalizi(b, atama, formId);
      onaySecimi.removeWhere(
        (id, imza) => !tercihler.any(
          (r) =>
              r['OgrenciId'] == id &&
              r['imza'] == imza &&
              (r['hatalar'] as List).isEmpty,
        ),
      );
    }
  }

  Future<void> _yeni() async {
    await _kontrol();
    final ms = MesajlasmaService.instance;
    final mb = await ms.hazirla();
    if (mb.okulId != b.okulId ||
        mb.ogretmenId != b.ogretmenProfilId ||
        mb.yil != b.egitimOgretimYili) {
      throw StateError('Alıcı kapsamı değişti.');
    }
    kisiler = (await ms.aliciAdaylari(mb))
        .where((k) => k.sinifId == sinif && k.tur == MesajKisiTuru.ogrenci)
        .toList();
    final ids = ogrenciler
        .where((o) => o['OgrenciAktif'] == 1 && o['KayitAktif'] == 1)
        .map((o) => o['OgrenciId'])
        .toSet();
    secili
      ..clear()
      ..addEntries(
        kisiler
            .where((k) => ids.contains(int.parse(k.kisiId)))
            .map((k) => MapEntry(k.secimAnahtari, k)),
      );
    dersSecimi
      ..clear()
      ..addEntries(
        dersler.map(
          (d) => MapEntry(d['DersId'] as int, d['DersAdi'] as String),
        ),
      );
    yerelForm = null;
    sonGun = null;
    proje = null;
    adim = 0;
    yeni = true;
    ekran = 0;
    istek = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _secim() async {
    final kopya = Map<String, MesajKisi>.of(secili);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (c) => StatefulBuilder(
          builder: (c, set) => OrtakSayfa(
            appBar: const ModulUstBar(title: Text('Proje öğrencileri')),
            body: CustomScrollView(
              slivers: [
                MesajAliciSecimSliver(
                  adaylar: kisiler,
                  siniflar: {sinif: '${widget.atama['SinifKodu']}'},
                  secilenler: kopya,
                  ogrenciKapsami: true,
                  iletisimDuzenleme: false,
                  baslangicSinifId: sinif,
                  baslangicAliciTuru: MesajKisiTuru.ogrenci,
                  degistir: (ks) => set(() {
                    kopya
                      ..clear()
                      ..addEntries(ks.map((k) => MapEntry(k.secimAnahtari, k)));
                  }),
                  veliDuzenle: (_) async {},
                  ogretmenDuzenle: (_, _) async {},
                  kisiDuzenle: (_) async {},
                ),
              ],
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: () {
                  secili
                    ..clear()
                    ..addAll(kopya);
                  Navigator.pop(c);
                },
                child: const Text('Seçimi uygula'),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _dersEkle() async {
    var girilen = '';
    String? sorun;
    final ad = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Ders Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (v) => girilen = v,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: 'Ders adı',
                  errorText: sorun,
                ),
              ),
              const Text(
                'Bu ders yalnız hazırladığınız proje formuna eklenir. Sınıfın ders programı değiştirilmez.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final value = girilen.trim();
                if (value.isEmpty) {
                  set(() => sorun = 'Ders adını girin.');
                  return;
                }
                final eslesen = dersler.where(
                  (d) =>
                      importNormalize(d['DersAdi'] as String) ==
                      importNormalize(value),
                );
                if (eslesen.isNotEmpty) {
                  final d = eslesen.first;
                  if (dersSecimi.containsKey(d['DersId'])) {
                    set(() => sorun = 'Bu ders zaten seçili.');
                    return;
                  }
                  dersSecimi[d['DersId'] as int] = d['DersAdi'] as String;
                  Navigator.pop(c);
                  return;
                }
                if (dersSecimi.length >= 100) {
                  set(() => sorun = 'Formun ders seçenekleri dolu.');
                  return;
                }
                Navigator.pop(c, value);
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (ad != null) {
        final id =
            dersler
                .map((d) => d['DersId'] as int)
                .fold<int>(0, (m, v) => v < m ? v : m) -
            1;
        dersler = [
          ...dersler,
          {'DersId': id, 'DersAdi': ad},
        ];
        dersSecimi[id] = ad;
      }
    });
  }

  Future<void> _devam() async {
    if (adim == 0 && (baslik.text.trim().isEmpty || hedefler.isEmpty)) {
      throw StateError('Form başlığı ve hedef öğrenci seçin.');
    }
    if (adim == 1 && dersSecimi.length < 3) {
      throw StateError(
        'En az üç farklı ders seçin. Eksik dersleri Ders Ekle ile ekleyebilirsiniz.',
      );
    }
    if (adim < 2) {
      adim++;
      return;
    }
    await _kontrol();
    yerelForm ??= await fs.formOlustur(
      fb!,
      baslik: baslik.text,
      istekKimligi: istek,
      ogrenciListesi: true,
      hedefTuru: 'OgrenciSec',
      ogrenciIdleri: hedefler,
      sorular: [
        for (var i = 1; i <= 3; i++)
          BilgiToplamaSorusu(
            anahtar: 'projeTercih$i',
            baslik: '$i. Ders Tercihi${i == 1 ? ' (Öncelikli)' : ''}',
            veriTuru: 'Secenek',
            zorunlu: true,
            secenekler: dersSecimi.values.toList(),
          ),
      ],
    );
    await _kontrol();
    await widget.service.projeFormunuBagla(
      b,
      atama,
      yerelForm!,
      dersSecimi,
      aciklama.text,
      sonGun: sonGun?.toIso8601String(),
    );
    await fs.formAlicilariniKaydet(
      fb!,
      yerelForm!,
      secili.values.map((k) => k.bagAnahtari).toSet(),
    );
    talepler = await widget.service.projeTalepleri(b, atama);
    proje = talepler.singleWhere((p) => p['formId'] == yerelForm);
    yeni = false;
    ekran = 0;
    await _yukle();
    await _hazirla();
  }

  Future<String> _token() =>
      widget.hesapBagla?.call() ?? OrtakGoogleOturumService.token();
  Future<void> _hazirla({String? kurtar}) async {
    await _kontrol();
    final token = await _token();
    await google.hazirla(
      fs,
      fb!,
      formId,
      token,
      kurtarilacakId: kurtar,
      aciklama: _davetMetni(proje!),
    );
    await _kontrol();
    link = await google.yayinla(fs, fb!, formId, token);
    final hazirLink = link;
    await _kontrol();
    await _yukle();
    link = hazirLink;
    ekran = 0;
    mesaj.text = '${_davetMetni(proje!)}\n\nForm Linki: $link';
    // Hazırlama bitince ortak mesaj ön izlemesi ve kullanıcı onayı açılır.
    await _gonder();
  }

  Future<void> _gonder({bool hatirlat = false, bool duzenle = false}) async {
    await _kontrol();
    final token = await _token();
    link = BilgiToplamaGoogleService.paylasimBaglantisi(
      await google.kontrolEt(fs, fb!, formId, token),
    );
    final dogrulananLink = link;
    await _kontrol();
    final ids = (proje!['ogrenciler'] as List).cast<int>().toSet();
    Set<String> baglar = await fs.formAliciBaglari(fb!, formId);
    if (hatirlat) {
      await google.yanitlariAl(fs, fb!, formId, token);
      await _yukle();
      link = dogrulananLink;
      if (tercihler.any(
        (r) =>
            r['OgrenciId'] == null ||
            (r['hatalar'] as List).any(
              (h) => h.toString().contains('birden fazla'),
            ),
      )) {
        throw StateError('Belirsiz yanıtlar var. Önce tercihleri inceleyin.');
      }
      final eksik = tercihler
          .where((r) => r['bekliyor'] == true)
          .map((r) => r['OgrenciId'])
          .toSet();
      baglar = baglar
          .where((k) => eksik.contains(int.tryParse(k.split(':')[1])))
          .toSet();
    }
    if (baglar.isEmpty) throw StateError('Gönderilecek kayıtlı alıcı yok.');
    final fid = formId;
    final secilenBaglar = Set<String>.of(baglar);
    if (mesaj.text.trim().isEmpty) {
      mesaj.text = '${_davetMetni(proje!)}\n\nForm Linki: $link';
    }
    mesaj.text = mesaj.text.replaceAll('{FormBaglantisi}', link!);
    if (!mesaj.text.contains(link!)) {
      mesaj.text = '${mesaj.text}\nForm Linki: $link';
    }
    await widget.service.projeDavetiniKaydet(
      b,
      atama,
      formId,
      link!,
      mesaj.text,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: duzenle,
        pageBuilder: (_, _, _) => MesajlasmaScreen(
          kaynakModul: 'RehberlikProjeOdev',
          kaynakKayit: '$atama:$fid',
          izinliOgrenciIdleri: ids,
          baslangicKisiBaglari: baglar,
          baslangicMetni: mesaj.text,
          gonderimOnizlemesiniAc: !duzenle,
          yalnizGonderimOnayi: !duzenle,
          takipPenceresi: true,
          kaynakKontrol: (mb) async {
            await _kontrol();
            if (mb.okulId != b.okulId ||
                mb.ogretmenId != b.ogretmenProfilId ||
                mb.yil != b.egitimOgretimYili) {
              throw StateError('Mesaj kapsamı değişti.');
            }
            final f = await fs.formGetir(fb!, fid);
            final guncel = await fs.formAliciBaglari(fb!, fid);
            if (f['Durum'] != 'Aktif' ||
                !secilenBaglar.every(guncel.contains)) {
              throw StateError('Form veya alıcılar değişti.');
            }
          },
        ),
      ),
    );
    sonuc = 'Gönderim durumu ortak Mesajlaşma kayıtlarında tutulur.';
  }

  Future<void> _yanitAl() async {
    await _kontrol();
    await google.yanitlariAl(fs, fb!, formId, await _token());
    await _kontrol();
    await _yukle();
    plan = null;
  }

  Future<void> _ortakForm() async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BireyselBilgiFormDetayScreen(
          service: fs,
          baglam: fb!,
          formId: formId,
          google: google,
          hesapBagla: widget.hesapBagla,
        ),
      ),
    );
    if (mounted) await _is(_yukle);
  }

  Future<void> _onayla() async {
    if (!await _onay(
      'Tercihleri onayla',
      'Seçilen ${onaySecimi.length} öğrencinin güncel üç tercihi kaydedilecek.',
    )) {
      return;
    }
    await widget.service.projeTercihleriniOnayla(b, atama, formId, onaySecimi);
    onaySecimi.clear();
    plan = null;
    await _yukle();
  }

  List<Map<String, dynamic>> get yanitSatirlari => hamYanitlar.map((y) {
    final eslesen = tercihler.where((r) => r['yanitId'] == y['Id']);
    if (eslesen.isNotEmpty) {
      return {...eslesen.first, 'kaynakSurum': y['KaynakSurum']};
    }
    final raw = jsonDecode(y['HamYanit'] as String) as Map;
    final qs = jsonDecode(y['SoruAnlikGoruntusu'] as String) as List;
    final ids = <int>[];
    for (var i = 1; i <= 3; i++) {
      final q = qs
          .where((q) => q['AlanAnahtari'] == 'projeTercih$i')
          .firstOrNull;
      if (q == null) continue;
      final duz = raw['_yerelDuzeltme'];
      final answers = raw['answers'] as Map?;
      String? value;
      if (duz is Map && duz['cevaplar'] is Map) {
        value = duz['cevaplar']['projeTercih$i']?.toString();
      } else {
        final answer = answers?[q['GoogleSoruId']];
        if (answer is Map && answer['textAnswers'] is Map) {
          final values = answer['textAnswers']['answers'];
          if (values is List && values.length == 1 && values.single is Map) {
            value = values.single['value']?.toString();
          }
        }
      }
      final d = projeDersleri.entries.where((d) => d.value == value);
      if (d.length == 1) ids.add(d.single.key);
    }
    return <String, dynamic>{
      'yanitId': y['Id'],
      'kaynakSurum': y['KaynakSurum'],
      'OkulNo': y['GirilenOkulNo'],
      'Ad': y['GirilenAdSoyad'],
      'Soyad': '',
      'tercihler': ids,
      'hatalar': [
        'Öğrenci eşleşmesi veya birden fazla yanıt için kontrol gerekli.',
      ],
      'onayli': false,
      'OgrenciId': null,
    };
  }).toList();

  void _yanitSec(Map<String, dynamic> r) => setState(() {
    yanitSecimModu = true;
    final id = r['yanitId'] as int;
    if (yanitSecimi.containsKey(id)) {
      yanitSecimi.remove(id);
    } else {
      yanitSecimi[id] = r['kaynakSurum'] as String;
    }
  });
  void _yanitSeciminiKapat() {
    yanitSecimi.clear();
    yanitSecimModu = false;
  }

  void _secilenYanitlariDogrula() {
    if (yanitSecimi.isEmpty) {
      throw StateError('Önce yanıta basılı tutarak seçim yapın.');
    }
    if (!yanitSecimi.entries.every(
      (e) => hamYanitlar.any(
        (y) => y['Id'] == e.key && y['KaynakSurum'] == e.value,
      ),
    )) {
      throw StateError('Seçilen yanıtlar değişti. Yenileyip yeniden seçin.');
    }
  }

  Future<void> _yanitlariOnayla() async {
    await _kontrol();
    _secilenYanitlariDogrula();
    final secim = {
      for (final r in tercihler.where(
        (r) =>
            yanitSecimi.containsKey(r['yanitId']) &&
            (r['hatalar'] as List).isEmpty,
      ))
        r['OgrenciId'] as int: r['imza'] as String,
    };
    if (secim.isEmpty) {
      throw StateError(
        'Seçili yanıtlar içinde onaylanabilecek geçerli tercih yok. Hatalı yanıtları düzenleyin.',
      );
    }
    final atlanan = yanitSecimi.length - secim.length;
    if (!await _onay(
      'Seçili yanıtları onayla',
      '${secim.length} öğrencinin üç ders tercihi onaylanacak.${atlanan == 0 ? '' : ' $atlanan sorunlu yanıt onaylanmayacak.'}',
    )) {
      return;
    }
    await widget.service.projeTercihleriniOnayla(b, atama, formId, secim);
    _yanitSeciminiKapat();
    plan = null;
    await _yukle();
    sonuc =
        '${secim.length} tercih onaylandı.${atlanan == 0 ? '' : ' $atlanan sorunlu yanıt korunuyor.'}';
  }

  Future<void> _yanitlariSil() async {
    await _kontrol();
    _secilenYanitlariDogrula();
    final secilen = Map<int, String>.of(yanitSecimi);
    final token = await _token();
    await google.yanitlariAl(fs, fb!, formId, token);
    final guncel = await fs.yanitlar(fb!, formId);
    if (!secilen.entries.every(
      (e) => guncel.any((y) => y['Id'] == e.key && y['KaynakSurum'] == e.value),
    )) {
      throw StateError('Seçili yanıtlar değişti. Yenileyip yeniden seçin.');
    }
    final silme = await fs.topluSilmePlani(
      fb!,
      formId,
      sadeceKaydedilenler: false,
      seciliYanitIdleri: secilen.keys.toSet(),
    );
    if (silme.toplam == 0) {
      throw StateError('Seçili yanıtlar artık silinebilir değil. Yenileyin.');
    }
    if (!mounted) return;
    if (!await _onay(
      'Seçili yanıtları sil',
      '${silme.toplam} yanıt Google Forms’dan ve uygulamadaki ham cevaplardan kalıcı olarak silinecek. '
          'Bu yanıtların tercih onayları ve dağıtım sonuçları yeniden kontrol gerektirecek. '
          'Öğrenci ana kayıtları korunur. Google E-Tablo kopyaları ve eski yedekler silinmez.',
    )) {
      return;
    }
    await _kontrol();
    silmeDurdur = false;
    if (mounted) {
      setState(() => silmeIlerleme = 'Siliniyor: 0 / ${silme.toplam}');
    }
    late BilgiToplamaTopluSilmeSonucu silinen;
    try {
      silinen = await google.yanitlariTopluSil(
        fs,
        fb!,
        silme,
        token,
        devamEt: () => mounted && !silmeDurdur,
        ilerleme: (n, toplam) {
          if (mounted) {
            setState(() => silmeIlerleme = 'Siliniyor: $n / $toplam');
          }
        },
      );
    } finally {
      silmeIlerleme = null;
    }
    await _kontrol();
    await _yukle();
    plan = null;
    if (silinen.kalan == 0) _yanitSeciminiKapat();
    sonuc =
        '${silinen.basarili} yanıt silindi; ${silinen.kalan} yanıt kaldı.${silinen.hatalar.isEmpty ? '' : '\n${silinen.hatalar.join('\n')}'}';
  }

  Future<void> _tercihDuzenle(Map<String, dynamic> row) async {
    await _kontrol();
    if (row['yanitId'] == null) {
      throw StateError('Önce öğrencinin yanıtını getirin.');
    }
    final p = await fs.onizle(fb!, row['yanitId'] as int);
    final cevaplar = await fs.duzenlenecekCevaplar(fb!, p);
    final secimler = List<String?>.generate(
      3,
      (i) => cevaplar['projeTercih${i + 1}'],
    );
    String? sorun;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${row['OkulNo']} • Tercih düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: projeDersleri.values.contains(secimler[i])
                          ? secimler[i]
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: '${i + 1}. Ders Tercihi',
                      ),
                      items: [
                        for (final ad in projeDersleri.values)
                          DropdownMenuItem(
                            value: ad,
                            child: Text(ad, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => set(() => secimler[i] = v),
                    ),
                  ),
                if (sorun != null)
                  Text(
                    sorun!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
                const Text(
                  'Özgün yanıt korunur. Düzeltme yeni bir sürüm olarak kaydedilir ve yeniden tercih onayı gerekir.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                if (secimler.any((s) => s == null) ||
                    secimler.toSet().length != 3) {
                  set(() => sorun = 'Üç farklı ders seçin.');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Düzeltmeyi kaydet'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _kontrol();
    await fs.yanitiDuzenle(fb!, p, {
      ...cevaplar,
      for (var i = 0; i < 3; i++) 'projeTercih${i + 1}': secimler[i]!,
    });
    await _yukle();
    plan = null;
  }

  Future<void> _dagit() async {
    plan = await widget.service.projeDagitimOnizle(
      b,
      atama,
      formId,
      kontenjan ? kapasite : null,
    );
  }

  Future<void> _sonuclandir() async {
    await _kontrol();
    final an = await widget.service.projeAnalizi(b, atama, formId);
    if (an['sonuclanabilir'] != true) {
      throw StateError(
        'Önce eksik/hatalı tercihleri tamamlayın, bütün öğrencilerin tercihlerini onaylayın ve ders dağıtımını kaydedin.',
      );
    }
    if (!mounted) return;
    if (!await _onay(
      'Proje ders seçimini sonuçlandır',
      '${an['yerlesen']} öğrencinin ders seçimi kesinleştirilecek. Sonuçlar ilgili ders öğretmenlerine mesaj olarak hazırlanabilecek.',
    )) {
      return;
    }
    await widget.service.projeSonuclandir(
      b,
      atama,
      formId,
      an['imza'] as String,
    );
    await _yukle();
    sonuc =
        'Proje ders seçimi sonuçlandırıldı. Ders kartından ilgili öğretmene mesaj hazırlayabilirsiniz.';
  }

  Future<void> _dersOgretmeniSec(int dersId) async {
    await _kontrol();
    final ms = MesajlasmaService.instance;
    final mb = await ms.hazirla();
    if (mb.okulId != b.okulId ||
        mb.ogretmenId != b.ogretmenProfilId ||
        mb.yil != b.egitimOgretimYili) {
      throw StateError('Öğretmen kapsamı değişti.');
    }
    final adaylar = await ms.aliciAdaylari(
      mb,
      tur: MesajKisiTuru.ogretmen,
      sinifId: sinif,
    );
    final ders =
        (analiz!['dersler'] as List).firstWhere((d) => d['dersId'] == dersId)
            as Map;
    final ids = (ders['ogretmenler'] as List).map((k) => k['KisiId']).toSet();
    final secim = {
      for (final k in adaylar.where((k) => ids.contains(k.kisiId)))
        k.secimAnahtari: k,
    };
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (c) => StatefulBuilder(
          builder: (c, set) => OrtakSayfa(
            appBar: ModulUstBar(title: Text('${ders['dersAdi']} • Öğretmen')),
            body: CustomScrollView(
              slivers: [
                MesajAliciSecimSliver(
                  adaylar: adaylar,
                  siniflar: {sinif: '${widget.atama['SinifKodu']}'},
                  secilenler: secim,
                  sadeceOgretmen: true,
                  iletisimDuzenleme: false,
                  baslangicSinifId: sinif,
                  degistir: (ks) => set(() {
                    secim
                      ..clear()
                      ..addEntries(ks.map((k) => MapEntry(k.secimAnahtari, k)));
                  }),
                  veliDuzenle: (_) async {},
                  ogretmenDuzenle: (_, _) async {},
                  kisiDuzenle: (_) async {},
                ),
                if (adaylar.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Bu sınıf için kayıtlı ders öğretmeni yok. Ortak Mesajlaşma rehberinden sınıf öğretmenlerini ekleyin.',
                      ),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: secim.isEmpty ? null : () => Navigator.pop(c, true),
                child: const Text('Öğretmeni eşleştir'),
              ),
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    await widget.service.projeDersOgretmeniEsle(
      b,
      atama,
      formId,
      dersId,
      secim.values.map((k) => k.kisiId).toSet(),
    );
    await _yukle();
  }

  Future<void> _ogretmeneSonucMesaji(int dersId) async {
    await _kontrol();
    final paket = await widget.service.projeSonucMesaji(
      b,
      atama,
      formId,
      dersId,
    );
    final ids = (paket['aliciIds'] as List).cast<String>().toSet();
    final baglar = ids.map((id) => 'Ogretmen:$id:$sinif').toSet();
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => MesajlasmaScreen(
          kaynakModul: 'RehberlikProjeSonuc',
          kaynakKayit: '$atama:$formId:$dersId:${paket['imza']}',
          ogretmenSinifId: sinif,
          baslangicOgretmenIdleri: ids,
          baslangicKisiBaglari: baglar,
          baslangicMetni: paket['metin'] as String,
          yalnizGonderimOnayi: true,
          gonderimOnizlemesiniAc: true,
          takipPenceresi: true,
          kaynakKontrol: (mb) async {
            await _kontrol();
            if (mb.okulId != b.okulId ||
                mb.ogretmenId != b.ogretmenProfilId ||
                mb.yil != b.egitimOgretimYili) {
              throw StateError('Mesaj kapsamı değişti.');
            }
            final guncel = await widget.service.projeSonucMesaji(
              b,
              atama,
              formId,
              dersId,
            );
            if (guncel['imza'] != paket['imza']) {
              throw StateError(
                'Proje sonucu veya ders öğretmeni değişti. Mesajı yeniden hazırlayın.',
              );
            }
          },
        ),
      ),
    );
    if (mounted) await _yukle();
  }

  Future<void> _dagitimKaydet() async {
    if (plan == null) throw StateError('Önce dağıtımı yenileyin.');
    if (!await _onay(
      'Dağıtımı onayla',
      '${(plan!['dagitim'] as Map).length} öğrenci yerleşti, ${plan!['acikta']} öğrenci yerleşmedi. Mevcut dağıtım bu onayla güncellenecek.',
    )) {
      return;
    }
    await widget.service.projeDagitiminiKaydet(b, atama, formId, plan!);
    plan = null;
    await _yukle();
  }

  Future<bool> _onay(String ad, String metin) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(ad),
          content: Text(metin),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Onayla'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _manuel() async {
    if (plan == null) await _dagit();
    if (!mounted) return;
    final d = Map<String, dynamic>.from(plan!['dagitim'] as Map);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Dağıtımı düzenle'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in tercihler.where((r) => r['onayli'] == true))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<int>(
                        initialValue: d['${r['OgrenciId']}'] as int?,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText:
                              '${r['OkulNo']} • ${r['Ad']} ${r['Soyad']}',
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                            value: 0,
                            child: Text('Yerleştirme yok'),
                          ),
                          for (final id in (r['tercihler'] as List).cast<int>())
                            DropdownMenuItem(
                              value: id,
                              child: Text(
                                projeDersleri[id]!,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => set(() {
                          if (v == null || v == 0) {
                            d.remove('${r['OgrenciId']}');
                          } else {
                            d['${r['OgrenciId']}'] = v;
                          }
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Ön izlemeye uygula'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      plan!['dagitim'] = d;
      plan!['acikta'] = tercihler
          .where(
            (r) =>
                r['OgrenciId'] != null && !d.containsKey('${r['OgrenciId']}'),
          )
          .length;
    }
  }

  List<List<String>> _raporSatirlari(int tur) {
    final ds = projeDersleri;
    final dag = proje!['dagitim'] as Map;
    final rows = <List<String>>[];
    if (tur == 2) {
      rows.add(['Ders', 'Öğretmen', 'Öğrenci sayısı']);
      for (final e in ds.entries) {
        final adlar = ogretmenler
            .where((o) => o['DersId'] == e.key)
            .map((o) => '${o['OgretmenAdi']}')
            .toSet();
        rows.add([
          e.value,
          adlar.isEmpty ? 'Öğretmen eşleştirilmemiş' : adlar.join(', '),
          '${dag.values.where((v) => v == e.key).length}',
        ]);
      }
    } else {
      rows.add([
        'No',
        'Öğrenci',
        '1. Tercih',
        '2. Tercih',
        '3. Tercih',
        tur == 0 ? 'Kontrol' : 'Atanan ders',
        if (tur == 3) 'Takip',
      ]);
      for (final r in tercihler) {
        final ts = (r['tercihler'] as List).cast<int>();
        rows.add([
          '${r['OkulNo']}',
          '${r['Ad']} ${r['Soyad']}',
          for (var i = 0; i < 3; i++) i < ts.length ? ds[ts[i]] ?? '' : '',
          tur == 0
              ? (r['onayli'] == true
                    ? 'Onaylı'
                    : (r['hatalar'] as List).join(' • '))
              : (ds[dag['${r['OgrenciId']}']] ?? 'Yerleşmedi'),
          if (tur == 3)
            r['onayli'] == true ? 'Tercih onaylandı' : 'Kontrol bekliyor',
        ]);
      }
      if (tur == 1) {
        final header = rows.removeAt(0);
        rows.sort((x, y) => x[5].compareTo(y[5]));
        rows.insert(0, header);
      }
    }
    return rows;
  }

  Future<void> _raporGoster(int tur) async {
    final rows = _raporSatirlari(tur);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OrtakSayfa(
          appBar: ModulUstBar(title: Text(_raporAdlari[tur])),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final r in rows.skip(1))
                _kart(r[1], Icons.assignment_outlined, [
                  for (var i = 0; i < r.length; i++)
                    Text('${rows.first[i]}: ${r[i]}'),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  static const _raporAdlari = [
    'Öğrenci Tercih Listesi',
    'Ders Bazlı Öğrenci Listesi',
    'Öğretmen Atama Listesi',
    'Takip Çizelgesi',
  ];
  int raporTuru = 0;
  Future<void> _export(String uzanti, {bool arsiv = false}) async {
    await _kontrol(yazma: false);
    await _yukle();
    if (raporTuru != 0 && !dagitimGuncel) {
      throw StateError('Dağıtım güncel değil. Yeniden onaylayın.');
    }
    final rows = _raporSatirlari(raporTuru);
    final bytes = await ProjeOdevRaporService.olustur(
      uzanti,
      '${_raporAdlari[raporTuru]} • ${widget.atama['SinifKodu']}',
      '${b.okulAdi} • ${b.egitimOgretimYili} • ${b.ogretmenAdi}',
      rows,
    );
    final ad = 'Proje_${formId}_${raporTuru + 1}.$uzanti';
    await _kontrol(yazma: false);
    if (arsiv) {
      final bs = widget.belgeService ?? BireyselBelgeService.instance;
      final ar = await bs.arsivleriGetir();
      if (ar.aktif.okulId != b.okulId ||
          ar.aktif.ogretmenProfilId != b.ogretmenProfilId) {
        throw StateError('Belge arşivi değişti.');
      }
      await bs.ekle(
        arsivId: ar.aktif.id,
        dosya: PlatformFile(name: ad, size: bytes.length, bytes: bytes),
      );
      sonuc = 'Rapor Belgelerim’e kaydedildi.';
    } else {
      final yol = await BelgeDisariAktarService.kaydet(ad, bytes);
      sonuc = yol == null ? 'Dışa aktarma iptal edildi.' : 'Rapor kaydedildi.';
    }
  }

  Widget _kart(
    String ad,
    IconData ikon,
    List<Widget> children, {
    Color? renk,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(ikon, color: renk ?? Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(ad, style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
  Widget _bilgi(String metin, {bool uyari = false}) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: uyari
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(uyari ? Icons.warning_amber : Icons.info_outline),
        const SizedBox(width: 8),
        Expanded(child: Text(metin)),
      ],
    ),
  );
  Widget _buton(
    String ad,
    IconData ikon,
    Future<void> Function() f, {
    bool ikincil = false,
    Color? renk,
    bool etkin = true,
  }) => ikincil
      ? OutlinedButton.icon(
          style: renk == null
              ? null
              : OutlinedButton.styleFrom(
                  foregroundColor: renk,
                  backgroundColor: renk.withValues(alpha: .08),
                  side: BorderSide(color: renk.withValues(alpha: .4)),
                ),
          onPressed: busy || !etkin ? null : () => _is(f),
          icon: Icon(ikon),
          label: Text(ad),
        )
      : FilledButton.icon(
          style: renk == null
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: renk,
                  foregroundColor: Colors.white,
                ),
          onPressed: busy || !etkin ? null : () => _is(f),
          icon: Icon(ikon),
          label: Text(ad),
        );
  Widget _alt(List<Widget> children) => Padding(
    padding: const EdgeInsets.all(12),
    child: Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: children,
    ),
  );
  Widget _istatistik(List<(String, int, Color)> list) => Row(
    children: [
      for (final (ad, n, renk) in list)
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: renk.withValues(alpha: .12),
              border: Border.all(color: renk.withValues(alpha: .25)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: renk,
                  ),
                ),
                Text(ad, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
    ],
  );
  Widget _adimlar() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: i < adim
                      ? Colors.green
                      : i == adim
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: i < adim
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: i == adim ? Colors.white : null,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(['Kapsam', 'Sorular', 'Kontrol'][i]),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _yeniIcerik() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _adimlar(),
      if (adim == 0) ...[
        _kart('Form Talebi Bilgileri', Icons.assignment, [
          TextField(
            controller: baslik,
            enabled: yerelForm == null,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Form Başlığı *',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: aciklama,
            enabled: yerelForm == null,
            maxLines: 3,
            maxLength: 1500,
            decoration: const InputDecoration(
              labelText: 'Açıklama',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Text('Eğitim Yılı: ${widget.atama['EgitimOgretimYili']}'),
          const SizedBox(height: 8),
          Text('Sınıf / Şube: ${widget.atama['SinifKodu']}'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(
              sonGun == null
                  ? 'Son gün (isteğe bağlı)'
                  : _tarihYaz(sonGun!.toIso8601String()),
            ),
            trailing: sonGun == null
                ? null
                : IconButton(
                    tooltip: 'Son günü kaldır',
                    onPressed: yerelForm == null
                        ? () => setState(() => sonGun = null)
                        : null,
                    icon: const Icon(Icons.close),
                  ),
            onTap: yerelForm != null
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: sonGun ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (date == null || !mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                        sonGun ??
                            DateTime(date.year, date.month, date.day, 23, 59),
                      ),
                    );
                    if (time != null && mounted) {
                      setState(
                        () => sonGun = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    }
                  },
          ),
        ]),
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text('${hedefler.length} öğrenci seçili'),
            trailing: const Icon(Icons.chevron_right),
            onTap: yerelForm == null ? _secim : null,
          ),
        ),
        if (yerelForm != null)
          _bilgi(
            'Yerel taslak korundu. Kapsamı değiştirmeden hazırlamayı sürdürebilirsiniz.',
          ),
      ],
      if (adim == 1) ...[
        ExpansionTile(
          title: Text('Öğrenci Listesi (${hedefler.length} öğrenci)'),
          children: [
            for (final k in secili.values)
              ListTile(
                dense: true,
                title: Text(k.ad),
                subtitle: Text(k.aciklama),
              ),
          ],
        ),
        _kart('Seçilebilecek Dersler', Icons.layers_outlined, [
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: yerelForm != null ? null : _dersEkle,
              icon: const Icon(Icons.add),
              label: const Text('Ders Ekle'),
            ),
          ),
          for (final d in dersler)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text('${d['DersAdi']}'),
              value: dersSecimi.containsKey(d['DersId']),
              onChanged: yerelForm != null
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        dersSecimi[d['DersId'] as int] = d['DersAdi'] as String;
                      } else {
                        dersSecimi.remove(d['DersId']);
                      }
                    }),
            ),
        ]),
        _bilgi(
          'Sınıfın kayıtlı tüm dersleri listelenir. Kutusunu kaldırarak dersi formdan çıkarabilir, Ders Ekle ile eksik bir ders ekleyebilirsiniz. Öğrenciler seçili derslerden üç farklı tercih yapacaktır.',
        ),
      ],
      if (adim == 2)
        _kart('Google Form Ön İzleme', Icons.description_outlined, [
          Text(
            baslik.text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(aciklama.text),
          if (sonGun != null)
            Text('Son Gün: ${_tarihYaz(sonGun!.toIso8601String())}'),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Öğrenciyi seçin *'),
            items: [
              for (final k in secili.values)
                DropdownMenuItem(
                  value: int.parse(k.kisiId),
                  child: Text(
                    '${ogrenciler.firstWhere((o) => o['OgrenciId'] == int.parse(k.kisiId))['OkulNo']} – ${k.ad}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (_) {},
          ),
          for (var i = 1; i <= 3; i++)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                decoration: InputDecoration(
                  labelText:
                      '$i. Ders Tercihi${i == 1 ? ' (Öncelikli)' : ''} *',
                ),
                items: [
                  for (final d in dersSecimi.entries)
                    DropdownMenuItem(
                      value: d.key,
                      child: Text(d.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (_) {},
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Ön izlemedir. Öğrenci listesinde sınıf, okul numarası ve ad soyad birlikte yer alır. Üç farklı ders kuralı yanıt kontrolünde doğrulanır.',
          ),
        ]),
    ],
  );

  Widget _davet() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _kart('Oluşturulan Form', Icons.description_outlined, [
        Text('${proje!['baslik']}'),
        Text('Durum: ${form?['Durum'] ?? 'Taslak'}'),
        if (link != null)
          Row(
            children: [
              Expanded(child: SelectableText(link!)),
              IconButton(
                tooltip: 'Bağlantıyı kopyala',
                onPressed: () => Clipboard.setData(ClipboardData(text: link!)),
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
      ]),
      _kart('Form Daveti Gönder', Icons.outgoing_mail, [
        const Text(
          'Gönderilecek kişiler ve kanal ortak Mesajlaşma onayında kontrol edilir.',
        ),
        TextField(
          controller: mesaj,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Davetiye Metni'),
        ),
      ]),
      if (!salt)
        _buton(
          'Alıcılar / Mesajı düzenle',
          Icons.edit_outlined,
          () => _gonder(duzenle: true),
          ikincil: true,
        ),
      if (!salt && form?['Durum'] == 'Taslak')
        _buton('Mevcut Google formunu bağla', Icons.link, () async {
          final c = TextEditingController();
          final id = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Yarım kalan formu bağla'),
              content: TextField(
                controller: c,
                decoration: const InputDecoration(
                  labelText: 'Google düzenleme adresindeki form kimliği',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, c.text.trim()),
                  child: const Text('Bağla'),
                ),
              ],
            ),
          );
          if (id != null && id.isNotEmpty) await _hazirla(kurtar: id);
        }, ikincil: true),
    ],
  );
  Widget _yanitlar() {
    final toplam = (proje!['ogrenciler'] as List).length;
    final alinan = tercihler
        .where((r) => r['OgrenciId'] != null && r['bekliyor'] != true)
        .map((r) => r['OgrenciId'])
        .toSet()
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('Özet', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ButtonSegment(
              value: 1,
              label: Text(
                'Yanıtlar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ButtonSegment(
              value: 2,
              tooltip: 'Değerlendirme',
              label: Text(
                'Değerlendirme',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          selected: {sekme},
          onSelectionChanged: busy
              ? null
              : (s) => setState(() {
                  sekme = s.single;
                  _yanitSeciminiKapat();
                }),
        ),
        const SizedBox(height: 12),
        if (sekme == 0) ...[
          _kart('Form Yanıt Durumu', Icons.bar_chart, [
            _istatistik([
              ('Öğrenci', toplam, Colors.blue),
              ('Alındı', alinan, Colors.green),
              ('Bekliyor', toplam - alinan, Colors.orange),
            ]),
          ]),
          _kart('Form Bilgileri', Icons.assignment_outlined, [
            Text('${proje!['baslik']}'),
            Text('Durum: ${form?['Durum']}'),
            Text(
              'Oluşturma: ${_tarihYaz(form?['OlusturmaTarihi'] as String?)}',
            ),
            Text('Son Gün: ${_tarihYaz(proje!['sonGun'] as String?)}'),
            if (link != null) SelectableText(link!),
          ]),
        ] else if (sekme == 2)
          _degerlendirme()
        else ...[
          if (yanitSecimModu)
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Tümünü seç (${yanitSecimi.length}/${hamYanitlar.length})',
                    ),
                    value:
                        hamYanitlar.isNotEmpty &&
                        yanitSecimi.length == hamYanitlar.length,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            yanitSecimi.clear();
                            if (v == true) {
                              yanitSecimi.addEntries(
                                hamYanitlar.map(
                                  (y) => MapEntry(
                                    y['Id'] as int,
                                    y['KaynakSurum'] as String,
                                  ),
                                ),
                              );
                            }
                          }),
                  ),
                ),
                IconButton(
                  tooltip: 'Seçimi kapat',
                  onPressed: busy ? null : () => setState(_yanitSeciminiKapat),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          if (hamYanitlar.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Henüz yanıt alınmadı.'),
            ),
          for (final r in yanitSatirlari)
            Card(
              key: ValueKey('proje-yanit-${r['yanitId']}'),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: yanitSecimModu
                    ? Checkbox(
                        value: yanitSecimi.containsKey(r['yanitId']),
                        onChanged: busy || salt ? null : (_) => _yanitSec(r),
                      )
                    : Icon(
                        r['onayli'] == true
                            ? Icons.check_circle_outline
                            : Icons.assignment_outlined,
                      ),
                title: Text(
                  '${r['OkulNo']} • ${r['Ad']} ${r['Soyad']}',
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (r['tercihler'] as List).indexed
                          .map((e) => '${e.$1 + 1}. ${projeDersleri[e.$2]}')
                          .join('\n'),
                    ),
                    if ((r['hatalar'] as List).isNotEmpty)
                      Text(
                        (r['hatalar'] as List).join('\n'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (r['onayli'] == true) const Text('Onaylı'),
                  ],
                ),
                onLongPress: busy || salt ? null : () => _yanitSec(r),
                onTap: busy || salt
                    ? null
                    : () => yanitSecimModu
                          ? _yanitSec(r)
                          : _is(() => _tercihDuzenle(r)),
              ),
            ),
        ],
      ],
    );
  }

  Widget _degerlendirme() {
    final an = analiz;
    if (an == null) return _bilgi('Analiz için verileri yenileyin.');
    final tamam = an['sonuclandi'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kart('Proje Ders Seçimi Analizi', Icons.analytics_outlined, [
          _istatistik([
            ('Öğrenci', an['toplam'] as int, Colors.blue),
            ('Onaylı', an['onayli'] as int, Colors.green),
            ('Yerleşen', an['yerlesen'] as int, Colors.purple),
          ]),
          Text(
            '${an['bekleyen']} yanıt bekleniyor • ${an['sorunlu']} sorunlu yanıt',
          ),
          const SizedBox(height: 8),
          Text(
            tamam
                ? 'Proje ders seçimi sonuçlandırıldı'
                : 'Proje ders seçimi henüz sonuçlandırılmadı',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (tamam)
            Text('Sonuçlandırma: ${_tarihYaz(an['sonucTarihi'] as String?)}'),
        ]),
        if (!tamam && an['sonuclanabilir'] != true)
          _bilgi(
            'Eksik veya hatalı yanıtları tamamlayın, tercihleri onaylayın ve bütün öğrencileri derslere yerleştirin. Sonuçlandırma güncel dağıtımı kesinleştirir.',
            uyari: true,
          ),
        if (!salt)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buton(
                'Tercihleri Kontrol Et',
                Icons.fact_check_outlined,
                () async {
                  ekran = 2;
                },
                ikincil: true,
              ),
              _buton('Ders Dağıtımı', Icons.school_outlined, () async {
                ekran = 3;
              }, ikincil: true),
            ],
          ),
        for (final d in (an['dersler'] as List).cast<Map<String, dynamic>>())
          _kart('${d['dersAdi']}', Icons.bar_chart, [
            Text(
              '1. tercih: ${(d['tercihler'] as List)[0]} • 2. tercih: ${(d['tercihler'] as List)[1]} • 3. tercih: ${(d['tercihler'] as List)[2]}',
            ),
            Text('Yerleşen öğrenci: ${d['yerlesen']}'),
            Text(
              (d['ogretmenler'] as List).isEmpty
                  ? 'Ders öğretmeni eşleştirilmemiş'
                  : 'Ders öğretmeni: ${(d['ogretmenler'] as List).map((k) => k['AdSoyad']).join(', ')}',
            ),
            if (!salt)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buton(
                    'Öğretmen Eşleştir',
                    Icons.person_search_outlined,
                    () => _dersOgretmeniSec(d['dersId'] as int),
                    ikincil: true,
                  ),
                  _buton(
                    'Öğretmene Mesaj',
                    Icons.send_outlined,
                    () => _ogretmeneSonucMesaji(d['dersId'] as int),
                    etkin:
                        tamam &&
                        (d['yerlesen'] as int) > 0 &&
                        (d['ogretmenler'] as List).isNotEmpty,
                  ),
                ],
              ),
          ]),
        Text(
          'Öğrenci Bazlı Sonuçlar',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final r in (an['ogrenciler'] as List).cast<Map<String, dynamic>>())
          Card(
            child: ListTile(
              leading: Icon(
                r['dersId'] == null
                    ? Icons.pending_outlined
                    : Icons.check_circle_outline,
              ),
              title: Text(
                '${r['OkulNo']} • ${r['Ad']} ${r['Soyad']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sonuç: ${r['dersAdi'] ?? 'Henüz yerleşmedi'}'),
                  Text('${r['durum']}'),
                  if ((r['hatalar'] as List).isNotEmpty)
                    Text((r['hatalar'] as List).join('\n')),
                ],
              ),
              onTap: salt || busy || r['yanitId'] == null
                  ? null
                  : () => _is(() => _tercihDuzenle(r)),
            ),
          ),
      ],
    );
  }

  Widget _kontrolEkrani() {
    final g = tercihler.where((r) => (r['hatalar'] as List).isEmpty).length;
    final bek = tercihler.where((r) => r['bekliyor'] == true).length;
    final h = tercihler.length - g - bek;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _istatistik([
          ('Geçerli', g, Colors.green),
          ('Sorunlu', h, Colors.red),
          ('Bekliyor', bek, Colors.blue),
        ]),
        TextField(
          controller: arama,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Öğrenci adı veya okul numarası',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        SwitchListTile(
          title: const Text('Yalnız hatalı tercihleri göster'),
          value: sadeceHata,
          onChanged: (v) => setState(() => sadeceHata = v),
        ),
        _bilgi(
          'Üç farklı ders zorunludur. Yeni yanıtlar onaylı tercihleri veya kesin dağıtımı sessizce değiştirmez.',
          uyari: h > 0,
        ),
        for (final r in tercihler.where(
          (r) =>
              (!sadeceHata ||
                  ((r['hatalar'] as List).isNotEmpty &&
                      r['bekliyor'] != true)) &&
              '${r['OkulNo']} ${r['Ad']} ${r['Soyad']}'.toLowerCase().contains(
                arama.text.toLowerCase(),
              ),
        ))
          Card(
            child: CheckboxListTile(
              secondary: !salt && r['yanitId'] != null
                  ? IconButton(
                      tooltip: 'Tercihleri düzenle',
                      color: Theme.of(context).colorScheme.primary,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: busy
                          ? null
                          : () => _is(() => _tercihDuzenle(r)),
                    )
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('${r['OkulNo']} • ${r['Ad']} ${r['Soyad']}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, d) in (r['tercihler'] as List).indexed)
                    Text('${i + 1}. ${projeDersleri[d]}'),
                  if ((r['hatalar'] as List).isNotEmpty)
                    Text(
                      (r['hatalar'] as List).join('\n'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (r['onayli'] == true)
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Colors.green,
                        ),
                        SizedBox(width: 4),
                        Text('Onaylı'),
                      ],
                    ),
                ],
              ),
              value: onaySecimi.containsKey(r['OgrenciId']),
              onChanged: salt || (r['hatalar'] as List).isNotEmpty
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        onaySecimi[r['OgrenciId'] as int] = r['imza'] as String;
                      } else {
                        onaySecimi.remove(r['OgrenciId']);
                      }
                    }),
            ),
          ),
      ],
    );
  }

  Widget _dagitim() {
    final ds = projeDersleri;
    final d =
        plan?['dagitim'] as Map? ??
        (dagitimGuncel ? proje!['dagitim'] as Map : <String, dynamic>{});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kart('Ders Kontenjanları', Icons.school_outlined, [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Kontenjan kullan (isteğe bağlı)'),
            value: kontenjan,
            onChanged: salt
                ? null
                : (v) => setState(() {
                    kontenjan = v;
                    plan = null;
                  }),
          ),
          for (final e in ds.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(e.value)),
                  if (kontenjan) ...[
                    IconButton(
                      tooltip: 'Kontenjanı azalt',
                      onPressed: salt || kapasite[e.key] == 0
                          ? null
                          : () => setState(() {
                              kapasite[e.key] = kapasite[e.key]! - 1;
                              plan = null;
                            }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('${kapasite[e.key] ?? 0}'),
                    IconButton(
                      tooltip: 'Kontenjanı artır',
                      onPressed: salt
                          ? null
                          : () => setState(() {
                              kapasite[e.key] = (kapasite[e.key] ?? 0) + 1;
                              plan = null;
                            }),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ] else
                    const Text('Sınırsız'),
                ],
              ),
            ),
        ]),
        _kart('Dağıtım Ön İzleme (${d.length} öğrenci)', Icons.groups_outlined, [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in ds.entries)
                Chip(
                  label: Text(
                    '${e.value}: ${d.values.where((v) => v == e.key).length}',
                  ),
                ),
            ],
          ),
          Text(
            'Yerleşmeyen: ${plan?['acikta'] ?? (proje!['ogrenciler'] as List).length - d.length}',
          ),
          Text(
            dagitimGuncel && plan == null
                ? 'Kesin dağıtım kaydedildi.'
                : 'Bu dağıtım henüz kesinleştirilmedi.',
          ),
        ]),
        _bilgi(
          'Önce 1., sonra 2. ve 3. tercihler değerlendirilir. Eşit öncelikte okul numarası sırası kullanılır. Öğrenci tercih etmediği derse otomatik atanmaz.',
        ),
      ],
    );
  }

  Widget _raporlar() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _kart('Ders Dağılım Özeti', Icons.bar_chart, [
        Wrap(
          spacing: 8,
          children: [
            for (final e in projeDersleri.entries)
              Chip(
                label: Text(
                  '${e.value}: ${(proje!['dagitim'] as Map).values.where((v) => v == e.key).length}',
                ),
              ),
          ],
        ),
      ]),
      if (!dagitimGuncel)
        _bilgi(
          'Kesin dağıtım yok veya yanıtlar değişti. Dağıtım raporları için yeniden kontrol ve onay gerekir.',
          uyari: true,
        ),
      for (var i = 0; i < 4; i++)
        Card(
          child: ListTile(
            leading: Icon(
              [
                Icons.list_alt,
                Icons.layers_outlined,
                Icons.groups_outlined,
                Icons.event_note,
              ][i],
            ),
            title: Text(_raporAdlari[i]),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy || i != 0 && !dagitimGuncel
                ? null
                : () => _is(() => _raporGoster(i)),
          ),
        ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        initialValue: raporTuru,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Dışa aktarılacak rapor'),
        items: [
          for (var i = 0; i < 4; i++)
            DropdownMenuItem(
              value: i,
              child: Text(_raporAdlari[i], overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => raporTuru = v ?? 0),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final detay = proje != null && !yeni;
    final ad = yeni
        ? [
            'Form Talebi Oluştur',
            'Öğrenci ve Ders Seçenekleri',
            'Google Formu Hazırla',
          ][adim]
        : detay
        ? [
            'Ortak Mesajlaşma ile Gönder',
            'Google Form Yanıtlarını Getir',
            'Tercihleri Kontrol Et',
            'Proje Derslerini Dağıt',
            'Liste ve Rapor Oluştur',
          ][ekran]
        : 'Form Talepleri';
    return PopScope(
      canPop: !yeni && !detay,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) {
          setState(() {
            if (yanitSecimModu) {
              _yanitSeciminiKapat();
              return;
            }
            yeni = false;
            proje = null;
          });
        }
      },
      child: OrtakSayfa(
        appBar: ModulUstBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Proje Ödevleri'),
              Text(ad, style: const TextStyle(fontSize: 11)),
            ],
          ),
          leading: yeni || detay
              ? IconButton(
                  tooltip: 'Proje taleplerine dön',
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          if (yanitSecimModu) {
                            _yanitSeciminiKapat();
                            return;
                          }
                          yeni = false;
                          proje = null;
                        }),
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (silmeIlerleme != null)
              Row(
                children: [
                  Expanded(child: Text(silmeIlerleme!)),
                  TextButton(
                    onPressed: silmeDurdur
                        ? null
                        : () => setState(() => silmeDurdur = true),
                    child: const Text('Durdur'),
                  ),
                ],
              ),
            if (hata != null) _bilgi(hata!, uyari: true),
            if (sonuc != null) _bilgi(sonuc!),
            if (salt) _bilgi('Geçmiş atama • Salt okunur'),
            if (yeni)
              _yeniIcerik()
            else if (detay) ...[
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<int>(
                  tooltip: 'İşlem değiştir',
                  key: ValueKey(ekran),
                  enabled: !busy,
                  itemBuilder: (_) => [
                    for (var i = 0; i < 5; i++)
                      PopupMenuItem(
                        value: i,
                        child: Text(
                          [
                            'Form Daveti',
                            'Yanıtlar',
                            'Tercih Kontrolü',
                            'Ders Dağıtımı',
                            'Liste ve Raporlar',
                          ][i],
                        ),
                      ),
                  ],
                  onSelected: (v) => setState(() {
                    ekran = v;
                    _yanitSeciminiKapat();
                  }),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('İşlem değiştir'),
                        Icon(Icons.expand_more),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (ekran == 0) _davet(),
              if (ekran == 1) _yanitlar(),
              if (ekran == 2) _kontrolEkrani(),
              if (ekran == 3) _dagitim(),
              if (ekran == 4) _raporlar(),
            ] else ...[
              for (final p in talepler)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.assignment_outlined),
                    title: Text('${p['baslik']}'),
                    subtitle: Text(
                      '${(p['ogrenciler'] as List).length} öğrenci • ${widget.atama['SinifKodu']}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: busy
                        ? null
                        : () => _is(() async {
                            proje = p;
                            ekran = 1;
                            plan = null;
                            await _yukle();
                            kontenjan = (p['kontenjan'] as Map).isNotEmpty;
                            kapasite
                              ..clear()
                              ..addEntries(
                                projeDersleri.keys.map(
                                  (id) => MapEntry(
                                    id,
                                    (p['kontenjan'] as Map)['$id'] as int? ??
                                        (p['ogrenciler'] as List).length,
                                  ),
                                ),
                              );
                            mesaj.text =
                                p['mesajMetni'] as String? ??
                                '${_davetMetni(p)}\n\nForm Linki: {FormBaglantisi}';
                          }),
                  ),
                ),
              if (talepler.isEmpty)
                _bilgi('Henüz proje formu yok. Yeni form talebi oluşturun.'),
            ],
          ],
        ),
        bottomNavigationBar: _alt([
          if (yeni) ...[
            if (adim > 0)
              _buton('Geri', Icons.chevron_left, () async {
                adim--;
              }, ikincil: true),
            _buton(
              adim == 2 ? 'Google Formu Hazırla' : 'İleri',
              adim == 2 ? Icons.link : Icons.chevron_right,
              _devam,
              renk: adim == 2 ? const Color(0xff7824ce) : null,
            ),
          ] else if (!detay) ...[
            _buton('Yenile', Icons.refresh, _yukle, ikincil: true),
            if (!salt) _buton('Form Talebi Oluştur', Icons.add, _yeni),
          ] else if (ekran == 0 && !salt) ...[
            _buton(
              form?['Durum'] == 'Taslak'
                  ? 'Google Formu Hazırla'
                  : 'Onayla ve Gönder',
              Icons.send,
              form?['Durum'] == 'Taslak' ? _hazirla : _gonder,
              renk: form?['Durum'] == 'Taslak'
                  ? const Color(0xff7824ce)
                  : const Color(0xff008a24),
            ),
          ] else if (ekran == 1 && !salt) ...[
            if (sekme == 2) ...[
              _buton('Analizi Yenile', Icons.refresh, _yukle, ikincil: true),
              _buton(
                analiz?['sonuclandi'] == true
                    ? 'Sonuçlandırıldı'
                    : 'Proje Seçimini Sonuçlandır',
                Icons.check_circle_outline,
                _sonuclandir,
                etkin:
                    analiz?['sonuclanabilir'] == true &&
                    analiz?['sonuclandi'] != true,
                renk: const Color(0xff008a24),
              ),
            ] else if (yanitSecimModu) ...[
              _buton(
                'Toplu Onayla (${yanitSecimi.length})',
                Icons.check,
                _yanitlariOnayla,
                etkin: yanitSecimi.isNotEmpty,
                renk: const Color(0xff008a24),
              ),
              _buton(
                'Toplu Sil (${yanitSecimi.length})',
                Icons.delete_outline,
                _yanitlariSil,
                etkin: yanitSecimi.isNotEmpty,
                ikincil: true,
                renk: const Color(0xffd92737),
              ),
            ] else ...[
              _buton('Yanıtları Getir', Icons.refresh, _yanitAl),
              _buton(
                'Hatırlatma Gönder',
                Icons.notifications_outlined,
                () => _gonder(hatirlat: true),
                ikincil: true,
              ),
            ],
          ] else if (ekran == 2 && !salt) ...[
            _buton('Düzenle', Icons.edit_outlined, _ortakForm, ikincil: true),
            _buton('Geçerlileri seç', Icons.checklist, () async {
              onaySecimi
                ..clear()
                ..addEntries(
                  tercihler
                      .where((r) => (r['hatalar'] as List).isEmpty)
                      .map(
                        (r) => MapEntry(
                          r['OgrenciId'] as int,
                          r['imza'] as String,
                        ),
                      ),
                );
            }, ikincil: true),
            _buton(
              'Onayla (${onaySecimi.length})',
              Icons.check,
              _onayla,
              renk: const Color(0xff008a24),
            ),
          ] else if (ekran == 3 && !salt) ...[
            _buton('Dağıtımı Yenile', Icons.refresh, _dagit, ikincil: true),
            _buton(
              'Manuel Düzenle',
              Icons.edit_outlined,
              _manuel,
              ikincil: true,
            ),
            _buton(
              'Dağıtımı Onayla',
              Icons.check,
              _dagitimKaydet,
              renk: const Color(0xff008a24),
            ),
          ] else if (ekran == 4) ...[
            _buton(
              'Excel',
              Icons.table_chart,
              () => _export('xlsx'),
              ikincil: true,
              renk: const Color(0xff008a24),
            ),
            _buton(
              'Word',
              Icons.description,
              () => _export('docx'),
              ikincil: true,
              renk: const Color(0xff0066cc),
            ),
            _buton(
              'PDF',
              Icons.picture_as_pdf,
              () => _export('pdf'),
              ikincil: true,
              renk: const Color(0xffd92737),
            ),
            if (!salt)
              _buton(
                'Belgelerim’e Kaydet',
                Icons.folder_outlined,
                () => _export('pdf', arsiv: true),
              ),
          ] else
            _buton('Yenile', Icons.refresh, _yukle, ikincil: true),
        ]),
      ),
    );
  }
}
