import '../widgets/ortak_ui.dart';
import '../widgets/odev_ortak_alt_islemler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/odev_kontrol.dart';
import '../services/bireysel_liste_service.dart';
import '../services/bireysel_odev_kontrol_service.dart';
import 'odev_tanim_screen.dart';
import '../widgets/odev_puan_dialog.dart';
import '../widgets/odev_gorunum.dart';
import 'odev_ogrenci_gecmis_screen.dart';
import 'odev_ekler_screen.dart';
import 'ders_uygulama_screen.dart';

class OdevKontrolDetayScreen extends StatefulWidget {
  const OdevKontrolDetayScreen({
    super.key,
    required this.oturum,
    required this.odevId,
  });
  final BireyselListeOturumu oturum;
  final int odevId;

  @override
  State<OdevKontrolDetayScreen> createState() => _OdevKontrolDetayScreenState();
}

class _OdevKontrolDetayScreenState extends State<OdevKontrolDetayScreen> {
  OdevTanim? _gorev;
  List<OdevKontrol> _kontroller = [];
  Map<int, OdevOgrenci> _ogrenciler = {};
  List<OdevKontrolSonuc> _sonuclar = [];
  final Map<int, OdevKontrolDurumu> _durumlar = {};
  final Map<int, String> _notlar = {};
  final _puanlar = <int, int?>{}, _kayitliPuanlar = <int, int?>{};
  final _seciliOgrenciler = <int>{};
  String _arama = '';
  final _aramaGirdisi = TextEditingController();
  final Map<int, OdevKontrolDurumu> _kayitliDurumlar = {};
  final Map<int, String> _kayitliNotlar = {};
  int? _kontrolId;
  bool _bekle = true, _islem = false, _degisti = false, _cikisSoruluyor = false;
  String? _hata;
  bool _topluSecim = false, _aramaAcik = false;
  bool _bilgiAcik = false, _ogrencilerAcik = true;
  final _puanGirdileri = <int, TextEditingController>{};
  final _puanHatalari = <int>{};

  String _puanMetni(int? puan) => puan != null && puan >= 0 ? '$puan' : '';

  void _puanAta(int id, int? puan, {bool metniGuncelle = true}) {
    _puanlar[id] = puan;
    _durumlar[id] = OdevKontrolSonuc.notDurumu(puan, null);
    _puanHatalari.remove(id);
    if (metniGuncelle) _puanGirdileri[id]?.text = _puanMetni(puan);
    _degisiklikDurumunuGuncelle();
  }

  void _puanGir(int id, String metin) {
    final puan = int.tryParse(metin);
    setState(() {
      if (metin.isNotEmpty && (puan == null || puan < 0 || puan > 10)) {
        _puanHatalari.add(id);
        _degisiklikDurumunuGuncelle();
      } else {
        _puanAta(id, puan, metniGuncelle: false);
      }
    });
  }

  @override
  void dispose() {
    for (final c in _puanGirdileri.values) {
      c.dispose();
    }
    _aramaGirdisi.dispose();
    super.dispose();
  }

  bool _ogrenciDegisti(int ogrenciId) =>
      _durumlar[ogrenciId] != _kayitliDurumlar[ogrenciId] ||
      (_notlar[ogrenciId] ?? '') != (_kayitliNotlar[ogrenciId] ?? '') ||
      _puanlar[ogrenciId] != _kayitliPuanlar[ogrenciId];

  void _degisiklikDurumunuGuncelle() {
    _degisti =
        _puanHatalari.isNotEmpty ||
        _sonuclar.any((s) => _ogrenciDegisti(s.ogrenciId));
  }

  void _durumDegistir(int ogrenciId, OdevKontrolDurumu durum) {
    setState(() {
      _durumlar[ogrenciId] = durum;
      _puanlar[ogrenciId] = OdevKontrolSonuc.hizliNot(durum);
      _puanGirdileri[ogrenciId]?.text = _puanMetni(_puanlar[ogrenciId]);
      _puanHatalari.remove(ogrenciId);
      _degisiklikDurumunuGuncelle();
    });
  }

  void _tumuneUygula(OdevKontrolDurumu durum, {Set<int>? hedef, int? puan}) {
    if (_islem || _sonuclar.isEmpty) return;
    final oncekiDurumlar = Map<int, OdevKontrolDurumu>.from(_durumlar);
    final oncekiPuanlar = Map<int, int?>.of(_puanlar);
    final kontrolId = _kontrolId;
    final uygulanan = puan ?? OdevKontrolSonuc.hizliNot(durum);
    setState(() {
      for (final s in _sonuclar.where(
        (s) => hedef == null || hedef.contains(s.ogrenciId),
      )) {
        _durumlar[s.ogrenciId] = durum;
        _puanlar[s.ogrenciId] = puan ?? OdevKontrolSonuc.hizliNot(durum);
        _puanGirdileri[s.ogrenciId]?.text = _puanMetni(_puanlar[s.ogrenciId]);
        _puanHatalari.remove(s.ogrenciId);
      }
      _degisiklikDurumunuGuncelle();
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${hedef?.length ?? _sonuclar.length} öğrenciye ${durum.sembol} (${durum.baslik}) uygulandı.',
        ),
        action: SnackBarAction(
          label: 'Geri Al',
          onPressed: () {
            if (!mounted || _kontrolId != kontrolId) return;
            setState(() {
              for (final entry in oncekiDurumlar.entries) {
                if ((hedef == null || hedef.contains(entry.key)) &&
                    _durumlar[entry.key] == durum &&
                    _puanlar[entry.key] == uygulanan) {
                  _durumlar[entry.key] = entry.value;
                  _puanlar[entry.key] = oncekiPuanlar[entry.key];
                  _puanGirdileri[entry.key]?.text = _puanMetni(
                    oncekiPuanlar[entry.key],
                  );
                }
              }
              _degisiklikDurumunuGuncelle();
            });
          },
        ),
      ),
    );
  }

  Future<void> _excelAktar() async {
    if (_islem || _bekle || _gorev == null) return;
    if (_degisti) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Excel’e aktarmadan önce kontrolleri kaydedin.'),
        ),
      );
      return;
    }
    setState(() => _islem = true);
    try {
      final yol = await BireyselOdevKontrolService.gorevDetayExcelAktar(
        widget.oturum,
        widget.odevId,
      );
      if (mounted && yol != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel kaydedildi: $yol')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Kontroller aktarılamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _aciklamaDuzenle(OdevOgrenci ogrenci, bool yazilabilir) async {
    var aciklama = _notlar[ogrenci.ogrenciId] ?? '';
    final sonuc = await odevDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${ogrenci.okulNo} • ${ogrenci.adSoyad}'),
        content: TextFormField(
          initialValue: aciklama,
          onChanged: (deger) => aciklama = deger,
          readOnly: !yazilabilir,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Öğrenci açıklaması'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
          if (yazilabilir)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, aciklama),
              child: const Text('Uygula'),
            ),
        ],
      ),
    );
    if (mounted && sonuc != null && sonuc != _notlar[ogrenci.ogrenciId]) {
      setState(() {
        _notlar[ogrenci.ogrenciId] = sonuc;
        _degisiklikDurumunuGuncelle();
      });
    }
  }

  bool get _olcutluGorev =>
      _gorev?.gorevTuru == OdevGorevTuru.proje ||
      _gorev?.gorevTuru == OdevGorevTuru.performans;

  Future<void> _olcutleriDuzenle() async {
    if (_kontrolId == null || _degisti) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce bekleyen kontrol değişikliklerini kaydedin.'),
        ),
      );
      return;
    }
    final id = _kontrolId!;
    try {
      final eski = await BireyselOdevKontrolService.degerlendirmeOlcutleri(
        widget.oturum,
        id,
      );
      if (!mounted || id != _kontrolId) return;
      final satirlar = <Map<String, TextEditingController>>[
        for (final o in eski)
          {
            'ad': TextEditingController(text: o['Baslik'] as String),
            'puan': TextEditingController(text: '${o['AzamiPuan']}'),
          },
      ];
      if (satirlar.isEmpty) {
        satirlar.add({
          'ad': TextEditingController(),
          'puan': TextEditingController(),
        });
      }
      try {
        final kaydet = await odevDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, yenile) => AlertDialog(
              title: const Text('Değerlendirme ölçütleri'),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Bu aşamanın ölçütlerini ve azami puanlarını belirleyin. '
                        'Tüm aşamaların toplamı 100 puanı geçemez.',
                      ),
                      for (var i = 0; i < satirlar.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: satirlar[i]['ad'],
                                  maxLength: 150,
                                  decoration: InputDecoration(
                                    labelText: '${i + 1}. ölçüt',
                                    counterText: '',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 72,
                                child: TextField(
                                  controller: satirlar[i]['puan'],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Puan',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Ölçütü kaldır',
                                onPressed: satirlar.length <= 1
                                    ? null
                                    : () => yenile(() => satirlar.removeAt(i)),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            ],
                          ),
                        ),
                      TextButton.icon(
                        onPressed: satirlar.length >= 20
                            ? null
                            : () => yenile(() {
                                satirlar.add({
                                  'ad': TextEditingController(),
                                  'puan': TextEditingController(),
                                });
                              }),
                        icon: const Icon(Icons.add),
                        label: const Text('Ölçüt ekle'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Kaydet'),
                ),
              ],
            ),
          ),
        );
        if (kaydet != true || !mounted || id != _kontrolId) return;
        final giris = [
          for (final satir in satirlar)
            <String, Object?>{
              'Baslik': satir['ad']!.text.trim(),
              'AzamiPuan': int.tryParse(satir['puan']!.text.trim()),
            },
        ];
        await BireyselOdevKontrolService.degerlendirmeOlcutleriniKaydet(
          widget.oturum,
          id,
          giris,
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Ölçütler kaydedildi.')));
        }
      } finally {
        for (final satir in satirlar) {
          for (final c in satir.values) {
            c.dispose();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Ölçütler kaydedilemedi.\\nOrijinal hata: $e');
      }
    }
  }

  Future<void> _ogrenciPuanla(OdevKontrolSonuc sonuc) async {
    if (_kontrolId == null || _degisti) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce bekleyen kontrol değişikliklerini kaydedin.'),
        ),
      );
      return;
    }
    final id = _kontrolId!;
    try {
      final olcutler = await BireyselOdevKontrolService.degerlendirmeOlcutleri(
        widget.oturum,
        id,
      );
      final puanlar = await BireyselOdevKontrolService.degerlendirmePuanlari(
        widget.oturum,
        id,
      );
      if (!mounted || id != _kontrolId) return;
      if (olcutler.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Önce değerlendirme ölçütlerini oluşturun.'),
          ),
        );
        return;
      }
      final girdiler = {
        for (final o in olcutler)
          o['OlcutId'] as int: TextEditingController(
            text:
                puanlar
                    .where(
                      (p) =>
                          p['OlcutId'] == o['OlcutId'] &&
                          p['OdevKontrolSonucId'] == sonuc.odevKontrolSonucId,
                    )
                    .map((p) => p['Puan'].toString())
                    .firstOrNull ??
                '',
          ),
      };
      try {
        final kaydet = await odevDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_ogrenciler[sonuc.ogrenciId]?.adSoyad ?? 'Öğrenci'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Boş bırakılan ölçüt değerlendirilmemiş sayılır. '
                      '0 puan vermek için 0 yazın.',
                    ),
                    for (final o in olcutler)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: girdiler[o['OlcutId']],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: o['Baslik'] as String,
                            helperText: 'Azami ${o['AzamiPuan']} puan',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Puanları kaydet'),
              ),
            ],
          ),
        );
        if (kaydet != true || !mounted || id != _kontrolId) return;
        await BireyselOdevKontrolService.degerlendirmePuaniKaydet(
          widget.oturum,
          id,
          sonuc.ogrenciId,
          {
            for (final entry in girdiler.entries)
              entry.key: entry.value.text.trim().isEmpty
                  ? null
                  : int.tryParse(entry.value.text.trim()) ?? -1,
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Öğrenci puanları kaydedildi.')),
          );
        }
      } finally {
        for (final c in girdiler.values) {
          c.dispose();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Puanlar kaydedilemedi.\\nOrijinal hata: $e');
      }
    }
  }

  Future<void> _puanDetayi(int index, bool yazilabilir) async {
    if (_islem) return;
    if (!yazilabilir) {
      await _aciklamaDuzenle(_ogrenciler[_sonuclar[index].ogrenciId]!, false);
      return;
    }
    while (mounted && index >= 0 && index < _sonuclar.length) {
      final s = _sonuclar[index], o = _ogrenciler[_sonuclar[index].ogrenciId]!;
      final yon = await odevDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => OdevPuanDialog(
          fotoVerisi: o.fotoVerisi,
          fotoYolu: o.fotoYolu,
          ad: '${o.okulNo} • ${o.adSoyad}',
          sinif:
              widget.oturum.siniflar
                  .where((x) => x.sinifSubeId == _gorev?.sinifSubeId)
                  .firstOrNull
                  ?.sinif ??
              '',
          sira: index + 1,
          toplam: _sonuclar.length,
          durum: _durumlar[o.ogrenciId]!,
          notDegeri: _puanlar[o.ogrenciId],
          aciklama: _notlar[o.ogrenciId] ?? '',
          onceki: index > 0,
          sonraki: index < _sonuclar.length - 1,
          ekle: () => odevEkiEkle(
            context,
            widget.oturum,
            widget.odevId,
            sonucId: s.odevKontrolSonucId,
          ),
          ekleriGetir: () async {
            final rows =
                (await OdevDosyaService.liste(widget.oturum, widget.odevId))
                    .where(
                      (r) => r['OdevKontrolSonucId'] == s.odevKontrolSonucId,
                    )
                    .toList();
            return Future.wait(
              rows.take(6).map((r) async {
                final ad = '${r['DosyaAdi']}'.toLowerCase();
                if ([
                  '.jpg',
                  '.jpeg',
                  '.png',
                  '.webp',
                  '.gif',
                ].any(ad.endsWith)) {
                  return OdevDosyaService.oku(
                    widget.oturum,
                    widget.odevId,
                    r['Id'] as int,
                  );
                }
                return r;
              }),
            );
          },
          kaydet: (n, d, aciklama) async {
            await BireyselOdevKontrolService.sonuclariKaydet(
              widget.oturum,
              _kontrolId!,
              [
                OdevSonucGirdisi(
                  ogrenciId: o.ogrenciId,
                  durum: d,
                  notDegeri: n,
                  aciklama: aciklama,
                ),
              ],
            );
            if (mounted) {
              setState(() {
                _durumlar[o.ogrenciId] = d;
                _kayitliDurumlar[o.ogrenciId] = d;
                _puanlar[o.ogrenciId] = n;
                _puanGirdileri[o.ogrenciId]?.text = _puanMetni(n);
                _puanHatalari.remove(o.ogrenciId);
                _kayitliPuanlar[o.ogrenciId] = n;
                _notlar[o.ogrenciId] = aciklama;
                _kayitliNotlar[o.ogrenciId] = aciklama;
                _degisiklikDurumunuGuncelle();
              });
            }
          },
        ),
      );
      if (yon == null || yon == 0) return;
      index += yon;
    }
  }

  void _topluSecimiKapat() => setState(() {
    _topluSecim = false;
    _seciliOgrenciler.clear();
  });

  void _aramayiAcKapat() => setState(() {
    _aramaAcik = !_aramaAcik;
    if (!_aramaAcik) {
      _aramaGirdisi.clear();
      _arama = '';
      FocusManager.instance.primaryFocus?.unfocus();
    }
  });

  Future<void> _toplu() async {
    if (_islem || _sonuclar.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_topluSecim) {
      setState(() => _topluSecim = true);
      return;
    }
    var durum = OdevKontrolDurumu.yapti;
    var secili = _seciliOgrenciler.isNotEmpty;
    var manuel = false;
    var metin = '';
    final form = GlobalKey<FormState>();
    final sonuc = await showModalBottomSheet<(OdevKontrolDurumu, int?, bool)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Toplu giriş',
                          style: Theme.of(c).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.pop(c),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('toplu-durum'),
                    initialValue: durum.name,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Durum / puan',
                    ),
                    items: [
                      for (final d in OdevKontrolDurumu.hizli)
                        DropdownMenuItem(
                          value: d.name,
                          child: Text(
                            '${d.sembol} ${odevDurumAdi(d)} • ${d.degerlendirmeDisi ? 'Ortalamaya katılmaz' : '${OdevKontrolSonuc.hizliNot(d)} puan'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem(
                        value: 'ozel',
                        child: Text('Özel puan (0–10)'),
                      ),
                    ],
                    onChanged: (v) => yenile(() {
                      manuel = v == 'ozel';
                      if (!manuel) {
                        durum = OdevKontrolDurumu.values.firstWhere(
                          (d) => d.name == v,
                        );
                      }
                    }),
                  ),
                  if (manuel) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('toplu-puan'),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Puan (0–10)',
                      ),
                      onChanged: (v) => metin = v,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 0 || n > 10
                            ? '0–10 arasında tam sayı girin.'
                            : null;
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<bool>(
                    key: const ValueKey('toplu-hedef'),
                    initialValue: secili,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Uygulanacak öğrenciler',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: false,
                        child: Text('Tümü (${_sonuclar.length})'),
                      ),
                      DropdownMenuItem(
                        value: true,
                        enabled: _seciliOgrenciler.isNotEmpty,
                        child: Text('Seçililer (${_seciliOgrenciler.length})'),
                      ),
                    ],
                    onChanged: (v) => yenile(() => secili = v ?? false),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      if (!form.currentState!.validate() ||
                          (secili && _seciliOgrenciler.isEmpty)) {
                        return;
                      }
                      final n = manuel ? int.parse(metin) : null;
                      Navigator.pop(c, (
                        manuel ? OdevKontrolSonuc.notDurumu(n, null) : durum,
                        n,
                        secili,
                      ));
                    },
                    child: const Text('Uygula'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || sonuc == null) return;
    _tumuneUygula(
      sonuc.$1,
      puan: sonuc.$2,
      hedef: sonuc.$3 ? _seciliOgrenciler.toSet() : null,
    );
    _topluSecimiKapat();
  }

  Widget _basitSatir(OdevKontrolSonuc sonuc, bool yazilabilir) {
    final o = _ogrenciler[sonuc.ogrenciId]!;
    final id = o.ogrenciId;
    final index = _sonuclar.indexOf(sonuc);
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('basit-$_kontrolId-$id'),
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(OrtakUi.bosluk),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_topluSecim)
                  Checkbox(
                    key: ValueKey('odev-ogrenci-sec-$id'),
                    value: _seciliOgrenciler.contains(id),
                    onChanged: yazilabilir
                        ? (v) => setState(() {
                            if (v == true) {
                              _seciliOgrenciler.add(id);
                            } else {
                              _seciliOgrenciler.remove(id);
                            }
                          })
                        : null,
                  ),
                CircleAvatar(
                  radius: 21,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    o.adSoyad.trim().split(RegExp(r'\\s+'))
                        .where((x) => x.isNotEmpty)
                        .take(2)
                        .map((x) => x.substring(0, 1).toUpperCase())
                        .join(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OdevOgrenciGecmisScreen(
                          oturum: widget.oturum,
                          ogrenciId: id,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OrtakBaslik(
                            o.adSoyad,
                            maxLines: 2,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            'No: ${o.okulNo}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('puan-$id'),
                  tooltip: 'Açıklama ve fotoğraf',
                  onPressed: _islem
                      ? null
                      : () => _puanDetayi(index, yazilabilir),
                  icon: const Icon(Icons.notes_outlined),
                ),
              ],
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final d in OdevKontrolDurumu.hizli)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message:
                            '${odevDurumAdi(d)} • ${d.degerlendirmeDisi ? 'Ortalamaya katılmaz' : '${OdevKontrolSonuc.hizliNot(d)} puan'}',
                        child: SizedBox(
                          width: 40,
                          child: OutlinedButton(
                            key: ValueKey('durum-$id-${d.name}'),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: odevDurumZemini(d),
                              foregroundColor: odevDurumRengi(d),
                              side: BorderSide(
                                color: _durumlar[id] == d
                                    ? odevDurumRengi(d)
                                    : Colors.transparent,
                              ),
                            ),
                            onPressed: yazilabilir
                                ? () => _durumDegistir(id, d)
                                : null,
                            child: Text(
                              d.sembol,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (d == OdevKontrolDurumu.yapti) ...[
                        const SizedBox(width: 4),
                        SizedBox(
                          width:
                              (56 * MediaQuery.textScalerOf(context).scale(1))
                                  .clamp(56, 96),
                          child: Tooltip(
                            message: 'Puan (0–10)',
                            child: TextField(
                              key: ValueKey('satir-puan-$id'),
                              controller: _puanGirdileri[id],
                              readOnly: !yazilabilir,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: '—',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                enabledBorder: _puanHatalari.contains(id)
                                    ? OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(
                                          OrtakUi.radius,
                                        ),
                                        borderSide: BorderSide(
                                          color: theme.colorScheme.error,
                                        ),
                                      )
                                    : null,
                              ),
                              onChanged: (v) => _puanGir(id, v),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
            if (_puanHatalari.contains(id))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '0–10 girin.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (_ogrenciDegisti(id))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Kaydedilmedi',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle({int? seciliId}) async {
    setState(() {
      _bekle = true;
      _hata = null;
    });
    try {
      final gorev = await BireyselOdevKontrolService.gorevGetir(
        widget.oturum,
        widget.odevId,
      );
      final ogrenciler = await BireyselOdevKontrolService.katilimcilar(
        widget.oturum,
        widget.odevId,
      );
      final kontroller = await BireyselOdevKontrolService.kontroller(
        widget.oturum,
        widget.odevId,
      );
      final aday = seciliId ?? _kontrolId;
      final id = kontroller.any((k) => k.odevKontrolId == aday)
          ? aday
          : (kontroller.isEmpty ? null : kontroller.last.odevKontrolId);
      final tumSonuclar = id == null
          ? <OdevKontrolSonuc>[]
          : await BireyselOdevKontrolService.sonuclar(widget.oturum, id);
      final aktifIdler = ogrenciler.where((o) => o.aktif)
          .map((o) => o.ogrenciId).toSet();
      final sonuclar = tumSonuclar
          .where((s) => aktifIdler.contains(s.ogrenciId)).toList();
      if (!mounted) return;
      setState(() {
        _gorev = gorev;
        _ogrenciler = {for (final o in ogrenciler.where((o) => o.aktif)) o.ogrenciId: o};
        _kontroller = kontroller;
        _kontrolId = id;
        _sonuclar = sonuclar;
        _durumlar.clear();
        _notlar.clear();
        _kayitliDurumlar.clear();
        _kayitliNotlar.clear();
        for (final c in _puanGirdileri.values) {
          c.dispose();
        }
        _puanGirdileri.clear();
        _puanHatalari.clear();
        _seciliOgrenciler.clear();
        _topluSecim = false;
        _puanlar.clear();
        _kayitliPuanlar.clear();
        for (final s in sonuclar) {
          final not = s.aciklama ?? '';
          _durumlar[s.ogrenciId] = s.durum;
          _puanlar[s.ogrenciId] =
              s.notDegeri ?? OdevKontrolSonuc.hizliNot(s.durum);
          _kayitliPuanlar[s.ogrenciId] =
              s.notDegeri ?? OdevKontrolSonuc.hizliNot(s.durum);
          _puanGirdileri[s.ogrenciId] = TextEditingController(
            text: _puanMetni(_puanlar[s.ogrenciId]),
          );
          _notlar[s.ogrenciId] = not;
          _kayitliDurumlar[s.ogrenciId] = s.durum;
          _kayitliNotlar[s.ogrenciId] = not;
        }
        _degisti = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Görev detayları okunamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _bekle = false);
    }
  }

  Future<bool> _vazgecilebilirMi() async {
    if (!_degisti) return true;
    return await odevDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kontroller kaydedilmedi'),
            content: const Text(
              'Kaydedilmemiş değişikliklerden vazgeçmek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Devam et'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Vazgeç'),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _cik() async {
    if (_islem || _cikisSoruluyor) return;
    _cikisSoruluyor = true;
    final cik = await _vazgecilebilirMi();
    _cikisSoruluyor = false;
    if (mounted && cik) {
      setState(() => _degisti = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _kontrolAciklamaDuzenle() async {
    final id = _kontrolId;
    if (id == null || _islem || _bekle) return;
    if (!await _vazgecilebilirMi() || !mounted) return;
    final mevcut = _kontroller.where((k) => k.odevKontrolId == id);
    if (mevcut.isEmpty || !mevcut.first.aktif) return;
    final controller = TextEditingController(text: mevcut.first.aciklama ?? '');
    try {
      final metin = await odevDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kontrol açıklaması'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: 'Bu kontrolde yapılan çalışma veya hatırlatma',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      );
      if (metin == null || !mounted) return;
      setState(() => _islem = true);
      try {
        await BireyselOdevKontrolService.kontrolAciklamaKaydet(
          widget.oturum,
          id,
          metin.trim(),
        );
        if (mounted) await _yukle(seciliId: id);
      } catch (e) {
        if (mounted) {
          setState(
            () =>
                _hata = 'Kontrol açıklaması kaydedilemedi.\\nOrijinal hata: $e',
          );
        }
      } finally {
        if (mounted) setState(() => _islem = false);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _yeniKontrol() async {
    if (_islem || _bekle) return;
    if (!await _vazgecilebilirMi() || !mounted) return;
    setState(() => _islem = true);
    try {
      final baslangic = _gorev!.baslangicTarihi;
      final bugun = DateUtils.dateOnly(DateTime.now());
      final tarih = await showDatePicker(
        context: context,
        initialDate: bugun.isBefore(baslangic) ? baslangic : bugun,
        firstDate: baslangic,
        lastDate: DateTime(9999, 12, 31),
        helpText: 'Yeni kontrol tarihi',
        cancelText: 'İptal',
        confirmText: 'Oluştur',
      );
      if (tarih == null || !mounted) return;
      String? asama;
      if (_gorev!.gorevTuru == OdevGorevTuru.proje ||
          _gorev!.gorevTuru == OdevGorevTuru.performans) {
        final controller = TextEditingController();
        try {
          asama = await odevDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Ara kontrol aşaması'),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Bu aşamada ne kontrol edilecek?',
                  hintText: 'Örnek: Taslak ve planlama, uygulama, final sunumu',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      Navigator.pop(ctx, controller.text.trim());
                    }
                  },
                  child: const Text('Aşamayı oluştur'),
                ),
              ],
            ),
          );
        } finally {
          controller.dispose();
        }
        if (asama == null || !mounted) return;
      }
      final id = await BireyselOdevKontrolService.kontrolOlustur(
        widget.oturum,
        widget.odevId,
        kontrolTarihi: tarih,
        aciklama: asama,
      );
      if (mounted) await _yukle(seciliId: id);
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Kontrol oluşturulamadı.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _kaydet() async {
    if (_islem || _kontrolId == null || !_degisti || _puanHatalari.isNotEmpty) {
      return;
    }
    setState(() {
      _islem = true;
      _hata = null;
    });
    try {
      await BireyselOdevKontrolService.sonuclariKaydet(
        widget.oturum,
        _kontrolId!,
        [
          for (final s in _sonuclar)
            OdevSonucGirdisi(
              ogrenciId: s.ogrenciId,
              durum: _durumlar[s.ogrenciId]!,
              aciklama: _notlar[s.ogrenciId],
              notDegeri: _puanlar[s.ogrenciId],
            ),
        ],
      );
      if (!mounted) return;
      setState(() {
        _kayitliPuanlar
          ..clear()
          ..addAll(_puanlar);
        _kayitliDurumlar
          ..clear()
          ..addAll(_durumlar);
        _kayitliNotlar
          ..clear()
          ..addAll(_notlar);
        _degisti = false;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kontrol sonuçları kaydedildi.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Sonuçlar kaydedilemedi.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _ogrenciEkle() async {
    if (_islem || _gorev == null) return;
    if (!await _vazgecilebilirMi() || !mounted) return;
    try {
      final gorev = _gorev!;
      final secenekler = await BireyselOdevKontrolService.ogrenciSecenekleri(
        widget.oturum, gorev.sinifSubeId);
      final mevcut = await BireyselOdevKontrolService.katilimcilar(
        widget.oturum, widget.odevId);
      if (!mounted) return;
      final aktifIdler = mevcut.where((o) => o.aktif)
          .map((o) => o.ogrenciId).toSet();
      final adaylar = secenekler.where((o) =>
          !aktifIdler.contains(o['OgrenciId'] as int)).toList();
      if (adaylar.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Bu sınıftaki bütün öğrenciler ödeve zaten dahil.')));
        return;
      }
      final secilen = <int>{};
      final onay = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Öğrenci Ekle'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: adaylar.map((o) {
                  final id = o['OgrenciId'] as int;
                  final ad = '${o['Ad'] ?? ''} ${o['Soyad'] ?? ''}'.trim();
                  return CheckboxListTile(
                    value: secilen.contains(id),
                    title: Text(ad),
                    subtitle: Text('No: ${o['OkulNo'] ?? ''}'),
                    onChanged: (v) => setDialogState(() {
                      if (v == true) { secilen.add(id); }
                      else { secilen.remove(id); }
                    }),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Vazgeç')),
              FilledButton(
                onPressed: secilen.isEmpty ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text('${secilen.length} Öğrenciyi Ekle')),
            ],
          ),
        ),
      );
      if (onay != true || !mounted) return;
      setState(() => _islem = true);
      await BireyselOdevKontrolService.gorevGuncelle(
        widget.oturum, widget.odevId,
        gorevTuru: gorev.gorevTuru,
        baslik: gorev.baslik,
        baslangicTarihi: gorev.baslangicTarihi,
        teslimTarihi: gorev.teslimTarihi,
        aciklama: gorev.aciklama,
        donem: gorev.donem,
        ogrenciIdleri: {...aktifIdler, ...secilen}.toList(),
      );
      if (!mounted) return;
      setState(() => _islem = false);
      await _yukle();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${secilen.length} öğrenci ödeve eklendi.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Öğrenci eklenemedi. Orijinal hata: $e')));
    } finally {
      if (mounted && _islem) setState(() => _islem = false);
    }
  }

  Future<void> _ogrenciCikar() async {
    if (_islem || _gorev == null) return;
    if (!await _vazgecilebilirMi() || !mounted) return;
    try {
      final katilimcilar = await BireyselOdevKontrolService.katilimcilar(
          widget.oturum, widget.odevId);
      if (!mounted) return;
      final aktifler = katilimcilar.where((o) => o.aktif).toList();
      if (aktifler.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ödevde çıkarılabilecek öğrenci yok.')));
        return;
      }
      final secilen = <int>{};
      final onay = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Öğrenci Çıkar'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: aktifler.map((o) => CheckboxListTile(
                  value: secilen.contains(o.ogrenciId),
                  title: Text(o.adSoyad),
                  subtitle: Text('No: ${o.okulNo}'),
                  onChanged: (v) => setDialogState(() {
                    if (v == true) { secilen.add(o.ogrenciId); }
                    else { secilen.remove(o.ogrenciId); }
                  }),
                )).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Vazgeç')),
              FilledButton(
                onPressed: secilen.isEmpty ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text('${secilen.length} Öğrenciyi Seç')),
            ],
          ),
        ),
      );
      if (onay != true || !mounted) return;
      final onayla = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Öğrenciler ödevden çıkarılsın mı?'),
          content: Text(
            '${secilen.length} öğrenci yalnızca bu ödevin aktif listesinden çıkarılacak. '
            'Sınıf kayıtları, önceki kontroller ve notlar korunacak.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
              child: const Text('İptal')),
            FilledButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('Öğrenci Çıkar')),
          ],
        ),
      );
      if (onayla != true || !mounted) return;
      setState(() => _islem = true);
      await BireyselOdevKontrolService.katilimcilariCikar(
          widget.oturum, widget.odevId, secilen);
      if (!mounted) return;
      setState(() => _islem = false);
      await _yukle();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${secilen.length} öğrenci ödevden çıkarıldı.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Öğrenci çıkarılamadı. Orijinal hata: $e')));
    } finally {
      if (mounted && _islem) setState(() => _islem = false);
    }
  }

  Future<void> _duzenle() async {
    if (!await _vazgecilebilirMi() || !mounted) return;
    final sonuc = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => OdevTanimScreen(oturum: widget.oturum, gorev: _gorev!),
      ),
    );
    if (mounted && sonuc != null) await _yukle();
  }

  Future<void> _pasiflestir() async {
    if (!await _vazgecilebilirMi() || !mounted) return;
    final onay = await odevDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Görev kaldırılsın mı?'),
        content: const Text(
          'Görev aktif listeden kaldırılacak. Geçmiş kontrol sonuçları silinmeyecek; görev, “Pasif görevleri göster” seçeneğiyle görüntülenebilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Görevi Kaldır'),
          ),
        ],
      ),
    );
    if (!mounted || onay != true) return;
    setState(() => _islem = true);
    try {
      await BireyselOdevKontrolService.gorevPasiflestir(
        widget.oturum,
        widget.odevId,
      );
      if (mounted) await _yukle();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Görev pasifleştirilemedi.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _kontrolSil() async {
    final id = _kontrolId;
    if (id == null || _islem || _bekle || _gorev?.aktif != true) return;
    final secili = _kontroller.where((k) => k.odevKontrolId == id);
    if (secili.isEmpty || !secili.first.aktif) return;
    if (!await _vazgecilebilirMi() || !mounted) return;

    final onay = await odevDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kontrolü Sil'),
        content: Text(
          '${secili.first.siraNo}. kontrol ve bu kontrole ait '
          'öğrenci değerlendirmeleri kalıcı olarak silinecek. '
          'Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kontrolü Sil'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    setState(() => _islem = true);
    try {
      await BireyselOdevKontrolService.kontrolSil(widget.oturum, id);
      if (!mounted) return;
      _kontrolId = null;
      _degisti = false;
      await _yukle();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Kontrol silinemedi.\\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  String _kontrolEtiketi(OdevKontrol k) =>
      '${k.siraNo}. kontrol • ${odevTarihYaz(k.kontrolTarihi)}${k.aktif ? '' : ' • Pasif'}';

  Future<void> _kontrolSec() async {
    if (_islem || _bekle || _kontroller.isEmpty) return;
    final secenekler = List<OdevKontrol>.of(_kontroller);
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kontrol tarihi', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final k in secenekler)
                      ListTile(
                        key: ValueKey('kontrol-sec-${k.odevKontrolId}'),
                        title: Text(_kontrolEtiketi(k)),
                        selected: k.odevKontrolId == _kontrolId,
                        trailing: k.odevKontrolId == _kontrolId
                            ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.pop(ctx, k.odevKontrolId),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || id == null || id == _kontrolId || _islem || _bekle) return;
    if (!_kontroller.any((k) => k.odevKontrolId == id)) return;
    if (await _vazgecilebilirMi() && mounted) await _yukle(seciliId: id);
  }

  Widget _kontrolSecici() {
    final secili = _kontroller.where((k) => k.odevKontrolId == _kontrolId).firstOrNull;
    return InkWell(
      key: const ValueKey('odev-kontrol-secici'),
      onTap: _islem || _bekle ? null : _kontrolSec,
      child: InputDecorator(
        decoration: InputDecoration(labelText: 'Kontrol tarihi', enabled: !_islem && !_bekle),
        child: Row(children: [
          Expanded(child: Text(secili == null ? 'Kontrol seçin' : _kontrolEtiketi(secili),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }
  Future<void> _tamamla() async {
    if (!await _vazgecilebilirMi() || !mounted) return;
    setState(() => _islem = true);
    try {
      await BireyselOdevKontrolService.tamamlanmaKaydet(
        widget.oturum,
        widget.odevId,
        !_gorev!.tamamlandi,
      );
      if (mounted) await _yukle();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Durum kaydedilemedi. Orijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _ekleriAc() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OdevEklerScreen(oturum: widget.oturum, odevId: widget.odevId),
      ),
    );
  }

  Future<void> _gorevBilgileri() async {
    final g = _gorev;
    if (g == null || _islem) return;
    final sinif =
        widget.oturum.siniflar
            .where((s) => s.sinifSubeId == g.sinifSubeId)
            .firstOrNull
            ?.sinif ??
        '';
    final girilen = _durumlar.values.where((d) => !d.bekliyor).length;
    final islem = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * .8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ödev bilgileri',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bilgileri kapat',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(g.baslik, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('$sinif • ${g.gorevTuru.baslik}'),
              Text('Başlangıç: ${odevTarihYaz(g.baslangicTarihi)}'),
              if (g.teslimTarihi != null)
                Text('Son teslim: ${odevTarihYaz(g.teslimTarihi!)}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Chip(
                    label: Text(
                      !g.aktif
                          ? 'Pasif'
                          : g.tamamlandi
                          ? 'Tamamlandı'
                          : girilen == 0
                          ? 'Taslak'
                          : 'Devam Ediyor',
                    ),
                  ),
                  Chip(label: Text('${_ogrenciler.length} öğrenci')),
                  Chip(label: Text('$girilen not girildi')),
                  Chip(label: Text('${_sonuclar.length - girilen} kalan')),
                ],
              ),
              if (g.aciklama?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(g.aciklama!),
                ),
              _sonucOzeti(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'ekler'),
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Ek Dosyalar'),
                  ),
                  TextButton.icon(
                    onPressed: _kontrolId == null || _sonuclar.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, 'aciklamalar'),
                    icon: const Icon(Icons.comment_outlined),
                    label: const Text('Açıklamaları Gör'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (islem == 'ekler') {
      await _ekleriAc();
    } else if (islem == 'aciklamalar' && _sonuclar.isNotEmpty) {
      final kontrolAktif = _kontroller.any(
        (k) => k.odevKontrolId == _kontrolId && k.aktif,
      );
      await _puanDetayi(0, _gorev?.aktif == true && kontrolAktif && !_islem);
    }
  }

  Widget _digerIslemler(bool yazilabilir, bool kontrolAktif) =>
      PopupMenuButton<String>(
        tooltip: 'Diğer işlemler',
        onSelected: (v) async {
          switch (v) {
            case 'bilgiler':
              await _gorevBilgileri();
            case 'rapor':
              await _excelAktar();
            case 'ogrenciEkle':
              await _ogrenciEkle();
            case 'ogrenciCikar':
              await _ogrenciCikar();
            case 'duzenle':
              await _duzenle();
            case 'excel':
              await _excelAktar();
            case 'yeni':
              await _yeniKontrol();
            case 'aciklama':
              await _kontrolAciklamaDuzenle();
            case 'olcut':
              await _olcutleriDuzenle();
            case 'puan':
              if (_sonuclar.isNotEmpty) await _ogrenciPuanla(_sonuclar.first);
            case 'tamam':
              await _tamamla();
            case 'pasif':
              await _pasiflestir();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'bilgiler', child: Text('Bilgiler')),
          const PopupMenuItem(value: 'rapor', child: Text('Rapor / Excel’e aktar')),
          if (yazilabilir) ...[
            const PopupMenuItem(value: 'duzenle', child: Text('Ödevi düzenle')),
            const PopupMenuItem(value: 'yeni', child: Text('Yeni kontrol')),
            if (kontrolAktif)
              const PopupMenuItem(
                value: 'aciklama',
                child: Text('Kontrol açıklaması'),
              ),
            if (_olcutluGorev && kontrolAktif) ...[
              const PopupMenuItem(
                value: 'olcut',
                child: Text('Aşama ölçütleri'),
              ),
              const PopupMenuItem(value: 'puan', child: Text('Aşama puanları')),
            ],
            PopupMenuItem(
              value: 'tamam',
              child: Text(
                _gorev?.tamamlandi == true
                    ? 'Devam ediyor olarak işaretle'
                    : 'Tamamlandı olarak işaretle',
              ),
            ),
            const PopupMenuItem(value: 'pasif', child: Text('Görevi kaldır')),
          ],
        ],
        icon: const Icon(Icons.more_vert),
      
      );

  Widget _altIslem(String ad, IconData ikon, VoidCallback? onTap, {
    bool vurgulu = false,
    bool kaydet = false,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: Tooltip(
        message: ad,
        child: Material(
          color: onTap == null
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : vurgulu
                  ? Theme.of(context).colorScheme.primary
                  : kaydet
                      ? Theme.of(context).colorScheme.tertiaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ikon, size: 23,
                    color: onTap == null
                        ? Theme.of(context).disabledColor
                        : vurgulu
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(ad, maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: onTap == null
                            ? Theme.of(context).disabledColor
                            : vurgulu
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  int _durumSayisi(OdevKontrolDurumu durum) =>
      _durumlar.values.where((d) => d == durum).length;

  Future<void> _sonucAyrintilari() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ödev sonuçları'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in OdevKontrolDurumu.secilebilir)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    d.sembol,
                    style: TextStyle(
                      color: odevDurumRengi(d),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  title: Text(odevDurumAdi(d)),
                  trailing: Text('${_durumSayisi(d)}'),
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

  Widget _sonucOzeti() => Card(
    child: InkWell(
      key: const ValueKey('odev-sonuc-ozeti'),
      borderRadius: BorderRadius.circular(OrtakUi.radius),
      onTap: _sonucAyrintilari,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Tam: ${_durumSayisi(OdevKontrolDurumu.yapti)} · '
                'Yarı: ${_durumSayisi(OdevKontrolDurumu.kismen)} · '
                'Eksik: ${_durumSayisi(OdevKontrolDurumu.yapmadi)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            const Tooltip(
              message: 'Tüm sonuçları gör',
              child: Icon(Icons.expand_more, size: 20),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final g = _gorev;
    if (g?.dersUygulamalari == true) {
      return DersUygulamaScreen(oturum: widget.oturum, odevId: widget.odevId);
    }
    final yazilabilir = g?.aktif == true && !_bekle && !_islem;
    final kontrolAktif = _kontroller.any(
      (k) => k.odevKontrolId == _kontrolId && k.aktif,
    );
    final rows = _sonuclar
        .where(
          (s) =>
              '${_ogrenciler[s.ogrenciId]?.okulNo} ${_ogrenciler[s.ogrenciId]?.adSoyad}'
                  .toLowerCase()
                  .contains(_arama),
        )
        .toList();
    return OdevTema(
      child: PopScope<void>(
        canPop: !_islem && !_degisti,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_islem) _cik();
        },
        child: OrtakSayfa(
          appBar: OdevBaslik(
            title: const Text('Ödev Kontrol Detayı'),
            actions: [_digerIslemler(yazilabilir, kontrolAktif)],
          ),
          body: _bekle
              ? const Center(child: CircularProgressIndicator())
              : g == null
              ? Center(child: Text(_hata ?? 'Ödev bulunamadı.'))
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList.list(
                        children: [
                          if (_hata != null)
                            Text(
                              _hata!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ListTile(
                            title: const Text('Ödev Bilgileri'),
                            trailing: Icon(_bilgiAcik
                                ? Icons.expand_less : Icons.expand_more),
                            onTap: () => setState(() => _bilgiAcik = !_bilgiAcik),
                          ),
                          if (_bilgiAcik) Card(
                            margin: EdgeInsets.zero,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.fact_check_outlined,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        OrtakBaslik(
                                          g.baslik,
                                          maxLines: 2,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tek ödev altında haftalık veya tekrarlı kontroller. Her tarihin değerlendirmesi ayrı saklanır.',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                          if (_kontroller.isNotEmpty) ...[
                            Row(
                              children: [
                                Expanded(child: _kontrolSecici()),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Seçili kontrolü sil',
                                  icon: const Icon(Icons.delete_outline),
                                  color: Theme.of(context).colorScheme.error,
                                  onPressed: yazilabilir && kontrolAktif
                                      ? _kontrolSil
                                      : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],

                          ListTile(
                            title: Text('Öğrenciler (${_sonuclar.length})'),
                            trailing: Icon(_ogrencilerAcik
                                ? Icons.expand_less : Icons.expand_more),
                            onTap: () => setState(
                                () => _ogrencilerAcik = !_ogrencilerAcik),
                          ),
                          if (_ogrencilerAcik) ...[
                            TextField(
                              controller: _aramaGirdisi,
                              decoration: const InputDecoration(
                                hintText: 'Öğrenci ara...',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) => setState(
                                  () => _arama = v.toLowerCase()),
                            ),
                            OutlinedButton.icon(
                              onPressed: yazilabilir && kontrolAktif &&
                                      _sonuclar.isNotEmpty ? _toplu : null,
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Toplu İşlem'),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _topluSecim
                                    ? '${_sonuclar.length} öğrenci • ${_seciliOgrenciler.length} seçili'
                                    : '${_sonuclar.length} öğrenci',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (_topluSecim)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _islem
                                        ? null
                                        : _topluSecimiKapat,
                                    child: const Text('Seçimi bitir'),
                                  ),
                                ),
                            ],
                          ),
                          if (_kontrolId == null && yazilabilir)
                            OutlinedButton.icon(
                              onPressed: _yeniKontrol,
                              icon: const Icon(Icons.add),
                              label: const Text('Not girişini başlat'),
                            ),
                          if (false && _aramaAcik) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _aramaGirdisi,
                              decoration: const InputDecoration(
                                hintText: 'Öğrenci ara...',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) =>
                                  setState(() => _arama = v.toLowerCase()),
                            ),
                          ],
                          if (_topluSecim)
                            CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Görünenleri seç'),
                              value:
                                  rows.isNotEmpty &&
                                  rows.every(
                                    (s) =>
                                        _seciliOgrenciler.contains(s.ogrenciId),
                                  ),
                              onChanged:
                                  yazilabilir && kontrolAktif && rows.isNotEmpty
                                  ? (v) => setState(() {
                                      final ids = rows.map((s) => s.ogrenciId);
                                      if (v == true) {
                                        _seciliOgrenciler.addAll(ids);
                                      } else {
                                        _seciliOgrenciler.removeAll(ids);
                                      }
                                    })
                                  : null,
                            ),
                          if (rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Öğrenci bulunamadı.'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_ogrencilerAcik) SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) =>
                            _basitSatir(rows[i], yazilabilir && kontrolAktif),
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: OdevOrtakAltIslemler(
            ogrenciEkle: yazilabilir ? _ogrenciEkle : null,
            ogrenciCikar: yazilabilir && _ogrenciler.isNotEmpty
                ? _ogrenciCikar : null,
            kaydet: yazilabilir && kontrolAktif && _degisti &&
                    _puanHatalari.isEmpty ? _kaydet : null,
          ),
        ),
      ),
    );
  }
}
