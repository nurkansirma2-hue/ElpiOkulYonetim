import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final dagitimArama = TextEditingController();
  int dagitimAsamasi = 0;
  int kapasiteSurumu = 0;
  bool kriterDegisti = false;
  Map<String, dynamic>? manuelPlan;
  List<Map<String, dynamic>> talepler = [], tercihler = [];
  List<Map<String, Object?>> dersler = [], ogrenciler = [], ogretmenler = [];
  List<MesajKisi> kisiler = [];
  final secili = <String, MesajKisi>{};
  final dersSecimi = <int, String>{};
  final onaySecimi = <int, String>{};
  final yanitSecimi = <int, String>{};
  List<Map<String, dynamic>>? dogrudanYanitlar;
  final dogrudanSecim = <String, String>{};
  String? dogrudanUyari;
  bool get dogrudanIsteniyor => google.dogrudanYanitOkuma && !salt;
  bool get dogrudanAktif => dogrudanIsteniyor && dogrudanYanitlar != null;
  bool yanitSecimModu = false;
  bool formSecimModu = false;
  final formSecimi = <int>{};
  String? silmeIlerleme;
  bool silmeDurdur = false;
  List<Map<String, Object?>> hamYanitlar = [];
  final kapasite = <int, int>{};
  Map<String, dynamic>? proje, plan;
  Map<String, dynamic>? analiz;
  Map<String, Object?>? form;
  bool? googleYanitAcik;
  String? hata, sonuc, link;
  bool busy = true, yeni = false, kontenjan = true, sadeceHata = false;
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
    dagitimArama.dispose();
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
    formSecimi.removeWhere((id) => !talepler.any((p) => p['formId'] == id));
    dersler = await widget.service.projeDersleri(b, atama);
    ogrenciler = await widget.service.sinifOgrencileri(b, atama);
    if (proje != null) {
      if (!talepler.any((p) => p['formId'] == formId)) {
        proje = null;
        plan = null;
        analiz = null;
        _yanitSeciminiKapat();
        return;
      }
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
      final guncelImzalar = {
        for (final r in tercihler.where((r) => r['onayli'] == true))
          '${r['OgrenciId']}': r['imza'],
      };
      bool eski(Map<String, dynamic>? p) =>
          p != null &&
          (p['surum'] != proje!['surum'] ||
              jsonEncode(p['imzalar']) != jsonEncode(guncelImzalar));
      if (eski(plan) || eski(manuelPlan)) {
        plan = null;
        manuelPlan = null;
        dagitimAsamasi = 0;
        sonuc = 'Yanıt veya kayıt değişti. Dağıtımı yeniden hazırlayın.';
      }
      for (final id in projeDersleri.keys) {
        kapasite.putIfAbsent(id, () => 3);
      }
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
    _formSeciminiKapat();
    kapasite.clear();
    kontenjan = true;
    _kriterDegisti();
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

  void _formSeciminiKapat() {
    formSecimModu = false;
    formSecimi.clear();
  }

  void _formSec(int id) => setState(() {
    formSecimModu = true;
    if (!formSecimi.add(id)) formSecimi.remove(id);
  });

  Future<void> _formAc(Map<String, dynamic> p, {int islem = 1}) async {
    dogrudanYanitlar = null;
    dogrudanUyari = null;
    _formSeciminiKapat();
    _yanitSeciminiKapat();
    onaySecimi.clear();
    sekme = 0;
    googleYanitAcik = null;
    proje = p;
    ekran = islem;
    plan = null;
    manuelPlan = null;
    kriterDegisti = false;
    dagitimAsamasi = 0;
    kapasiteSurumu++;
    await _yukle();
    if (proje == null) throw StateError('Form artık listede bulunmuyor.');
    final guncel = proje!;
    kontenjan =
        (guncel['kontenjan'] as Map).isNotEmpty ||
        guncel['dagitimOnayli'] != true;
    kapasite
      ..clear()
      ..addEntries(
        projeDersleri.keys.map(
          (id) =>
              MapEntry(id, (guncel['kontenjan'] as Map)['$id'] as int? ?? 3),
        ),
      );
    mesaj.text =
        guncel['mesajMetni'] as String? ??
        '${_davetMetni(guncel)}\n\nForm Linki: {FormBaglantisi}';
  }

  Future<void> _formlariSil() async {
    await _kontrol();
    final ids = Set<int>.of(formSecimi);
    final guncel = await widget.service.projeTalepleri(b, atama);
    if (ids.isEmpty ||
        !ids.every((id) => guncel.any((p) => p['formId'] == id))) {
      throw StateError('Seçilen formlar değişti. Listeyi yenileyin.');
    }
    if (!mounted ||
        !await _onay(
          'Seçili proje formlarını sil',
          '${ids.length} form uygulama listesinden kaldırılacak. Google formları yanıtlara kapatılacak; henüz alınmamış olanlar dahil bütün yanıtları kalıcı olarak silinecek. '
              'Tercih ve dağıtım sonuçları artık kullanılamayacak. Öğrenci kayıtları ve Belgelerim’deki raporlar korunur. '
              'Google’daki boş form şablonu, bağlı E-Tablo kopyaları ve eski yedekler kalır. Devam edilsin mi?',
        )) {
      return;
    }
    var silinen = 0;
    final hatalar = <String>[];
    String? token;
    silmeDurdur = false;
    try {
      for (final id in ids) {
        if (!mounted || silmeDurdur) break;
        setState(
          () => silmeIlerleme =
              'Form siliniyor: ${silinen + hatalar.length + 1} / ${ids.length}',
        );
        try {
          await _kontrol();
          if (!(await widget.service.projeTalepleri(
            b,
            atama,
          )).any((p) => p['formId'] == id)) {
            throw StateError('Form atama kapsamından çıkmış.');
          }
          final f = await fs.formGetir(fb!, id);
          if (f['GoogleFormId'] == null) {
            await fs.formuSil(
              fb!,
              id,
              googleTemizle: (_) async {
                throw StateError('Google bağlantısı değişti; yeniden deneyin.');
              },
            );
          } else {
            token ??=
                await (widget.hesapBagla?.call() ??
                    OrtakGoogleOturumService.token(
                      ekIzin: BilgiToplamaGoogleService.silmeScope,
                    ));
            await _kontrol();
            await google.formuSil(fs, fb!, id, token);
          }
          await _kontrol();
          silinen++;
          formSecimi.remove(id);
        } catch (e) {
          hatalar.add('Form #$id: $e');
        }
      }
    } finally {
      silmeIlerleme = null;
      await _yukle();
      if (formSecimi.isEmpty) _formSeciminiKapat();
    }
    sonuc =
        '$silinen form silindi; ${ids.length - silinen} form kaldı.${hatalar.isEmpty ? '' : '\n${hatalar.join('\n')}'}';
  }

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

  Future<void> _yanitAlimiDurumunuKontrolEt() async {
    await _kontrol(yazma: false);
    final id = formId;
    final f = await fs.formGetir(fb!, id);
    final gid = f['GoogleFormId'] as String?;
    if (gid == null || gid.isEmpty) {
      googleYanitAcik = null;
      return;
    }
    final uzak = await google.kontrolEt(fs, fb!, id, await _token());
    if (proje == null || formId != id) return;
    final yayin = (uzak['publishSettings'] as Map?)?['publishState'] as Map?;
    if (yayin == null || yayin['isAcceptingResponses'] is! bool) {
      throw StateError('Google Form yanıt kabul durumu doğrulanamadı.');
    }
    googleYanitAcik =
        yayin['isPublished'] == true &&
        yayin['isAcceptingResponses'] == true;
  }

  Future<void> _yanitAliminiDegistir() async {
    await _kontrol();
    final id = formId;
    // İşlem öncesinde Google tarafındaki gerçek durumu yeniden kontrol et.
    await _yanitAlimiDurumunuKontrolEt();
    if (proje == null || formId != id || googleYanitAcik == null) {
      throw StateError('Seçili formun yanıt alım durumu doğrulanamadı.');
    }
    final ac = googleYanitAcik == false;
    final ad = (proje!['baslik'] ?? 'Seçili form').toString();
    final sayi = hamYanitlar.length;
    if (!await _onay(
      ac ? 'Yanıtları aç' : 'Yanıt alımını kapat',
      ac
          ? '"$ad" Google Formu yeniden yanıt kabul etmeye başlayacak. '
              'Mevcut $sayi yerel yanıt korunacak. Devam edilsin mi?'
          : '"$ad" Google Formu yeni yanıt kabul etmeyecek. '
              'Mevcut $sayi yerel yanıt ve Google Form yanıtları korunacak. '
              'Yanıtları Getir ile eski cevaplara erişmeye devam edebilirsiniz. '
              'Devam edilsin mi?',
    )) {
      return;
    }
    await _kontrol();
    if (proje == null || formId != id) {
      throw StateError('İşlem sırasında seçili proje formu değişti.');
    }
    await google.yanitAliminiAyarla(fs, fb!, id, await _token(), ac);
    // Başarıyı yalnız uzak Google Form'un teyit ettiği duruma göre göster.
    googleYanitAcik = null;
    await _yanitAlimiDurumunuKontrolEt();
    if (googleYanitAcik != ac) {
      throw StateError('Google Form yanıt durumu beklenen şekilde değişmedi.');
    }
    await _yukle();
    sonuc = ac
        ? 'Google Form yeniden yanıt kabul ediyor.'
        : 'Google Form yeni yanıtlara kapatıldı. Mevcut cevaplar korunuyor.';
  }

  Future<void> _yanitAl() async {
    await _kontrol();
    await google.yanitlariAl(fs, fb!, formId, await _token());
    await _kontrol();
    await _yukle();
    if (dogrudanIsteniyor) await _dogrudanYukle();
    // Native Google Forms ve REST/SQLite farklı yanıt kimlikleri kullanabilir.
    // Öğrenci numarası yalnız tutarsızlığı bildirmek içindir, silme yetkisi değildir.
    if (dogrudanYanitlar != null) {
      final uzak = <int, int>{}, yerel = <int, int>{};
      for (final row in dogrudanYanitlar!) {
        final no = _dogrudanOkulNo(row);
        if (no != null) uzak[no] = (uzak[no] ?? 0) + 1;
      }
      for (final row in hamYanitlar) {
        final no = int.tryParse((row['GirilenOkulNo'] ?? '').toString());
        if (no != null) yerel[no] = (yerel[no] ?? 0) + 1;
      }
      final uyusmayan = {...uzak.keys, ...yerel.keys}
          .where((no) => uzak[no] != yerel[no])
          .toList()..sort();
      if (uyusmayan.isNotEmpty) {
        hata = 'Google Form ve SQLite yanıt sayıları farklı. '
            'Kontrol gereken öğrenci numaraları: '
            '${uyusmayan.take(12).join(', ')}'
            '${uyusmayan.length > 12 ? ' ve diğerleri' : ''}. '
            'Yanıt kimlikleri farklı olduğu için doğrulanmamış kayıtlar '
            'otomatik silinmedi. Onaylı tercihler korundu.';
        sonuc = null;
        plan = null;
        return;
      }
    }
    sonuc = 'Google yanıtları alındı ve yerel yanıt sayıları kontrol edildi.';
    plan = null;
  }

  Future<void> _yanitlariSifirla() async {
    await _kontrol();
    final id = formId;
    final ad = (proje?['baslik'] ?? form?['Baslik'] ?? 'Seçili form').toString();
    final onaylandi = await _onay(
      'Proje yanıtlarını sıfırla',
      '"$ad" formunun yalnız SQLite\'daki yanıtları, tercih onayları '
      've ders dağıtımı/sonuçlandırma kayıtları kalıcı olarak temizlenecek. '
      'Google Form yanıtları, öğrenci ana kayıtları ve diğer formlar korunacak. '
      'Sonrasında Yanıtları Getir ile cevapları yeniden alabilirsiniz. '
      'Devam etmek istiyor musunuz?',
    );
    if (!onaylandi) return;
    await _kontrol();
    if (proje == null || formId != id) {
      throw StateError('Sıfırlama öncesi seçili form değişti.');
    }
    await widget.service.projeYanitlariniSifirla(b, atama, id);
    plan = null;
    manuelPlan = null;
    analiz = null;
    dogrudanYanitlar = null;
    dogrudanUyari = null;
    onaySecimi.clear();
    _yanitSeciminiKapat();
    dagitimAsamasi = 0;
    await _yukle();
    sonuc = 'Seçili formun yerel yanıtları ve proje onay/dağıtımı sıfırlandı. '
        'Google Form değişmedi. Yanıtları Getir ile güncel cevapları alın.';
  }

  // Tercih denetiminden önce Google'daki silmeleri yerel kayda yansıt.
  // Ağ/izin hatasında yerel verileri silme; eski durumun doğrulanamadığını bildir.
  Future<void> _pasifOgrenciyiCikar(Map<String, dynamic> row) async {
    final oid = row['OgrenciId'] as int?;
    if (oid == null || (row['OgrenciAktif'] == 1 && row['KayitAktif'] == 1)) {
      throw StateError('Yalnız pasif öğrenciler proje listesinden çıkarılabilir.');
    }
    final id = formId;
    final ad = '${row['OkulNo']} • ${row['Ad']} ${row['Soyad']}';
    if (!await _onay(
      'Pasif öğrenciyi projeden çıkar',
      '$ad yalnızca seçili proje ödevinin öğrenci listesinden çıkarılacak. '
      'Google Form yanıtı, okul öğrenci kaydı ve diğer projeler korunacak. '
      'Varsa mevcut ders dağıtımı yeniden onay gerektirecek. Devam edilsin mi?',
    )) {
      return;
    }
    await _kontrol();
    if (proje == null || formId != id) {
      throw StateError('Proje seçimi değişti. İşlem durduruldu.');
    }
    await widget.service.projePasifOgrenciyiCikar(b, atama, id, oid);
    onaySecimi.remove(oid);
    plan = null;
    manuelPlan = null;
    kriterDegisti = false;
    dagitimAsamasi = 0;
    await _yukle();
    sonuc = '$ad seçili proje listesinden çıkarıldı.';
  }

  Future<void> _tercihleriAc() async {
    if (!salt && form?['Durum'] == 'Aktif') {
      try {
        await _yanitAl();
      } catch (e) {
        await _yukle();
        hata =
            'Google yanıtları güncellenemedi; eski kayıtlar korunuyor. '
            'Mükerrer yanıt durumu henüz doğrulanmadı. Orijinal hata: $e';
      }
    } else {
      await _yukle();
    }
    ekran = 2;
    _yanitSeciminiKapat();
  }

  Future<void> _dogrudanYukle() async {
    await _kontrol();
    final fid = formId;
    late final List<Map<String, dynamic>> rows;
    try {
      rows = await google.dogrudanYanitlariAl(fs, fb!, fid, await _token());
    } catch (_) {
      await _kontrol();
      if (!mounted || proje?['formId'] != fid) {
        throw StateError('Form seçimi değişti.');
      }
      dogrudanYanitlar = null;
      _yanitSeciminiKapat();
      dogrudanUyari =
          'Kaydedilmiş yanıtlar görüntüleniyor. Google’daki silme hedefleri '
          'doğrulanamadığı için silme kapalı; yanıtları yenilemeye devam edebilirsiniz.';
      return;
    }
    dogrudanUyari = null;
    await _kontrol();
    if (!mounted || proje?['formId'] != fid) {
      throw StateError('Form seçimi değişti.');
    }
    final sorted = rows.toList()
      ..sort((a, b) {
        final aNo = _dogrudanOkulNo(a), bNo = _dogrudanOkulNo(b);
        if (aNo != null && bNo != null && aNo != bNo) return aNo.compareTo(bNo);
        if (aNo != null && bNo == null) return -1;
        if (aNo == null && bNo != null) return 1;
        final ad = _dogrudanBaslik(a).compareTo(_dogrudanBaslik(b));
        if (ad != 0) return ad;
        return (b['submittedTime'] as String).compareTo(
          a['submittedTime'] as String,
        );
      });
    dogrudanYanitlar = sorted;
    dogrudanSecim.removeWhere(
      (id, imza) =>
          !sorted.any((r) => r['responseId'] == id && jsonEncode(r) == imza),
    );
  }

  String _dogrudanBaslik(Map<String, dynamic> row) {
    final answers = row['answers'] as List;
    if (answers.isEmpty) return 'Google yanıtı';
    final values = (answers.first as Map)['values'] as List;
    return values.join(' • ');
  }

  // Yalnız görünüm sırası içindir; silme kimliği olarak kullanılmaz.
  int? _dogrudanOkulNo(Map<String, dynamic> row) {
    final parts = _dogrudanBaslik(row).split(' • ');
    return int.tryParse(parts.length >= 3 ? parts[1] : parts.first);
  }

  Future<void> _dogrudanSil() async {
    await _kontrol();
    final fid = formId;
    final secim = Map<String, String>.of(dogrudanSecim);
    final snapshots = [
      for (final r in dogrudanYanitlar ?? <Map<String, dynamic>>[])
        if (secim[r['responseId']] == jsonEncode(r)) r,
    ];
    if (snapshots.isEmpty || snapshots.length != secim.length) {
      throw StateError('Seçili Google yanıtları değişti. Listeyi yenileyin.');
    }
    final token = await _token();
    // Bu plan sadece form kapsamını taşır; native kimlikler yerel REST
    // kayıtlarıyla eşlenmez veya onların yerine yazılmaz.
    final silme = await fs.topluSilmePlani(
      fb!,
      fid,
      sadeceKaydedilenler: false,
      seciliYanitIdleri: {},
    );
    final metin = snapshots
        .map(
          (r) =>
              '${_dogrudanBaslik(r)}\n'
              'Gönderim: ${_tarihYaz(r['submittedTime'] as String)}\n'
              '${(r['answers'] as List).map((a) => '${a['title']}: ${(a['values'] as List).join(', ')}').join('\n')}',
        )
        .join('\n\n');
    if (!mounted ||
        !await _onay(
          'Seçili yanıtları sil',
          '$metin\n\n${snapshots.length} seçili yanıt Google Forms’dan kalıcı olarak silinecek. '
              'Yanıt değişirse silme durur. Google’da yokluğu doğrulanan ham kayıtlar temizlenir. '
              'Öğrenci ana kayıtları ve onaylı bilgiler korunur. Tercih ve dağıtım sonuçları yeniden kontrol gerektirebilir. '
              'Google E-Tablo kopyaları ve eski yedekler silinmez.',
        )) {
      return;
    }
    await _kontrol();
    bool ayni() =>
        mounted &&
        proje?['formId'] == fid &&
        dogrudanSecim.length == secim.length &&
        secim.entries.every((e) => dogrudanSecim[e.key] == e.value);
    if (!ayni()) throw StateError('Yanıt seçimi değişti. Silme başlatılmadı.');
    silmeDurdur = false;
    late BilgiToplamaTopluSilmeSonucu silinen;
    setState(() => silmeIlerleme = 'Siliniyor: 0 / ${snapshots.length}');
    try {
      silinen = await google.yanitlariTopluSil(
        fs,
        fb!,
        silme,
        token,
        dogrudanHedefler: snapshots,
        devamEt: () => ayni() && !silmeDurdur,
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
    try {
      await _dogrudanYukle();
    } catch (_) {
      dogrudanYanitlar = null;
      _yanitSeciminiKapat();
      hata =
          'Güncel Google yanıt listesi alınamadı. Yenileyene kadar silme kapalı.';
    }
    if (dogrudanSecim.isEmpty) _yanitSeciminiKapat();
    plan = null;
    sonuc =
        '${silinen.googleSilinen} yanıt Google’dan silindi; '
        '${silinen.yokluguDogrulanan} yanıtın yokluğu doğrulandı; ${silinen.kalan} yanıt silinmedi. '
        '${silinen.yerelTemizlikTamam ? 'Yerel liste Google REST sonuçlarıyla yenilendi.' : 'Yerel temizlik doğrulanamadı; ham kayıtlar korundu.'}'
        '${silinen.hatalar.isEmpty ? '' : '\n${silinen.hatalar.join('\n')}'}';
  }

  Widget _dogrudanListe() {
    final rows = dogrudanYanitlar;
    if (rows == null) {
      return _bilgi(
        'Yanıtları Getir ile Google yanıtlarını yükleyin. '
        'Silme, bu listede ilk seçtiğiniz gerçek Google yanıtı üzerinde yapılır.',
      );
    }
    final gorulen = <String>{};
    final sonYanitlar = {
      for (final row in rows)
        if (gorulen.add(
          _dogrudanOkulNo(row)?.toString() ?? _dogrudanBaslik(row),
        ))
          row['responseId'],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Tercih onayları ve yerel düzeltmeler Tercih Kontrolü bölümündedir.',
        ),
        if (yanitSecimModu)
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Tümünü seç (${dogrudanSecim.length}/${rows.length})',
                  ),
                  value: rows.isNotEmpty && dogrudanSecim.length == rows.length,
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          dogrudanSecim.clear();
                          if (v == true) {
                            for (final r in rows) {
                              dogrudanSecim[r['responseId'] as String] =
                                  jsonEncode(r);
                            }
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
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Google’da yanıt yok.'),
          ),
        for (final row in rows)
          Card(
            key: ValueKey('google-yanit-${row['responseId']}'),
            child: ListTile(
              leading: yanitSecimModu
                  ? Checkbox(
                      value: dogrudanSecim.containsKey(row['responseId']),
                      onChanged: busy ? null : (_) => _dogrudanSec(row),
                    )
                  : const Icon(Icons.assignment_outlined),
              title: Text(
                _dogrudanBaslik(row),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final a in row['answers'] as List)
                    Text('${a['title']}: ${(a['values'] as List).join(', ')}'),
                  Text(
                    'Gönderim: ${_tarihYaz(row['submittedTime'] as String)}',
                  ),
                  if (sonYanitlar.contains(row['responseId']))
                    const Text(
                      'Son yanıt',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              onLongPress: busy ? null : () => _dogrudanSec(row),
              onTap: busy ? null : () => _dogrudanSec(row),
            ),
          ),
      ],
    );
  }

  void _dogrudanSec(Map<String, dynamic> row) => setState(() {
    yanitSecimModu = true;
    final id = row['responseId'] as String;
    if (dogrudanSecim.containsKey(id)) {
      dogrudanSecim.remove(id);
    } else {
      dogrudanSecim[id] = jsonEncode(row);
    }
  });

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

  // Her Google yanıtını ayrı tut; aynı öğrencinin geçmişini birleştirme.
  // Google zaman damgası yerel kayıt oluşturma tarihinden önceliklidir.
  List<Map<String, dynamic>> get yanitSatirlari {
    final satirlar = hamYanitlar.map((y) {
      final raw = jsonDecode(y['HamYanit'] as String) as Map;
      final googleZamani =
          raw['lastSubmittedTime']?.toString() ?? raw['createTime']?.toString();
      final zaman =
          DateTime.tryParse(googleZamani ?? '') ??
          DateTime.tryParse(y['OlusturmaTarihi']?.toString() ?? '');
      final okulNo = y['GirilenOkulNo']?.toString().trim() ?? '';
      return {
        ..._yanitSatiri(y),
        'gonderimZamani': googleZamani,
        'gorunumZamani': zaman,
        'ogrenciAnahtari': okulNo,
      };
    }).toList();
    satirlar.sort((a, b) {
      final aNo = a['ogrenciAnahtari'] as String;
      final bNo = b['ogrenciAnahtari'] as String;
      final aSayi = int.tryParse(aNo);
      final bSayi = int.tryParse(bNo);
      // Okul numarası sayısal artan; tanınmayan numaralar sonda.
      if (aSayi != null && bSayi != null) {
        final noKarsilastirma = aSayi.compareTo(bSayi);
        if (noKarsilastirma != 0) return noKarsilastirma;
      } else if (aSayi != null) {
        return -1;
      } else if (bSayi != null) {
        return 1;
      } else {
        final noKarsilastirma = aNo.compareTo(bNo);
        if (noKarsilastirma != 0) return noKarsilastirma;
      }
      // Aynı öğrencinin yanıtları en yeniden eskiye sıralanır.
      final x = a['gorunumZamani'] as DateTime?;
      final y = b['gorunumZamani'] as DateTime?;
      if (x == null) return y == null ? 0 : 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    final gorulen = <String>{};
    for (final satir in satirlar) {
      final okulNo = satir['ogrenciAnahtari'] as String;
      satir['sonYanit'] = okulNo.isNotEmpty && gorulen.add(okulNo);
    }
    return satirlar;
  }

  Map<String, dynamic> _yanitSatiri(Map<String, Object?> y) {
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
  }

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
    dogrudanSecim.clear();
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
    if (dogrudanIsteniyor && !dogrudanAktif) {
      throw StateError(
        'Google’daki silme hedefleri doğrulanamadı. Yanıtlar korunuyor.',
      );
    }
    await _kontrol();
    _secilenYanitlariDogrula();
    final secilen = Map<int, String>.of(yanitSecimi);
    final secilenGoogleIdleri = {
      for (final y in hamYanitlar.where((y) => secilen.containsKey(y['Id'])))
        y['Id'] as int: y['GoogleYanitId'],
    };
    final hedefFormId = formId;
    final token = await _token();
    await google.yanitlariAl(fs, fb!, formId, token);
    final guncel = await fs.yanitlar(fb!, formId);
    // Senkronizasyon ham kayıtları temizlemiş olabilir; hata/erken dönüşte de
    // eski satırları ekranda bırakma. Aynı Google kimliğinin yeni sürümü korunur.
    await _yukle();
    final temizlenenler = secilen.keys
        .where(
          (id) =>
              !guncel.any((y) => y['GoogleYanitId'] == secilenGoogleIdleri[id]),
        )
        .toSet();
    secilen.removeWhere((id, _) => temizlenenler.contains(id));
    if (secilen.isEmpty) {
      _yanitSeciminiKapat();
      sonuc =
          '${temizlenenler.length} seçili yanıtın Google’da yokluğu doğrulandı; '
          'ham kayıtları temizlendi. Diğer yanıtlar korundu.';
      return;
    }
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
    final hedefler = yanitSatirlari
        .where((r) => secilen.containsKey(r['yanitId']))
        .map(
          (r) =>
              '${r['OkulNo']} • ${r['Ad']} ${r['Soyad']} • '
              '${_tarihYaz(r['gonderimZamani'] as String?)}',
        )
        .join('\n');
    if (!await _onay(
      'Seçili yanıtları sil',
      '$hedefler\n\n${silme.toplam} yanıt Google Forms’dan ve uygulamadaki ham cevaplardan kalıcı olarak silinecek. '
          'Bu yanıtların tercih onayları ve dağıtım sonuçları yeniden kontrol gerektirecek. '
          'Öğrenci ana kayıtları korunur. Google E-Tablo kopyaları ve eski yedekler silinmez.',
    )) {
      return;
    }
    await _kontrol();
    bool secimAyni() =>
        mounted &&
        proje?['formId'] == hedefFormId &&
        yanitSecimi.length == secilen.length &&
        secilen.entries.every((e) => yanitSecimi[e.key] == e.value);
    if (!secimAyni()) {
      throw StateError('Yanıt seçimi değişti. Silme başlatılmadı.');
    }
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
        devamEt: () => secimAyni() && !silmeDurdur,
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
        '${silinen.googleSilinen} yanıt silindi; ${silinen.kalan} yanıt kaldı. '
        '${silinen.yokluguDogrulanan + temizlenenler.length} yanıtın Google’da yokluğu doğrulanarak ham kayıtları temizlendi; '
        '${silinen.kalan} yanıt korundu (${silinen.hatalar.length} başarısız, '
        '${silinen.durdurulan} işlenmedi).${silinen.hatalar.isEmpty ? '' : '\n${silinen.hatalar.join('\n')}'}';
  }

  /// Sadece tek bir REST yanıt kimliği seçilmişken çalışır.
  /// Aynı öğrencinin diğer yanıtları hedefe dahil edilmez.
  String _tekSeciliGoogleYanitId() {
    _secilenYanitlariDogrula();
    if (yanitSecimi.length != 1) {
      throw StateError('Manuel silme için yalnız bir yanıt seçin.');
    }
    final secim = yanitSecimi.entries.single;
    final kayit = hamYanitlar.singleWhere(
      (y) => y['Id'] == secim.key && y['KaynakSurum'] == secim.value,
    );
    final id = kayit['GoogleYanitId']?.toString() ?? '';
    if (id.isEmpty) throw StateError('Seçilen Google yanıt kimliği eksik.');
    return id;
  }

  Future<void> _seciliGoogleFormdaAc() async {
    await _kontrol();
    _tekSeciliGoogleYanitId();
    final googleFormId = form?['GoogleFormId']?.toString() ?? '';
    if (!RegExp(r'^[a-zA-Z0-9_-]{10,300}$').hasMatch(googleFormId)) {
      throw StateError('Google Form kimliği geçersiz. Form açılmadı.');
    }
    final uri = Uri.https('docs.google.com', '/forms/d/$googleFormId/edit');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Google Forms düzenleme ekranı açılamadı.');
    }
    sonuc =
        'Google Forms açıldı. Yanıtlar > Bireysel bölümünde '
        'seçtiğiniz yanıtın öğrenci, gönderim zamanı ve cevaplarını '
        'kontrol ederek yalnız o yanıtı silin. '
        'Ardından uygulamaya dönüp silinmeyi doğrulayın.';
  }

  Future<void> _seciliSilinmeyiDogrula() async {
    await _kontrol();
    final id = _tekSeciliGoogleYanitId();
    final secim = yanitSecimi.entries.single;
    final satir = yanitSatirlari.singleWhere(
      (r) => r['yanitId'] == secim.key && r['kaynakSurum'] == secim.value,
    );
    if (!await _onay(
      'Google’da silinmeyi doğrula',
      'Seçili yanıt: ${satir['OkulNo']} • ${satir['Ad']} ${satir['Soyad']}\n'
          'Gönderim: ${_tarihYaz(satir['gonderimZamani'] as String?)}\n\n'
          'Bu yanıtı Google Forms üzerinden sildiyseniz devam edin. '
          'Uygulama yalnız bu yanıtın artık Google’da bulunmadığını '
          'kontrol edecek. Aynı öğrencinin diğer yanıtları korunacak.',
    )) {
      return;
    }
    if (!mounted) return;
    await _kontrol();
    if (_tekSeciliGoogleYanitId() != id) {
      throw StateError('Yanıt seçimi değişti. Hiçbir kayıt temizlenmedi.');
    }
    final plan = await fs.topluSilmePlani(
      fb!,
      formId,
      sadeceKaydedilenler: false,
      seciliYanitIdleri: {secim.key},
    );
    if (plan.toplam != 1 ||
        plan.googleYanitIdleri.length != 1 ||
        plan.googleYanitIdleri.single != id) {
      throw StateError(
        'Yanıt eşleştirmesi kesin değil. Hiçbir kayıt temizlenmedi.',
      );
    }
    final token = await _token();
    await fs.topluSilmeYanitiSil(
      fb!,
      plan,
      id,
      googleSil: (formId, responseId) =>
          google.googleSilinmesiniDogrula(token, formId, responseId),
    );
    await _kontrol();
    await _yukle();
    this.plan = null;
    sonuc =
        'Yalnız seçili yanıtın Google’da silindiği doğrulandı. '
        'Uygulamadaki ham verileri temizlendi; diğer yanıtlar korundu.';
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
    kriterDegisti = false;
    await _yukle();
  }

  Future<bool> _onay(String ad, String metin) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(ad),
          content: SingleChildScrollView(child: Text(metin)),
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

  Future<bool> _dagitimTercihleriniHazirla() async {
    await _kontrol();
    await _yukle();
    final yeniOnay = {
      for (final r in tercihler.where(
        (r) => (r['hatalar'] as List).isEmpty && r['onayli'] != true,
      ))
        r['OgrenciId'] as int: r['imza'] as String,
    };
    if (yeniOnay.isNotEmpty) {
      if (!mounted ||
          !await _onay(
            'Dağıtım için tercihleri onayla',
            '${yeniOnay.length} öğrencinin geçerli üç tercihi onaylanacak. Hatalı ve eksik yanıtlar dağıtıma alınmayacak.',
          )) {
        return false;
      }
      await widget.service.projeTercihleriniOnayla(b, atama, formId, yeniOnay);
      await _yukle();
      plan = null;
    }
    if (!tercihler.any((r) => r['onayli'] == true)) {
      throw StateError(
        'Dağıtılacak geçerli tercih yok. Önce yanıtları kontrol edin.',
      );
    }
    return true;
  }

  Future<void> _kontenjanOnerisiniUygula() async {
    final mevcutPlan = plan;
    if (!kontenjan || mevcutPlan == null) return;
    final artislar = Map<String, dynamic>.from(
      mevcutPlan['kontenjanOnerisi'] as Map? ?? {},
    );
    if (artislar.isEmpty) return;
    final aciklama = artislar.entries.map((e) {
      final id = int.parse(e.key);
      final eski = kapasite[id] ?? 0;
      return '${projeDersleri[id]}: $eski → ${eski + (e.value as int)}';
    }).join('\n');
    final kimlik = formId;
    if (!await _onay(
      'Kontenjan artırma önerisi',
      'Öğrenciler tercih etmedikleri derslere atanmayacak. '
      'Açıkta kalan geçerli ve onaylı öğrenciler için şu kontenjanları '
      'artırmayı öneriyorum:\n\n$aciklama\n\n'
      'Onaylarsanız yalnız bu ekrandaki kontenjanlar değiştirilerek '
      'dağıtım yeniden hesaplanacak. Kesin kayıt için ayrıca '
      'Dağıtımı Onayla gerekir.',
    )) {
      return;
    }
    await _kontrol();
    if (proje == null || formId != kimlik || !identical(plan, mevcutPlan)) {
      throw StateError('Dağıtım veya proje değişti; öneriyi yeniden hesaplayın.');
    }
    for (final e in artislar.entries) {
      final id = int.parse(e.key);
      kapasite[id] = (kapasite[id] ?? 0) + (e.value as int);
    }
    kapasiteSurumu++;
    await _dagit();
    dagitimAsamasi = 1;
  }

  Future<void> _otomatikDagit() async {
    if (!await _dagitimTercihleriniHazirla()) return;
    await _dagit();
    dagitimAsamasi = 1;
    if (kontenjan && (plan?['kontenjanOnerisi'] as Map? ?? {}).isNotEmpty) {
      await _kontenjanOnerisiniUygula();
    }
  }

  Future<void> _manuel() async {
    if (!await _dagitimTercihleriniHazirla()) return;
    final temel = await widget.service.projeDagitimOnizle(
      b,
      atama,
      formId,
      kontenjan ? kapasite : null,
    );
    final aday =
        plan?['dagitim'] as Map? ??
        (dagitimGuncel ? proje!['dagitim'] as Map : <String, dynamic>{});
    final d = <String, dynamic>{};
    for (final r in tercihler.where((r) => r['onayli'] == true)) {
      final oid = '${r['OgrenciId']}';
      final ders = aday[oid];
      if (!(r['tercihler'] as List).contains(ders)) continue;
      if (!kontenjan ||
          d.values.where((v) => v == ders).length < (kapasite[ders] ?? 0)) {
        d[oid] = ders;
      }
    }
    manuelPlan = {...temel, 'dagitim': d};
    dagitimAsamasi = 2;
    dagitimArama.clear();
  }

  Future<void> _manuelUygula() async {
    if (manuelPlan == null) return;
    await _kontrol();
    plan = jsonDecode(jsonEncode(manuelPlan)) as Map<String, dynamic>;
    plan!['acikta'] = tercihler
        .where(
          (r) =>
              r['onayli'] == true &&
              !(plan!['dagitim'] as Map).containsKey('${r['OgrenciId']}'),
        )
        .length;
    manuelPlan = null;
    dagitimAsamasi = 1;
  }

  void _kriterDegisti() {
    plan = null;
    manuelPlan = null;
    dagitimAsamasi = 0;
    kriterDegisti = true;
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
              : (s) => _is(() async {
                  if (s.single == 2) {
                    // Değerlendirmede ilk adım doğrudan Tercih Kontrolü.
                    await _tercihleriAc();
                    return;
                  }
                  sekme = s.single;
                  _yanitSeciminiKapat();
                  if (sekme == 1) {
                    await _yanitAlimiDurumunuKontrolEt();
                    if (dogrudanIsteniyor) await _dogrudanYukle();
                  }
                }),
        ),
        const SizedBox(height: 12),
        if (dogrudanUyari != null) _bilgi(dogrudanUyari!),
        if (sekme == 1 && form?['GoogleFormId'] != null)
          Card(
            color: (googleYanitAcik ?? form?['Durum'] == 'Aktif')
                ? const Color(0xffe7f6e9)
                : const Color(0xffffecec),
            child: ListTile(
              leading: Icon(
                (googleYanitAcik ?? form?['Durum'] == 'Aktif')
                    ? Icons.check_circle_outline
                    : Icons.lock_outline,
                color: (googleYanitAcik ?? form?['Durum'] == 'Aktif')
                    ? const Color(0xff008a24)
                    : const Color(0xffbd3030),
              ),
              title: Text(
                (googleYanitAcik ?? form?['Durum'] == 'Aktif')
                    ? 'Yanıt alımı açık'
                    : 'Yanıt alımı kapalı',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                googleYanitAcik == null
                    ? 'Yerel kaydedilmiş durum • Google durumunu kontrol etmek için Yanıtlar sekmesini açın.'
                    : googleYanitAcik!
                        ? 'Google Form yeni yanıtları kabul ediyor.'
                        : 'Google Form yeni yanıt kabul etmiyor. Mevcut cevaplar korunuyor.',
              ),
            ),
          ),
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
        else if (dogrudanAktif)
          _dogrudanListe()
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
                    Text(
                      'Gönderim: ${_tarihYaz(r['gonderimZamani'] as String?)}'
                      '${r['gonderimZamani'] == null ? ' (yerel kayıt zamanı: ${_tarihYaz((r['gorunumZamani'] as DateTime?)?.toIso8601String())})' : ''}',
                    ),
                    if (r['sonYanit'] == true)
                      const Text(
                        'Son yanıt',
                        style: TextStyle(fontWeight: FontWeight.bold),
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

  Widget _degerlendirme() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _dagitim(),
      if (dagitimAsamasi != 2 &&
          dagitimGuncel &&
          !kriterDegisti &&
          plan == null)
        ExpansionTile(
          key: ValueKey('sonuc-bildirimi-${analiz?['sonuclandi']}'),
          initiallyExpanded: analiz?['sonuclandi'] == true,
          title: const Text('Sonuçlandırma ve Öğretmen Bildirimi'),
          children: [_degerlendirmeSonucu()],
        ),
    ],
  );

  Widget _degerlendirmeSonucu() {
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
                _tercihleriAc,
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
              secondary: !salt &&
                      r['OgrenciId'] != null &&
                      (r['OgrenciAktif'] != 1 || r['KayitAktif'] != 1)
                  ? IconButton(
                      tooltip: 'Pasif öğrenciyi proje listesinden çıkar',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: busy
                          ? null
                          : () => _is(() => _pasifOgrenciyiCikar(r)),
                    )
                  : !salt && r['yanitId'] != null
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

  Map get _gorunenDagitim => dagitimAsamasi == 2
      ? (manuelPlan?['dagitim'] as Map? ?? {})
      : (plan?['dagitim'] as Map? ??
            (dagitimGuncel && !kriterDegisti ? proje!['dagitim'] as Map : {}));

  Widget _dagitim() {
    final an = analiz;
    if (an == null) return _bilgi('Analiz için verileri yenileyin.');
    final d = _gorunenDagitim;
    final gecerli = an['gecerli'] as int;
    final sorunlu = an['sorunlu'] as int;
    final bekleyen = an['bekleyen'] as int;
    final onayli = tercihler.where((r) => r['onayli'] == true).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kart(
          '${widget.atama['SinifKodu']} • ${an['toplam']} öğrenci',
          Icons.groups_outlined,
          [
            if (dagitimAsamasi != 2)
              _istatistik(
                dagitimAsamasi == 0
                    ? [
                        ('Geçerli', gecerli, Colors.green),
                        ('Kontrol', sorunlu, Colors.orange),
                        ('Toplam', an['toplam'] as int, Colors.blue),
                      ]
                    : [
                        ('Yerleşen', d.length, Colors.green),
                        ('Açıkta', max(0, onayli - d.length), Colors.blue),
                        ('Kontrol', sorunlu, Colors.orange),
                      ],
              ),
            if (bekleyen > 0) Text('$bekleyen öğrenci için yanıt bekleniyor.'),
          ],
        ),
        if (dagitimAsamasi == 0) ...[
          Card(
            child: ExpansionTile(
              key: ValueKey('dagitim-kriterleri-$formId'),
              initiallyExpanded: false,
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Dağıtım Kriterleri'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Kontenjan kullan'),
                        value: kontenjan,
                        onChanged: salt || busy
                            ? null
                            : (v) => setState(() {
                                kontenjan = v;
                                _kriterDegisti();
                              }),
                      ),
                      const Text(
                        'Her dersin alabileceği en fazla öğrenci sayısı.',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Text('Ders')),
                          Text(kontenjan ? 'Maks. öğrenci' : 'Kontenjan'),
                        ],
                      ),
                      const Divider(),
                      for (final e in projeDersleri.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text(e.value)),
                              if (kontenjan) ...[
                                IconButton(
                                  tooltip: '${e.value} kontenjanını azalt',
                                  onPressed:
                                      salt ||
                                          busy ||
                                          (kapasite[e.key] ?? 0) == 0
                                      ? null
                                      : () => setState(() {
                                          kapasite[e.key] =
                                              (kapasite[e.key] ?? 0) - 1;
                                          kapasiteSurumu++;
                                          _kriterDegisti();
                                        }),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                SizedBox(
                                  width: 42,
                                  child: TextFormField(
                                    key: ValueKey(
                                      'kapasite-${e.key}-$kapasiteSurumu',
                                    ),
                                    initialValue: '${kapasite[e.key] ?? 0}',
                                    enabled: !salt && !busy,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(4),
                                    ],
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                    ),
                                    onChanged: (v) {
                                      setState(() {
                                        kapasite[e.key] = int.tryParse(v) ?? 0;
                                        _kriterDegisti();
                                      });
                                    },
                                  ),
                                ),
                                IconButton(
                                  tooltip: '${e.value} kontenjanını artır',
                                  onPressed: salt || busy
                                      ? null
                                      : () => setState(() {
                                          kapasite[e.key] =
                                              (kapasite[e.key] ?? 0) + 1;
                                          kapasiteSurumu++;
                                          _kriterDegisti();
                                        }),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ] else
                                const Text('Sınırsız'),
                            ],
                          ),
                        ),
                      const Divider(),
                      Text(
                        kontenjan
                            ? 'Toplam kapasite: ${kapasite.values.fold<int>(0, (a, b) => a + b)}'
                            : 'Kontenjan sınırı yok.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '• Önce 1., sonra 2. ve 3. tercihler\n• Her öğrenciye 1 proje dersi\n• Eşitlikte okul numarası sırası',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (sorunlu > 0 || bekleyen > 0)
            _bilgi(
              '$sorunlu hatalı yanıt ve $bekleyen bekleyen öğrenci dağıtıma alınmaz.',
              uyari: true,
            ),
        ] else if (dagitimAsamasi == 2) ...[
          _kart('Manuel Düzenleme', Icons.edit_outlined, [
            Wrap(
              spacing: 6,
              children: [
                for (final e in projeDersleri.entries)
                  Chip(
                    label: Text(
                      '${e.value}: ${d.values.where((v) => v == e.key).length}${kontenjan ? '/${kapasite[e.key] ?? 0}' : ''}',
                    ),
                  ),
              ],
            ),
            TextField(
              controller: dagitimArama,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Öğrenci adı veya numarası',
              ),
            ),
          ]),
          _bilgi(
            'Yalnız öğrencinin tercihleri seçilebilir. Kontenjan aşılamaz. Değişiklikler önce ön izlemeye uygulanır.',
          ),
          for (final r in tercihler.where(
            (r) => importNormalize(
              '${r['OkulNo']} ${r['Ad']} ${r['Soyad']}',
            ).contains(importNormalize(dagitimArama.text)),
          ))
            _manuelOgrenci(r, d),
        ] else ...[
          _kart('Ders Dağılımı', Icons.bar_chart, [
            const Row(
              children: [
                Expanded(child: Text('Ders')),
                Text('Yerleşen / Maks.'),
              ],
            ),
            const Divider(),
            for (final e in projeDersleri.entries) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(e.value)),
                    Text(
                      '${d.values.where((v) => v == e.key).length} / ${kontenjan ? kapasite[e.key] ?? 0 : '∞'}',
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: kontenjan
                    ? ((kapasite[e.key] ?? 0) == 0
                              ? 0.0
                              : d.values.where((v) => v == e.key).length /
                                    kapasite[e.key]!)
                          .clamp(0.0, 1.0)
                          .toDouble()
                    : (d.isEmpty
                          ? 0.0
                          : d.values.where((v) => v == e.key).length /
                                d.length),
                minHeight: 5,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '${d.length} öğrenci yerleştirildi. $sorunlu yanıt kontrol bekliyor.',
            ),
            Text(
              plan != null
                  ? 'Ön izleme • Henüz kaydedilmedi.'
                  : dagitimGuncel && !kriterDegisti
                  ? 'Kesin dağıtım kaydedildi.'
                  : 'Dağıtımı yeniden hazırlayın.',
            ),
          ]),
          if (kontenjan &&
              plan != null &&
              (plan!['kontenjanOnerisi'] as Map? ?? {}).isNotEmpty)
            _kart('Kontenjan Artırma Önerisi', Icons.info_outline, [
              const Text(
                'Açıkta kalan geçerli öğrenciler için tercih dışı atama '
                'yapılmayacak. Önerilen ek kontenjanları onaylayıp '
                'dağıtımı yeniden hesaplayabilirsiniz.',
              ),
              for (final e in (plan!['kontenjanOnerisi'] as Map).entries)
                Text(
                  '${projeDersleri[int.parse(e.key as String)]}: '
                  '+${e.value} öğrenci',
                ),
              _buton(
                'Önerilen Kontenjanları Uygula',
                Icons.add_circle_outline,
                _kontenjanOnerisiniUygula,
                ikincil: true,
              ),
            ]),
          _kart('Öğrenci Sonuçları', Icons.groups_outlined, [
            for (final r in tercihler)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  d.containsKey('${r['OgrenciId']}')
                      ? Icons.check_circle_outline
                      : Icons.pending_outlined,
                ),
                title: Text('${r['OkulNo']} • ${r['Ad']} ${r['Soyad']}'),
                subtitle: Text(
                  d.containsKey('${r['OgrenciId']}')
                      ? '${(r['tercihler'] as List).indexOf(d['${r['OgrenciId']}']) + 1}. tercihine yerleşti • ${projeDersleri[d['${r['OgrenciId']}']]}'
                      : (r['hatalar'] as List).isNotEmpty
                      ? (r['hatalar'] as List).join(' ')
                      : 'Yerleşmedi',
                ),
                onTap: busy || salt || r['yanitId'] == null
                    ? null
                    : () => _is(() => _tercihDuzenle(r)),
              ),
          ]),
          if (analiz?['sonuclanabilir'] != true)
            _bilgi(
              'Kesin sonuç için eksik yanıtları tamamlayın ve bütün öğrencileri yerleştirin.',
            ),
        ],
      ],
    );
  }

  Widget _manuelOgrenci(Map<String, dynamic> r, Map d) {
    final oid = '${r['OgrenciId']}';
    final seciliDers = d[oid] as int?;
    final ids = (r['tercihler'] as List).cast<int>();
    bool dolu(int id) =>
        kontenjan &&
        seciliDers != id &&
        d.values.where((v) => v == id).length >= (kapasite[id] ?? 0);
    return _kart(
      '${r['OkulNo']} • ${r['Ad']} ${r['Soyad']}',
      Icons.person_outline,
      [
        Text(
          'Tercihler: ${ids.indexed.map((e) => '${e.$1 + 1}. ${projeDersleri[e.$2]}').join(' • ')}',
        ),
        const SizedBox(height: 8),
        if (r['onayli'] == true)
          DropdownButtonFormField<int>(
            key: ValueKey('manuel-$oid-$seciliDers'),
            initialValue: seciliDers ?? 0,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Atanacak ders'),
            selectedItemBuilder: (c) => [
              const Text('Yerleştirme yok'),
              for (final id in ids)
                Text(projeDersleri[id]!, overflow: TextOverflow.ellipsis),
            ],
            items: [
              const DropdownMenuItem(value: 0, child: Text('Yerleştirme yok')),
              for (final id in ids)
                DropdownMenuItem(
                  value: id,
                  enabled: !dolu(id),
                  child: Text(
                    '${projeDersleri[id]}${dolu(id)
                        ? ' — Dolu'
                        : seciliDers == id
                        ? ' — Mevcut ders'
                        : kontenjan
                        ? ' — ${(kapasite[id] ?? 0) - d.values.where((v) => v == id).length} boş yer'
                        : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: busy || salt
                ? null
                : (id) => setState(() {
                    if (id == null || id == 0) {
                      d.remove(oid);
                    } else if (ids.contains(id) && !dolu(id)) {
                      d[oid] = id;
                    }
                  }),
          )
        else ...[
          Text(
            (r['hatalar'] as List).join(' '),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          if (r['yanitId'] != null && !salt)
            _buton(
              'Yanıtı Düzenle',
              Icons.edit_outlined,
              () => _tercihDuzenle(r),
              ikincil: true,
            ),
        ],
      ],
    );
  }

  List<Widget> _dagitimButonlari() => dagitimAsamasi == 2
      ? [
          _buton('Vazgeç', Icons.close, () async {
            manuelPlan = null;
            dagitimAsamasi = plan != null || dagitimGuncel && !kriterDegisti
                ? 1
                : 0;
          }, ikincil: true),
          _buton('Ön İzlemeye Uygula', Icons.check, _manuelUygula),
        ]
      : dagitimAsamasi == 0
      ? [
          _buton('Manuel Dağıt', Icons.edit_outlined, _manuel, ikincil: true),
          _buton('Otomatik Dağıt', Icons.play_arrow, _otomatikDagit),
        ]
      : [
          _buton('Kriterler', Icons.settings_outlined, () async {
            dagitimAsamasi = 0;
          }, ikincil: true),
          _buton('Manuel Düzenle', Icons.edit_outlined, _manuel, ikincil: true),
          _buton(
            'Dağıtımı Onayla',
            Icons.check,
            _dagitimKaydet,
            etkin: plan != null && (_gorunenDagitim).isNotEmpty,
            renk: const Color(0xff008a24),
          ),
        ];
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
    final ad = !yeni && detay && (ekran == 3 || ekran == 1 && sekme == 2)
        ? 'Değerlendirme'
        : yeni
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
      canPop: !busy && !yeni && !detay && !formSecimModu,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) {
          setState(() {
            if (formSecimModu) {
              _formSeciminiKapat();
              return;
            }
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
          leading: yeni || detay || formSecimModu
              ? IconButton(
                  tooltip: 'Proje taleplerine dön',
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          if (formSecimModu) {
                            _formSeciminiKapat();
                            return;
                          }
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
                  onSelected: (v) {
                    if (v == 2) {
                      _is(_tercihleriAc);
                    } else {
                      setState(() {
                        ekran = v;
                        _yanitSeciminiKapat();
                      });
                    }
                  },
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
              if (formSecimModu)
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Tümünü seç (${formSecimi.length}/${talepler.length})',
                        ),
                        value:
                            talepler.isNotEmpty &&
                            formSecimi.length == talepler.length,
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                formSecimi.clear();
                                if (v == true) {
                                  formSecimi.addAll(
                                    talepler.map((p) => p['formId'] as int),
                                  );
                                }
                              }),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Form seçimini kapat',
                      onPressed: busy
                          ? null
                          : () => setState(_formSeciminiKapat),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              for (final p in talepler)
                Card(
                  key: ValueKey('proje-form-${p['formId']}'),
                  child: ListTile(
                    selected: formSecimi.contains(p['formId']),
                    leading: formSecimModu
                        ? Checkbox(
                            value: formSecimi.contains(p['formId']),
                            onChanged: busy || salt
                                ? null
                                : (_) => _formSec(p['formId'] as int),
                          )
                        : const Icon(Icons.assignment_outlined),
                    title: Text(
                      '${p['baslik']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${(p['ogrenciler'] as List).length} öğrenci • ${widget.atama['SinifKodu']}',
                    ),
                    trailing: formSecimModu
                        ? null
                        : const Icon(Icons.chevron_right),
                    onLongPress: busy || salt
                        ? null
                        : () => _formSec(p['formId'] as int),
                    onTap: busy
                        ? null
                        : () => formSecimModu
                              ? _formSec(p['formId'] as int)
                              : _is(() => _formAc(p)),
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
            if (formSecimModu && !salt)
              _buton(
                'Seçilenleri Sil (${formSecimi.length})',
                Icons.delete_outline,
                _formlariSil,
                etkin: formSecimi.isNotEmpty,
                renk: const Color(0xffd92737),
              )
            else ...[
              _buton('Yenile', Icons.refresh, _yukle, ikincil: true),
              if (!salt) _buton('Form Talebi Oluştur', Icons.add, _yeni),
            ],
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
              ..._dagitimButonlari(),
              if (dagitimAsamasi != 2 &&
                  dagitimGuncel &&
                  !kriterDegisti &&
                  plan == null)
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
            ] else if (yanitSecimModu && dogrudanAktif) ...[
              _buton(
                'Toplu Sil (${dogrudanSecim.length})',
                Icons.delete_outline,
                _dogrudanSil,
                etkin: dogrudanSecim.isNotEmpty,
                ikincil: true,
                renk: const Color(0xffd92737),
              ),
              _buton('Yanıtları Getir', Icons.refresh, _yanitAl, ikincil: true),
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
                etkin:
                    yanitSecimi.isNotEmpty &&
                    (!dogrudanIsteniyor || dogrudanAktif),
                ikincil: true,
                renk: const Color(0xffd92737),
              ),
              if (yanitSecimi.length == 1) ...[
                _buton(
                  'Google Form’da Aç',
                  Icons.open_in_new,
                  _seciliGoogleFormdaAc,
                  ikincil: true,
                ),
                _buton(
                  'Google’da Silinmeyi Doğrula',
                  Icons.verified_outlined,
                  _seciliSilinmeyiDogrula,
                  ikincil: true,
                ),
              ],
            ] else ...[
              _buton('Yanıtları Getir', Icons.refresh, _yanitAl),
              if (sekme == 1 && form?['GoogleFormId'] != null)
                _buton(
                  (googleYanitAcik ?? form?['Durum'] == 'Aktif')
                      ? 'Yanıtları Kapat'
                      : 'Yanıtları Aç',
                  (googleYanitAcik ?? form?['Durum'] == 'Aktif')
                      ? Icons.lock_outline
                      : Icons.lock_open_outlined,
                  _yanitAliminiDegistir,
                  ikincil: true,
                  renk: (googleYanitAcik ?? form?['Durum'] == 'Aktif')
                      ? const Color(0xffb46b00)
                      : const Color(0xff008a24),
                ),
              if (sekme == 1)
                _buton(
                  'Sıfırla',
                  Icons.restart_alt,
                  _yanitlariSifirla,
                  ikincil: true,
                  renk: const Color(0xffd92737),
                ),
              _buton(
                'Hatırlatma Gönder',
                Icons.notifications_outlined,
                () => _gonder(hatirlat: true),
                ikincil: true,
              ),
            ],
          ] else if (ekran == 2 && !salt) ...[
            _buton('Google Yanıtlarını Yenile', Icons.refresh, _yanitAl),
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
            ..._dagitimButonlari(),
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
