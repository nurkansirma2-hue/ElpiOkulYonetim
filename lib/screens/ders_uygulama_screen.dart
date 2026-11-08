import 'package:flutter/material.dart';
import '../models/odev_kontrol.dart';
import '../models/ders_uygulama.dart';
import '../services/bireysel_liste_service.dart';
import '../services/bireysel_odev_kontrol_service.dart';
import '../widgets/ortak_ui.dart';
import '../widgets/odev_ortak_alt_islemler.dart';
import '../widgets/odev_gorunum.dart';
import '../widgets/odev_puan_dialog.dart';
import '../widgets/ogrenci_foto_widget.dart';
import '../widgets/uygulama_ekle_tanitim.dart';
import 'odev_tanim_screen.dart';
import 'odev_ekler_screen.dart';

class DersUygulamaScreen extends StatefulWidget {
  const DersUygulamaScreen({
    super.key,
    required this.oturum,
    required this.odevId,
  });
  final BireyselListeOturumu oturum;
  final int odevId;
  @override
  State<DersUygulamaScreen> createState() => _DersUygulamaScreenState();
}

class _DersUygulamaScreenState extends State<DersUygulamaScreen> {
  OdevTanim? _g;
  List<OdevOgrenci> _ogrenciler = [];
  List<DersUygulamasi> _uygulamalar = [];
  List<OdevKontrol> _kontroller = [];
  Map<(int, int), UygulamaSonucu> _son = {};
  final _taslak = <(int, int), UygulamaSonucGirdisi>{};
  final _acik = <int>{};
  int? _kid;
  bool _bekle = true, _islem = false;
  bool _ogrenciBolumuAcik = true;
  String? _hata;
  String _arama = '';
  int? _seciliId;
  DersUygulamasi? get _secili =>
      _aktif.where((u) => u.id == _seciliId).firstOrNull ?? _aktif.firstOrNull;
  final _aramaGirdisi = TextEditingController();
  final _aramaOdak = FocusNode();
  final _aramaAlani = GlobalKey();
  final _kaydirma = ScrollController();
  List<DersUygulamasi> get _aktif =>
      _uygulamalar.where((u) => u.aktif).toList();
  bool get _yaz =>
      _hata == null &&
      !_bekle &&
      !_islem &&
      _g?.aktif == true &&
      _kontroller.any((k) => k.odevKontrolId == _kid && k.aktif);
  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _aramaGirdisi.dispose();
    _aramaOdak.dispose();
    _kaydirma.dispose();
    super.dispose();
  }

  Future<void> _yukle({int? kontrol}) async {
    setState(() {
      _bekle = true;
      _hata = null;
    });
    try {
      final g = await BireyselOdevKontrolService.gorevGetir(
        widget.oturum,
        widget.odevId,
      );
      if (!g.dersUygulamalari) throw StateError('Görev türü değişti.');
      final ogr = await BireyselOdevKontrolService.katilimcilar(
        widget.oturum,
        widget.odevId,
      );
      final uygulamalar = await DersUygulamaIslemleri.uygulamalar(
        widget.oturum,
        widget.odevId,
      );
      final kontroller = await BireyselOdevKontrolService.kontroller(
        widget.oturum,
        widget.odevId,
      );
      final aday = kontrol ?? _kid;
      final kid = kontroller.any((k) => k.odevKontrolId == aday)
          ? aday
          : kontroller.lastOrNull?.odevKontrolId;
      final son = kid == null
          ? <UygulamaSonucu>[]
          : await DersUygulamaIslemleri.gecmis(
              widget.oturum,
              widget.odevId,
              kontrolId: kid,
              guncel: true,
            );
      if (!mounted) return;
      setState(() {
        _g = g;
        _ogrenciler = ogr.where((o) => o.aktif).toList();
        _uygulamalar = uygulamalar;
        _kontroller = kontroller;
        _kid = kid;
        _son = {for (final s in son) (s.ogrenciId, s.uygulamaId): s};
        _taslak.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _hata = 'Bilgiler yüklenemedi. $e');
    } finally {
      if (mounted) setState(() => _bekle = false);
    }
  }

  void _mesaj(String metin) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(metin)));
    }
  }

  Future<bool> _vazgec() async {
    if (_taslak.isEmpty) return true;
    final sonuc = await odevDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Değişiklikler kaydedilmedi'),
        content: const Text(
          'Devam ederseniz kaydedilmemiş değerlendirmeler bırakılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Düzenlemeye devam et'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Değişiklikleri bırak'),
          ),
        ],
      ),
    );
    return sonuc == true && mounted;
  }

  Future<void> _kaydet() async {
    if (!_yaz || _taslak.isEmpty || _kid == null) return;
    setState(() => _islem = true);
    try {
      await DersUygulamaIslemleri.sonuclariKaydet(
        widget.oturum,
        _kid!,
        _taslak.values.toList(),
      );
      if (mounted) {
        await _yukle();
        _mesaj('Değerlendirmeler kaydedildi.');
      }
    } catch (e) {
      _mesaj('Kaydedilemedi. $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _cik() async {
    if (_islem || !await _vazgec() || !mounted) return;
    setState(_taslak.clear);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  String _tarih(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  String _kontrolAdi(OdevKontrol k) =>
      '${k.siraNo}. Kontrol • ${_tarih(k.kontrolTarihi)}${k.aktif ? '' : ' • Pasif'}';
  Future<void> _kontrolSec() async {
    final id = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final k in _kontroller)
                ListTile(
                  title: Text(_kontrolAdi(k)),
                  selected: k.odevKontrolId == _kid,
                  onTap: () => Navigator.pop(ctx, k.odevKontrolId),
                ),
            ],
          ),
        ),
      ),
    );
    if (id != null && id != _kid && mounted && await _vazgec()) {
      await _yukle(kontrol: id);
    }
  }

  Future<void> _yeniKontrol() async {
    if (_g?.aktif != true || !await _vazgec() || !mounted) return;
    final tarih = await showDatePicker(
      context: context,
      initialDate: DateTime.now().isBefore(_g!.baslangicTarihi)
          ? _g!.baslangicTarihi
          : DateTime.now(),
      firstDate: _g!.baslangicTarihi,
      lastDate: DateTime(9999, 12, 31),
      helpText: 'Yeni kontrol tarihi',
    );
    if (tarih == null || !mounted) return;
    setState(() => _islem = true);
    try {
      final id = await BireyselOdevKontrolService.kontrolOlustur(
        widget.oturum,
        widget.odevId,
        kontrolTarihi: tarih,
      );
      if (mounted) await _yukle(kontrol: id);
    } catch (e) {
      _mesaj('Kontrol oluşturulamadı. $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _kontrolSil() async {
    if (!_yaz || !await _vazgec() || !mounted) return;
    final onay = await odevDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kontrolü sil'),
        content: const Text(
          'Yalnız seçili tarihin değerlendirmeleri silinecek. Ortak uygulamalar ve diğer tarihler korunacak. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kontrolü sil'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    setState(() => _islem = true);
    try {
      await BireyselOdevKontrolService.kontrolSil(widget.oturum, _kid!);
      if (mounted) {
        _kid = null;
        await _yukle();
      }
    } catch (e) {
      _mesaj('Kontrol silinemedi. $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Future<void> _uygulamaDuzenle([DersUygulamasi? u]) async {
    if (!await _vazgec() || !mounted) return;
    final ad = TextEditingController(text: u?.ad ?? '');
    String? hata;
    await odevDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: Text(u == null ? 'Uygulama Ekle' : 'Uygulamayı düzenle'),
          content: TextField(
            key: const ValueKey('uygulama-adi'),
            controller: ad,
            autofocus: true,
            maxLength: 150,
            decoration: InputDecoration(
              labelText: 'Uygulama adı',
              errorText: hata,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await DersUygulamaIslemleri.uygulamaKaydet(
                    widget.oturum,
                    widget.odevId,
                    ad.text,
                    uygulamaId: u?.id,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) await _yukle();
                } catch (e) {
                  if (ctx.mounted) yenile(() => hata = '$e');
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    ad.dispose();
  }

  Future<void> _aktifligiDegistir(DersUygulamasi u) async {
    if (!await _vazgec() || !mounted) return;
    final onay = await odevDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          u.aktif ? 'Uygulamayı pasifleştir' : 'Uygulamayı etkinleştir',
        ),
        content: Text(
          '${u.ad}: Geçmiş değerlendirmeler korunur. Yalnız aktif uygulamalar ortalamaya katılır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    setState(() => _islem = true);
    try {
      await DersUygulamaIslemleri.uygulamaAktifligi(
        widget.oturum,
        widget.odevId,
        u.id,
        !u.aktif,
      );
      if (mounted) await _yukle();
    } catch (e) {
      _mesaj('$e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  UygulamaSonucu? _deger(int oid, int uid) {
    final t = _taslak[(oid, uid)];
    return t == null
        ? _son[(oid, uid)]
        : UygulamaSonucu.fromMap({
            'UygulamaId': uid,
            'OgrenciId': oid,
            'OdevKontrolId': _kid!,
            'KontrolTarihi': odevTarihYaz(
              _kontroller
                  .firstWhere((k) => k.odevKontrolId == _kid)
                  .kontrolTarihi,
            ),
            'Durum': t.durum.kayitDegeri,
            'NotDegeri': t.notDegeri,
            'Aciklama': t.aciklama,
            'Yapilan': t.yapilan,
            'Adet': t.adet,
          });
  }

  UygulamaIlerleme _ozet(int oid) => UygulamaIlerleme(
    _aktif,
    _aktif.map((u) => _deger(oid, u.id)).whereType<UygulamaSonucu>(),
  );
  void _ata(int oid, int uid, OdevKontrolDurumu d, {int? puan}) {
    final n = puan ?? OdevKontrolSonuc.hizliNot(d), eski = _son[(oid, uid)];
    final guncel = _deger(oid, uid);
    final sayilariKoru = d.puanlanabilir && d != OdevKontrolDurumu.manuel;
    final yapilan = sayilariKoru ? guncel?.yapilan : null;
    final adet = sayilariKoru ? guncel?.adet : null;
    final aciklama = eski?.aciklama;
    if ((eski?.durum ?? OdevKontrolDurumu.kontrolEdilmedi) == d &&
        eski?.notDegeri == n &&
        eski?.yapilan == yapilan &&
        eski?.adet == adet) {
      _taslak.remove((oid, uid));
    } else {
      _taslak[(oid, uid)] = UygulamaSonucGirdisi(
        oid,
        uid,
        d,
        notDegeri: n,
        aciklama: aciklama,
        yapilan: yapilan,
        adet: adet,
      );
    }
  }

  Future<void> _sonucSec(OdevOgrenci o, DersUygulamasi u) async {
    final d = await showModalBottomSheet<OdevKontrolDurumu>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(o.adSoyad), subtitle: Text(u.ad)),
              for (final d in OdevKontrolDurumu.secilebilir)
                ListTile(
                  leading: Text(d.sembol),
                  title: Text(odevDurumAdi(d)),
                  selected:
                      (_deger(o.ogrenciId, u.id)?.durum ??
                          OdevKontrolDurumu.kontrolEdilmedi) ==
                      d,
                  onTap: () => Navigator.pop(ctx, d),
                ),
            ],
          ),
        ),
      ),
    );
    if (d == null || !mounted) return;
    int? n;
    if (d == OdevKontrolDurumu.manuel) {
      final c = TextEditingController();
      String? hata;
      n = await odevDialog<int>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, yenile) => AlertDialog(
            title: const Text('Özel puan'),
            content: TextField(
              key: const ValueKey('uygulama-ozel-puan'),
              controller: c,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Puan (0–10)',
                errorText: hata,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  final p = int.tryParse(c.text);
                  if (p == null || p < 0 || p > 10) {
                    yenile(() => hata = '0–10 arasında tam sayı girin.');
                    return;
                  }
                  Navigator.pop(ctx, p);
                },
                child: const Text('Uygula'),
              ),
            ],
          ),
        ),
      );
      c.dispose();
      if (n == null || !mounted) return;
    }
    setState(() => _ata(o.ogrenciId, u.id, d, puan: n));
  }

  Future<void> _toplu() async {
    int? uid = _secili?.id;
    var durum = OdevKontrolDurumu.yapti;
    final secili = <int>{};
    if (uid == null) return;
    final onay = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .8,
            child: Column(
              children: [
                const Text('Toplu İşlem'),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<int>(
                    initialValue: uid,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Uygulama'),
                    items: [
                      for (final u in _aktif)
                        DropdownMenuItem(
                          value: u.id,
                          child: Text(u.ad, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => yenile(() => uid = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonFormField<OdevKontrolDurumu>(
                    initialValue: durum,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Sonuç'),
                    items: [
                      for (final d in OdevKontrolDurumu.secilebilir.where(
                        (d) => d != OdevKontrolDurumu.manuel,
                      ))
                        DropdownMenuItem(
                          value: d,
                          child: Text('${d.sembol} ${odevDurumAdi(d)}'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) yenile(() => durum = v);
                    },
                  ),
                ),
                TextButton(
                  onPressed: () => yenile(() {
                    if (secili.length == _ogrenciler.length) {
                      secili.clear();
                    } else {
                      secili.addAll(_ogrenciler.map((o) => o.ogrenciId));
                    }
                  }),
                  child: const Text('Tümünü seç / temizle'),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final o in _ogrenciler)
                        CheckboxListTile(
                          title: Text(o.adSoyad),
                          value: secili.contains(o.ogrenciId),
                          onChanged: (v) => yenile(() {
                            if (v == true) {
                              secili.add(o.ogrenciId);
                            } else {
                              secili.remove(o.ogrenciId);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: secili.isEmpty
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: Text('${secili.length} öğrenciye uygula'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (onay == true && mounted && uid != null) {
      setState(() {
        for (final oid in secili) {
          _ata(oid, uid!, durum);
        }
      });
    }
  }

  Future<void> _panel(String baslik, List<Widget> children) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .85,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                Text(baslik, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          ),
        ),
      );
  Future<void> _bilgiler() => _panel('Ödev bilgileri', [
    Text(_g!.baslik),
    const Text('Ders Uygulamaları'),
    Text('Başlangıç: ${_tarih(_g!.baslangicTarihi)}'),
    if (_g!.aciklama?.isNotEmpty == true) Text(_g!.aciklama!),
    Text('${_ogrenciler.length} öğrenci • ${_aktif.length} aktif uygulama'),
    const Text(
      'Ortalama 10 üzerinden eşit ağırlıkla hesaplanır. Boş ve G/M hesap dışı sonuçları ortalamaya katılmaz.',
    ),
    TextButton.icon(
      onPressed: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                OdevEklerScreen(oturum: widget.oturum, odevId: widget.odevId),
          ),
        );
      },
      icon: const Icon(Icons.attach_file),
      label: const Text('Ek Dosyalar'),
    ),
  ]);
  Future<void> _rapor() => _panel('Uygulama raporu', [
    if (_taslak.isNotEmpty) const Text('Kaydedilmemiş değişiklikleri içerir.'),
    for (final o in _ogrenciler)
      ListTile(
        title: Text(o.adSoyad),
        subtitle: Text(
          '${_ozet(o.ogrenciId).degerlendirilen}/${_aktif.length} değerlendirildi • ${_ozet(o.ogrenciId).bekleyen} bekleyen • ${_ozet(o.ogrenciId).hesapDisi} hesap dışı',
        ),
        trailing: Text(_ortalama(_ozet(o.ogrenciId).ortalama)),
      ),
  ]);
  Future<void> _gecmis([OdevOgrenci? o]) async {
    try {
      final rows = await DersUygulamaIslemleri.gecmis(
        widget.oturum,
        widget.odevId,
        ogrenciId: o?.ogrenciId,
      );
      if (!mounted) return;
      await _panel(o == null ? 'Değerlendirme geçmişi' : o.adSoyad, [
        if (rows.isEmpty) const Text('Kaydedilmiş değerlendirme yok.'),
        for (final s in rows.reversed)
          ListTile(
            title: Text(
              '${_uygulamalar.where((u) => u.id == s.uygulamaId).firstOrNull?.ad ?? 'Uygulama'} • ${odevDurumAdi(s.durum)}',
            ),
            subtitle: Text(
              '${_tarih(s.tarih)} • ${_ogrenciler.where((o) => o.ogrenciId == s.ogrenciId).firstOrNull?.adSoyad ?? 'Öğrenci'}',
            ),
            trailing: Text(
              s.durum == OdevKontrolDurumu.manuel
                  ? '${s.notDegeri}'
                  : s.durum.sembol,
            ),
          ),
      ]);
    } catch (e) {
      _mesaj('$e');
    }
  }

  String _ortalama(double? n) => n == null
      ? '— / 10'
      : '${n.toStringAsFixed(1).replaceAll('.', ',')} / 10';
  Widget _rozet(String text, {bool basari = false}) => Chip(
    visualDensity: VisualDensity.compact,
    backgroundColor: basari
        ? Theme.of(context).colorScheme.tertiaryContainer
        : Theme.of(context).colorScheme.primaryContainer,
    label: Text(text),
  );
  Widget _foto(OdevOgrenci o, {double radius = 22}) => CircleAvatar(
    radius: radius,
    backgroundImage: o.fotoVerisi == null ? null : MemoryImage(o.fotoVerisi!),
    child: o.fotoVerisi != null
        ? null
        : Text(o.ad.characters.firstOrNull?.toUpperCase() ?? 'Ö'),
  );

  Future<void> _ogrenciDetay(OdevOgrenci o) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .78,
            child: Column(
              children: [
                ListTile(
                  leading: _foto(o, radius: 27),
                  title: Text(o.adSoyad),
                  subtitle: Text(
                    'No: ${o.okulNo} • ${_ozet(o.ogrenciId).degerlendirilen}/${_aktif.length} uygulama',
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: [
                      for (final u in _aktif)
                        ListTile(
                          title: Text('${u.sira}. ${u.ad}'),
                          subtitle: Text(
                            _deger(o.ogrenciId, u.id)?.durum == null
                                ? 'Değerlendirilmedi'
                                : odevDurumAdi(
                                    _deger(o.ogrenciId, u.id)!.durum,
                                  ),
                          ),
                          trailing: OutlinedButton.icon(
                            onPressed: !_yaz
                                ? null
                                : () async {
                                    await _sonucSec(o, u);
                                    if (ctx.mounted) yenile(() {});
                                  },
                            icon: const Icon(Icons.arrow_drop_down),
                            label: Text(
                              _deger(o.ogrenciId, u.id)?.durum.sembol ?? 'Seç',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _gecmis(o);
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('Değerlendirme geçmişi'),
                ),
                if (_taslak.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: FilledButton.icon(
                      onPressed: !_yaz
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              await _kaydet();
                            },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Değişiklikleri kaydet'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _ogrenciKarti(OdevOgrenci o) {
    final oid = o.ogrenciId,
        ozet = _ozet(o.ogrenciId),
        acik = _acik.contains(o.ogrenciId);
    return Card(
      key: ValueKey('uygulama-ogrenci-$oid'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey('uygulama-ogrenci-ac-$oid'),
              onTap: () => setState(() {
                if (acik) {
                  _acik.remove(oid);
                } else {
                  _acik.add(oid);
                }
              }),
              child: Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      o.ad.characters.firstOrNull?.toUpperCase() ?? 'Ö',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OrtakBaslik(
                          o.adSoyad,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('No: ${o.okulNo}'),
                      ],
                    ),
                  ),
                  Icon(acik ? Icons.keyboard_double_arrow_up : Icons.keyboard_double_arrow_down),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                _rozet('${ozet.degerlendirilen}/${ozet.toplam} uygulama'),
                _rozet(_ortalama(ozet.ortalama), basari: true),
                _rozet('${ozet.bekleyen} bekleyen'),
              ],
            ),
            if (acik) ...[
              if (_aktif.isEmpty)
                const Text('Önce ortak listeye uygulama ekleyin.'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final u in _aktif)
                      SizedBox(
                        width: 180 * MediaQuery.textScalerOf(context).scale(1),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Tooltip(
                                message: u.ad,
                                child: Text(
                                  '${u.sira}. ${u.ad}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 6),
                              OutlinedButton(
                                key: ValueKey('uygulama-sonuc-$oid-${u.id}'),
                                onPressed: _yaz ? () => _sonucSec(o, u) : null,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: odevDurumZemini(
                                    _deger(oid, u.id)?.durum ??
                                        OdevKontrolDurumu.kontrolEdilmedi,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _deger(oid, u.id)?.durum ==
                                              OdevKontrolDurumu.manuel
                                          ? '${_deger(oid, u.id)?.notDegeri}'
                                          : (_deger(oid, u.id)?.durum.sembol ??
                                                '—'),
                                      style: TextStyle(
                                        color: odevDurumRengi(
                                          _deger(oid, u.id)?.durum ??
                                              OdevKontrolDurumu.kontrolEdilmedi,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.expand_more),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _islem ? null : () => _gecmis(o),
                  child: const Text('Geçmişi gör'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ColorScheme get _renkler => Theme.of(context).colorScheme;
  bool get _koyu => Theme.of(context).brightness == Brightness.dark;
  Color get _cizgi => _renkler.primary.withValues(alpha: _koyu ? .4 : .25);
  Color get _yazi => _koyu ? _renkler.onSurface : const Color(0xff101334);
  Color get _solukMavi => _koyu
      ? _renkler.surfaceContainer
      : Color.lerp(_renkler.surface, _renkler.primaryContainer, .28)!;

  Widget _kart(
    List<Widget> children, {
    bool vurgulu = false,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
  }) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _renkler.surfaceContainerLowest,
          vurgulu
              ? _solukMavi
              : Color.lerp(_renkler.surfaceContainerLowest, _solukMavi, .25)!,
        ],
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _cizgi, width: .7),
      boxShadow: [
        BoxShadow(
          color: _renkler.primary.withValues(alpha: .09),
          blurRadius: 3,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Future<void> _adet(int fark) async {
    final u = _secili;
    if (u == null || !_yaz || !await _vazgec() || !mounted) return;
    setState(() => _islem = true);
    try {
      await DersUygulamaIslemleri.adetKaydet(
        widget.oturum,
        widget.odevId,
        u.id,
        u.adet + fark,
      );
      await _yukle();
    } catch (e) {
      _mesaj('$e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  int _sayi(OdevOgrenci o, DersUygulamasi u) {
    final s = _deger(o.ogrenciId, u.id);
    return s?.yapilan ?? ((s?.puan ?? 0) / 10 * u.adet).round();
  }

  void _sayac(OdevOgrenci o, DersUygulamasi u, int fark) {
    final eski = _deger(o.ogrenciId, u.id), adet = eski?.adet ?? u.adet;
    final sayi = (_sayi(o, u) + fark).clamp(0, adet);
    if (sayi == _sayi(o, u)) return;
    final durum = eski?.durum.puanlanabilir == true
        ? eski!.durum
        : OdevKontrolDurumu.manuel;
    final notDegeri = durum == OdevKontrolDurumu.manuel
        ? (sayi / adet * 10).round()
        : OdevKontrolSonuc.hizliNot(durum);
    setState(() {
      final kayitli = _son[(o.ogrenciId, u.id)];
      if (kayitli?.yapilan == sayi &&
          kayitli?.adet == adet &&
          kayitli?.durum == durum) {
        _taslak.remove((o.ogrenciId, u.id));
      } else {
        _taslak[(o.ogrenciId, u.id)] = UygulamaSonucGirdisi(
          o.ogrenciId,
          u.id,
          durum,
          notDegeri: notDegeri,
          yapilan: sayi,
          adet: adet,
          aciklama: eski?.aciklama,
        );
      }
    });
  }


  (String, String, Color, Color) _durumGorunumu(UygulamaSonucu? s) {
    final d = s?.durum ?? OdevKontrolDurumu.kontrolEdilmedi;
    final (simge, ad, renk) = switch (d) {
      OdevKontrolDurumu.yapti => ('+', 'Tamam', const Color(0xff16a62a)),
      OdevKontrolDurumu.kismen => ('±', 'Kısmen', const Color(0xffd58c00)),
      OdevKontrolDurumu.yapmadi => ('−', 'Yapmadı', const Color(0xffd63142)),
      OdevKontrolDurumu.gelmedi => ('G', 'Gelmedi', const Color(0xff7842ce)),
      OdevKontrolDurumu.mazeretli => (
        'M',
        'Mazeretli',
        const Color(0xff7842ce),
      ),
      OdevKontrolDurumu.manuel when s?.yapilan != null =>
        s!.yapilan == s.adet
            ? ('+', 'Tamam', const Color(0xff16a62a))
            : s.yapilan == 0
            ? ('−', 'Yapmadı', const Color(0xffd63142))
            : ('±', 'Kısmen', const Color(0xffd58c00)),
      OdevKontrolDurumu.manuel => ('P', 'Manuel', _renkler.primary),
      _ => ('·', 'Bekliyor', _renkler.outline),
    };
    return (
      simge,
      ad,
      renk,
      Color.lerp(_renkler.surfaceContainerLowest, renk, _koyu ? .25 : .16)!,
    );
  }

  Widget _miniDugme(
    String etiket,
    IconData ikon,
    VoidCallback? action, {
    double width = 28,
    bool cerceve = true,
  }) => SizedBox(
    width: width,
    height: 32,
    child: IconButton(
      tooltip: etiket,
      onPressed: action,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        side: cerceve ? BorderSide(color: _cizgi, width: .7) : BorderSide.none,
        backgroundColor: cerceve
            ? _renkler.surfaceContainerLowest
            : Colors.transparent,
        foregroundColor: _renkler.primary,
      ),
      icon: Icon(ikon, size: 18),
    ),
  );

  Widget _colonlar(List<Widget> children) => Row(
    children: [
      Expanded(flex: 35, child: children[0]),
      const SizedBox(width: 4),
      Expanded(flex: 25, child: children[1]),
      const SizedBox(width: 4),
      Expanded(flex: 16, child: children[2]),
      const SizedBox(width: 4),
      Expanded(flex: 27, child: children[3]),
      const SizedBox(width: 14),
    ],
  );

  Widget _tabloBasligi() => Container(
    key: const ValueKey('uygulama-tablo-basligi'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: _solukMavi,
      border: Border.all(color: _cizgi, width: .7),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
    ),
    child: LayoutBuilder(
      builder: (ctx, c) {
        final texts = [
          'Öğrenci',
          'Yapılan / Adet (${_secili?.adet ?? 1})',
          'Puan (100)',
          'Sonuç',
        ];
        if (c.maxWidth < 330 || MediaQuery.textScalerOf(ctx).scale(1) > 1.3) {
          return Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final t in texts)
                Text(
                  t,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _yazi,
                  ),
                ),
            ],
          );
        }
        Widget etiket(String text) => Tooltip(
          message: text,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: _yazi,
            ),
          ),
        );
        return _colonlar([
          etiket(texts[0]),
          Row(
            children: [
              Expanded(child: etiket(texts[1])),
              const SizedBox(width: 2),
              Tooltip(
                message: 'Yapılan ve adet bilgisi',
                child: InkWell(
                  onTap: () => _panel('Yapılan / Adet', [
                    const Text(
                      'Sayaçlar yapılan parça sayısını değiştirir. Puan = (Yapılan ÷ Adet) × 100. Her kayıt değerlendirildiği andaki adedini korur.',
                    ),
                  ]),
                  child: Icon(
                    Icons.info_outline,
                    size: 13,
                    color: _renkler.primary,
                  ),
                ),
              ),
            ],
          ),
          etiket(texts[2]),
          etiket(texts[3]),
        ]);
      },
    ),
  );

  Widget _satir(OdevOgrenci o, {bool son = false}) {
    final u = _secili, acik = _acik.contains(o.ogrenciId);
    final sonuc = u == null ? null : _deger(o.ogrenciId, u.id);
    final (simge, ad, renk, zemin) = _durumGorunumu(sonuc);
    final adet = sonuc?.adet ?? u?.adet ?? 1;
    final kimlik = InkWell(
      onTap: _islem ? null : () => _ogrenciDetay(o),
      child: Row(
        children: [
          OgrenciFotoWidget(
            fotoYolu: o.fotoYolu,
            fotoVerisi: o.fotoVerisi,
            yerel: true,
            width: 28,
            height: 28,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: o.adSoyad,
                  child: Text(
                    o.adSoyad.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _yazi,
                    ),
                  ),
                ),
                Text(
                  'No: ${o.okulNo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: _yazi),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final sayac = Row(
      children: [
        _miniDugme(
          '${o.adSoyad}: yapılan azalt',
          Icons.remove,
          _yaz && u != null && _sayi(o, u) > 0 ? () => _sayac(o, u, -1) : null,
          width: 24,
        ),
        Expanded(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: _solukMavi,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _cizgi, width: .7),
            ),
            child: Text(
              '${u == null ? 0 : _sayi(o, u)} / $adet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _yazi,
              ),
            ),
          ),
        ),
        _miniDugme(
          '${o.adSoyad}: yapılan artır',
          Icons.add,
          _yaz && u != null && _sayi(o, u) < adet
              ? () => _sayac(o, u, 1)
              : null,
          width: 24,
        ),
      ],
    );
    final puan = Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: sonuc?.puan == null
              ? _renkler.surfaceContainerHighest
              : Color.lerp(
                  _renkler.surfaceContainerLowest,
                  Colors.green,
                  _koyu ? .3 : .16,
                ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.green.withValues(alpha: .22),
            width: .7,
          ),
        ),
        child: Text(
          sonuc?.puan == null
              ? (sonuc?.durum.degerlendirmeDisi == true ? '0,0' : '—')
              : (sonuc!.puan! * 10).toStringAsFixed(1).replaceAll('.', ','),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _yazi,
          ),
        ),
      ),
    );
    final durum = Tooltip(
      message: sonuc?.durum.degerlendirmeDisi == true ? '$ad • Ortalamaya katılmaz' : ad,
      child: OutlinedButton(
        onPressed: _yaz && u != null ? () => _sonucSec(o, u) : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: renk.withValues(alpha: .45), width: .7),
          backgroundColor: zemin,
          foregroundColor: _yazi,
          disabledForegroundColor: _yazi,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          children: [
            Text(
              simge,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: renk,
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                '($ad)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
            const Icon(Icons.expand_more, size: 14),
          ],
        ),
      ),
    );
    return Container(
      key: ValueKey('uygulama-satir-${o.ogrenciId}'),
      decoration: BoxDecoration(
        color: _renkler.surfaceContainerLowest,
        border: Border(
          left: BorderSide(color: _cizgi, width: .7),
          right: BorderSide(color: _cizgi, width: .7),
          bottom: BorderSide(color: _cizgi, width: .7),
        ),
        borderRadius: son
            ? const BorderRadius.vertical(bottom: Radius.circular(12))
            : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: LayoutBuilder(
              builder: (ctx, c) {
                final ok = InkWell(
                  onTap: _islem ? null : () => _ogrenciDetay(o),
                  child: Icon(
                    acik ? Icons.keyboard_double_arrow_up : Icons.keyboard_double_arrow_down,
                    size: 18,
                    color: _yazi,
                  ),
                );
                if (c.maxWidth < 330 ||
                    MediaQuery.textScalerOf(ctx).scale(1) > 1.3) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: kimlik),
                          ok,
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(width: 140, child: sayac),
                          puan,
                          SizedBox(width: 130, child: durum),
                        ],
                      ),
                    ],
                  );
                }
                return Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    _colonlar([kimlik, sayac, puan, durum]),
                    SizedBox(width: 14, child: ok),
                  ],
                );
              },
            ),
          ),
          if (acik) _ogrenciKarti(o),
        ],
      ),
    );
  }

  Widget _uygulamaPanel() => _kart(
    [
      LayoutBuilder(
        builder: (ctx, c) {
          final secim = DropdownButtonFormField<int>(
            key: ValueKey('uygulama-secim-${_secili?.id}'),
            initialValue: _secili?.id,
            isExpanded: true,
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _yazi,
            ),
            decoration: InputDecoration(
              labelText: 'Seçili uygulama',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              filled: true,
              fillColor: _renkler.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: _cizgi),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: _cizgi),
              ),
            ),
            items: [
              for (final u in _aktif)
                DropdownMenuItem(
                  value: u.id,
                  child: Text(
                    '${u.sira}. ${u.ad}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _islem ? null : (v) => setState(() => _seciliId = v),
          );
          return secim;
        },
      ),
    ],
    vurgulu: true,
    padding: const EdgeInsets.all(8),
  );

  Widget _adetPanel() => _kart([
    LayoutBuilder(
      builder: (ctx, c) {
        final baslik = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_outlined, color: _renkler.tertiary, size: 28),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'Adet (Katsayı)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _yazi,
                ),
              ),
            ),
          ],
        );
        final sayac = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _renkler.surfaceContainerLowest,
                    border: Border.all(color: _cizgi, width: .7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _miniDugme(
                        'Adeti azalt',
                        Icons.remove,
                        _yaz && (_secili?.adet ?? 1) > 1
                            ? () => _adet(-1)
                            : null,
                        width: 36,
                        cerceve: false,
                      ),
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${_secili?.adet ?? 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _yazi,
                          ),
                        ),
                      ),
                      _miniDugme(
                        'Adeti artır',
                        Icons.add,
                        _yaz && _secili != null && _secili!.adet < 10000
                            ? () => _adet(1)
                            : null,
                        width: 36,
                        cerceve: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _miniDugme(
                  'Adet bilgisi',
                  Icons.info_outline,
                  () => _panel('Adet (Katsayı)', [
                    const Text(
                      'Puan = (Yapılan ÷ Adet) × 100. Kayıtlı sonuçlar kendi adedini korur. Adet değişikliği hemen kaydedilir.',
                    ),
                  ]),
                  width: 28,
                  cerceve: false,
                ),
              ],
            ),
            Text(
              '1 = tek uygulama (varsayılan)',
              style: TextStyle(fontSize: 10, color: _yazi),
            ),
          ],
        );
        if (c.maxWidth < 340 || MediaQuery.textScalerOf(ctx).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [baslik, const SizedBox(height: 6), sayac],
          );
        }
        return Row(
          children: [
            Expanded(child: baslik),
            sayac,
          ],
        );
      },
    ),
  ], padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6));

  Future<void> _tumUygulamalar() => _panel('Tüm Uygulamalar', [
    for (final u in _aktif)
      ListTile(
        title: Text('${u.sira}. ${u.ad}'),
        trailing: IconButton(
          tooltip: '${u.ad} düzenle',
          onPressed: _islem || _g?.aktif != true
              ? null
              : () {
                  Navigator.pop(context);
                  _uygulamaDuzenle(u);
                },
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
  ]);

  Future<void> _puanlama() => _panel('Puanlama', [
    const Text(
      'Puan = (Yapılan ÷ Adet) × 100. Hesap dışı sonuçlar ortalamaya katılmaz.',
    ),
    ListTile(
      key: const ValueKey('uygulama-kontrol-sec'),
      leading: const Icon(Icons.calendar_month),
      title: const Text('Kontrol tarihi seç'),
      subtitle: Text(
        _kontroller
                .where((k) => k.odevKontrolId == _kid)
                .map(_kontrolAdi)
                .firstOrNull ??
            'Kontrol tarihi seçin',
      ),
      onTap: _islem || _kontroller.isEmpty
          ? null
          : () {
              Navigator.pop(context);
              _kontrolSec();
            },
    ),
    if (_g?.aktif == true)
      ListTile(
        leading: const Icon(Icons.add),
        title: const Text('Yeni kontrol'),
        onTap: _islem
            ? null
            : () {
                Navigator.pop(context);
                _yeniKontrol();
              },
      ),
  ]);

  Widget _islemDugmesi(
    String text,
    IconData icon,
    VoidCallback? action, {
    bool ana = false,
    bool ok = false,
  }) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (ok) ...[
          const SizedBox(width: 6),
          const Icon(Icons.expand_more, size: 17),
        ],
      ],
    );
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: ana ? _renkler.primary : _solukMavi,
      foregroundColor: ana ? Colors.white : _yazi,
      side: BorderSide(color: _cizgi, width: .7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return ana
        ? FilledButton(onPressed: action, style: style, child: child)
        : OutlinedButton(onPressed: action, style: style, child: child);
  }

  Widget _islemler() => LayoutBuilder(
    builder: (ctx, c) {
      final buttons = [
        UygulamaEkleTanitim(key:const ValueKey('uygulama-ekle-tanitim'),enabled:_g?.aktif==true,child:_islemDugmesi(
          'Uygulama Ekle',
          Icons.add,
          _islem || _g?.aktif != true ? null : () => _uygulamaDuzenle(),
          ana: true,
        )),
        _islemDugmesi(
          'Düzenle',
          Icons.edit_outlined,
          _islem || _g?.aktif != true || _secili == null
              ? null
              : () => _uygulamaDuzenle(_secili),
        ),
        _islemDugmesi(
          'Tüm Uygulamalar',
          Icons.format_list_bulleted,
          _islem ? null : _tumUygulamalar,
        ),
        _islemDugmesi(
          'Puanlama',
          Icons.save_outlined,
          _islem ? null : _puanlama,
          ok: true,
        ),
      ];
      if (c.maxWidth < 330 || MediaQuery.textScalerOf(ctx).scale(1) > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final button in buttons)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: button),
          ],
        );
      }
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: buttons[0]),
              const SizedBox(width: 10),
              Expanded(child: buttons[1]),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: buttons[2]),
              const SizedBox(width: 10),
              Expanded(child: buttons[3]),
            ],
          ),
        ],
      );
    },
  );

  Widget _ogrenciPanel() => _kart([
    LayoutBuilder(
      builder: (ctx, c) {
        final baslik = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, color: _renkler.primary, size: 27),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Öğrenciler (${_ogrenciler.length})',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _yazi,
                ),
              ),
            ),
          ],
        );
        final islemler = Wrap(
          children: [
            TextButton(
              onPressed: _islem
                  ? null
                  : () => setState(
                      () => _acik.addAll(_ogrenciler.map((o) => o.ogrenciId)),
                    ),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Tümünü Aç', style: TextStyle(fontSize: 11)),
            ),
            TextButton(
              onPressed: _islem ? null : () => setState(_acik.clear),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Tümünü Kapat', style: TextStyle(fontSize: 11)),
            ),
          ],
        );
        if (c.maxWidth < 340 || MediaQuery.textScalerOf(ctx).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [baslik, islemler],
          );
        }
        return Row(
          children: [
            Expanded(child: baslik),
            islemler,
          ],
        );
      },
    ),
    const SizedBox(height: 5),
    TextField(
      key: const ValueKey('uygulama-arama'),
      controller: _aramaGirdisi,
      focusNode: _aramaOdak,
      onChanged: (v) => setState(() => _arama = v.toLowerCase()),
      style: TextStyle(fontSize: 12, color: _yazi),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 26,
        ),
        hintText: 'Öğrenci ara...',
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        filled: true,
        fillColor: _renkler.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _cizgi),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _cizgi),
        ),
      ),
    ),
    const SizedBox(height: 6),
    _islemDugmesi(
      'Toplu İşlem',
      Icons.checklist,
      _yaz && _aktif.isNotEmpty ? _toplu : null,
      ok: true,
    ),
  ], padding: const EdgeInsets.all(8));

  Widget _kayitAlani() {
    final degisen = _taslak.keys.map((k) => k.$1).toSet().length;
    final bilgi = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline, size: 21, color: _renkler.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Puan = (Yapılan ÷ Adet) × 100',
            style: TextStyle(fontSize: 10, color: _yazi),
          ),
        ),
      ],
    );
    final durum = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          degisen > 0 ? Icons.check_circle_outline : Icons.check_circle_outline,
          size: 21,
          color: Colors.green,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            degisen > 0 ? 'Değişiklik var ($degisen)' : 'Değişiklik yok',
            style: TextStyle(fontSize: 11, color: _yazi),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kart([
            LayoutBuilder(
              builder: (ctx, c) {
                if (c.maxWidth < 330 ||
                    MediaQuery.textScalerOf(ctx).scale(1) > 1.3) {
                  return Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [bilgi, durum],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 6, child: bilgi),
                    Container(height: 20, width: .7, color: _cizgi),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: durum),
                  ],
                );
              },
            ),
          ], padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('uygulama-kaydet'),
            onPressed: _yaz && _taslak.isNotEmpty ? _kaydet : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(vertical: 6),
              disabledBackgroundColor: _renkler.primary.withValues(alpha: .65),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.save_outlined, size: 20),
            label: Text(
              _islem ? 'Kaydediliyor...' : 'Kaydet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _aramayaGit() async {
    if (_aramaGirdisi.text.isNotEmpty) {
      setState(() {
        _arama = '';
        _aramaGirdisi.clear();
      });
    }
    if (_kaydirma.hasClients) {
      await _kaydirma.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
    if (!mounted) return;
    final alan = _aramaAlani.currentContext;
    if (alan != null && alan.mounted) {
      await Scrollable.ensureVisible(
        alan,
        duration: const Duration(milliseconds: 200),
        alignment: .1,
      );
    }
    if (mounted) _aramaOdak.requestFocus();
  }

  Widget _altDugme(String text, IconData icon, VoidCallback? action) =>
      Expanded(
        child: TextButton(
          onPressed: action,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, color: _yazi),
                ),
              ),
            ],
          ),
        ),
      );
  Future<void> _diger(String v) async {
    switch (v) {
      case 'bilgiler':
        await _bilgiler();
      case 'rapor':
        await _rapor();
      case 'yeni':
        await _yeniKontrol();
      case 'sil':
        await _kontrolSil();
      case 'gecmis':
        await _gecmis();
      case 'pasif':
        await _panel('Uygulama yönetimi', [
          for (final u in _uygulamalar)
            ListTile(
              title: Text(u.ad),
              subtitle: Text(u.aktif ? 'Aktif' : 'Pasif'),
              trailing: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _aktifligiDegistir(u);
                },
                child: Text(u.aktif ? 'Pasifleştir' : 'Etkinleştir'),
              ),
            ),
        ]);
      case 'duzenle':
        if (await _vazgec() && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OdevTanimScreen(oturum: widget.oturum, gorev: _g),
            ),
          );
          if (mounted) await _yukle();
        }
    }
  }


  Future<void> _katilimDuzenle({required bool ekle}) async {
    if (_g?.aktif != true || _islem || !await _vazgec() || !mounted) return;
    try {
      final g = _g!;
      final tum = await BireyselOdevKontrolService.katilimcilar(
          widget.oturum, widget.odevId);
      final aktif = tum.where((o) => o.aktif).map((o) => o.ogrenciId).toSet();
      final adaylar = ekle
          ? (await BireyselOdevKontrolService.ogrenciSecenekleri(
                  widget.oturum, g.sinifSubeId))
              .where((o) => !aktif.contains(o['OgrenciId'] as int))
              .map((o) => (id: o['OgrenciId'] as int,
                  ad: '${o['Ad'] ?? ''} ${o['Soyad'] ?? ''}'.trim(),
                  no: '${o['OkulNo'] ?? ''}'))
              .toList()
          : tum.where((o) => o.aktif)
              .map((o) => (id: o.ogrenciId, ad: o.adSoyad, no: o.okulNo))
              .toList();
      if (!mounted) return;
      if (adaylar.isEmpty) {
        _mesaj(ekle ? 'Eklenebilecek öğrenci yok.' : 'Çıkarılabilecek öğrenci yok.');
        return;
      }
      final secilen = <int>{};
      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, yenile) => AlertDialog(
            title: Text(ekle ? 'Öğrenci Ekle' : 'Öğrenci Çıkar'),
            content: SizedBox(width: double.maxFinite,
              child: ListView(shrinkWrap: true, children: [
                for (final o in adaylar)
                  CheckboxListTile(
                    value: secilen.contains(o.id),
                    title: Text(o.ad),
                    subtitle: Text('No: ${o.no}'),
                    onChanged: (v) => yenile(() {
                      if (v == true) { secilen.add(o.id); }
                      else { secilen.remove(o.id); }
                    }),
                  ),
              ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
              FilledButton(onPressed: secilen.isEmpty ? null :
                () => Navigator.pop(ctx, true),
                child: Text(ekle ? 'Ekle' : 'Devam')),
            ],
          ),
        ),
      );
      if (onay != true || !mounted) return;
      if (!ekle) {
        final kesin = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Öğrencileri ödevden çıkar'),
            content: const Text('Yalnızca aktif ödev katılımı kaldırılacak. '
                'Önceki kontroller ve değerlendirmeler korunacak.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Çıkar')),
            ],
          ),
        );
        if (kesin != true || !mounted) return;
      }
      setState(() => _islem = true);
      if (ekle) {
        await BireyselOdevKontrolService.gorevGuncelle(
          widget.oturum, widget.odevId,
          gorevTuru: g.gorevTuru,
          baslik: g.baslik,
          baslangicTarihi: g.baslangicTarihi,
          teslimTarihi: g.teslimTarihi,
          aciklama: g.aciklama,
          donem: g.donem,
          ogrenciIdleri: {...aktif, ...secilen}.toList(),
        );
      } else {
        await BireyselOdevKontrolService.katilimcilariCikar(
            widget.oturum, widget.odevId, secilen);
      }
      if (mounted) await _yukle();
    } catch (e) {
      _mesaj('Öğrenci işlemi başarısız. Orijinal hata: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  Widget _digerMenu() => PopupMenuButton<String>(
              tooltip: 'Uygulama işlemleri',
              enabled: !_bekle && !_islem && _g != null,
              onSelected: _diger,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'bilgiler', child: Text('Bilgiler')),
                const PopupMenuItem(value: 'rapor', child: Text('Rapor')),
                if (_g?.aktif == true)
                  const PopupMenuItem(
                    value: 'yeni',
                    child: Text('Yeni kontrol'),
                  ),
                if (_yaz)
                  const PopupMenuItem(
                    value: 'sil',
                    child: Text('Seçili kontrolü sil'),
                  ),
                const PopupMenuItem(
                  value: 'gecmis',
                  child: Text('Değerlendirme geçmişi'),
                ),
                if (_g?.aktif == true) ...[
                  const PopupMenuItem(
                    value: 'pasif',
                    child: Text('Uygulama yönetimi'),
                  ),
                  const PopupMenuItem(
                    value: 'duzenle',
                    child: Text('Ödevi düzenle'),
                  ),
                ],
              ],
              icon: const Icon(Icons.more_vert),
            );

  @override
  Widget build(BuildContext context) {
    final rows = _ogrenciler
        .where((o) => '${o.okulNo} ${o.adSoyad}'.toLowerCase().contains(_arama))
        .toList();
    final sinif = widget.oturum.siniflar
        .where((s) => s.sinifSubeId == _g?.sinifSubeId)
        .firstOrNull
        ?.sinif;
    return OdevTema(
      child: PopScope<void>(
        canPop: !_islem && _taslak.isEmpty,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _cik();
        },
        child: OrtakSayfa(
          appBar: OdevBaslik(
            title: Row(
              children: [
                const Icon(Icons.assignment_turned_in_outlined, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ödev Kontrolü',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Ders Uygulamaları${sinif == null ? '' : ' – $sinif'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [_digerMenu()],
          ),
          backgroundColor: _koyu
              ? _renkler.surface
              : Color.lerp(_renkler.surface, Colors.white, .6),
          body: _bekle
              ? const Center(child: CircularProgressIndicator())
              : _hata != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_hata!),
                      TextButton(
                        onPressed: _islem ? null : _yukle,
                        child: const Text('Yeniden dene'),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  key: const ValueKey('uygulama-icerik'),
                  controller: _kaydirma,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                      sliver: SliverList.list(
                        children: [
                          OrtakGenisleyenBolum(
                            key:const ValueKey('uygulama-ayarlari'),
                            title:const Text('Uygulama Listesi'),
                            subtitle:Text('Sınıf ortak • ${_aktif.length} uygulama'),
                            leading:const Icon(Icons.code),initiallyExpanded:false,maintainState:true,
                            childrenPadding:const EdgeInsets.only(top:10),children:[
                          _uygulamaPanel(),
                          const SizedBox(height: 10),
                          _adetPanel(),
                          const SizedBox(height: 12),
                          _islemler(),
                          ]),
                          const SizedBox(height: 12),
                          ListTile(
                            title: Text('Öğrenciler (${_ogrenciler.length})'),
                            trailing: Icon(_ogrenciBolumuAcik
                                ? Icons.expand_less : Icons.expand_more),
                            onTap: () => setState(() =>
                                _ogrenciBolumuAcik = !_ogrenciBolumuAcik),
                          ),
                          if (_ogrenciBolumuAcik) ...[
                          KeyedSubtree(
                            key: _aramaAlani,
                            child: _ogrenciPanel(),
                          ),
                          const SizedBox(height: 10),
                          if (_kid == null && _g!.aktif) ...[
                            OutlinedButton(
                              onPressed: _islem ? null : _yeniKontrol,
                              child: const Text('Not girişini başlat'),
                            ),
                            const SizedBox(height: 8),
                          ],
                          _tabloBasligi(),
                          if (rows.isEmpty)
                            _kart([
                              Text(
                                _ogrenciler.isEmpty
                                    ? 'Henüz öğrenci yok.'
                                    : 'Öğrenci bulunamadı.',
                              ),
                            ]),
                          ],
                        ],
                      ),
                    ),
                    if (_ogrenciBolumuAcik) SliverPadding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      sliver: SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (ctx, i) =>
                            _satir(rows[i], son: i == rows.length - 1),
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: OdevOrtakAltIslemler(
            ogrenciEkle: _g?.aktif == true && !_bekle && !_islem
                ? () => _katilimDuzenle(ekle: true) : null,
            ogrenciCikar: _g?.aktif == true && !_bekle && !_islem &&
                    _ogrenciler.isNotEmpty
                ? () => _katilimDuzenle(ekle: false) : null,
            kaydet: _yaz && _taslak.isNotEmpty ? _kaydet : null,
          ),
        ),
      ),
    );
  }
}
