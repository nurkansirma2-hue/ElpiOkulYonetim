import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/mesajlasma.dart';
import '../models/ortak_import.dart';
import '../services/mesajlasma_service.dart';
import '../services/belge_disari_aktar_service.dart';
import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import '../widgets/ogrenci_foto_widget.dart';
import 'ortak_import_screen.dart';

class VeliBilgileriScreen extends StatefulWidget {
  const VeliBilgileriScreen({super.key, this.service, this.excel = false});
  final MesajlasmaService? service;
  final bool excel;
  @override
  State<VeliBilgileriScreen> createState() => _VeliBilgileriScreenState();
}

class _VeliBilgileriScreenState extends State<VeliBilgileriScreen> {
  MesajlasmaService get _service =>
      widget.service ?? MesajlasmaService.instance;
  MesajBaglami? _baglam;
  List<Map<String, Object?>> _siniflar = [];
  List<Map<String, String>> _satirlar = [];
  final _alanlar = <String, Map<String, TextEditingController>>{};
  final _arama = TextEditingController();
  Map<int, Map<String, Object?>> _fotograflar = {};
  int? _sinifId;
  String? _hata;
  bool _mesgul = false, _degisti = false, _cikabilir = false;
  bool _excel = false, _modal = false;

  @override
  void initState() {
    super.initState();
    _excel = widget.excel;
    _hazirla();
  }

  @override
  void dispose() {
    _arama.dispose();
    _temizle();
    super.dispose();
  }

  void _temizle() {
    for (final a in _alanlar.values) {
      for (final c in a.values) {
        c.dispose();
      }
    }
    _alanlar.clear();
  }

  Future<void> _islem(Future<void> Function() f) async {
    if (_mesgul) return;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _hata = 'İşlem tamamlanamadı. $e');
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _hazirla() => _islem(() async {
    final b = await _service.hazirla();
    // sqflite sonuçları salt okunurdur; yalnız ekranın kopyasını sırala.
    final siniflar = (await _service.mesajSiniflari(b)).toList();
    siniflar.sort((a, b) {
      final aa = a['SinifKodu'].toString(), bb = b['SinifKodu'].toString();
      final n = _seviye(aa).compareTo(_seviye(bb));
      return n != 0 ? n : aa.compareTo(bb);
    });
    if (!mounted) return;
    _baglam = b;
    _siniflar = siniflar;
    _sinifId = siniflar.isEmpty ? null : siniflar.first['SinifSubeId'] as int;
    await _yukle();
  });

  int _seviye(String s) =>
      int.tryParse(RegExp(r'^\d+').stringMatch(s) ?? '') ?? 0;
  String get _sinifAdi =>
      _siniflar
          .where((s) => s['SinifSubeId'] == _sinifId)
          .map((s) => s['SinifKodu'].toString())
          .firstOrNull ??
      '';

  Future<void> _yukle() async {
    final rows = _sinifId == null
        ? <Map<String, String>>[]
        : await _service.veliSinifBilgileri(_baglam!, _sinifId!);
    final fotograflar = _sinifId == null
        ? <int, Map<String, Object?>>{}
        : await _service.veliFotograflari(_baglam!, _sinifId!);
    if (!mounted) return;
    _temizle();
    _satirlar = rows;
    _fotograflar = fotograflar;
    for (final r in rows) {
      _alanlar[r['OgrenciId']!] = {
        for (final k in VeliBilgileriIslemleri.alanlar.keys)
          k: TextEditingController(text: r[k] ?? ''),
      };
    }
    _degisti = false;
  }

  Future<bool> _vazgec() async {
    if (!_degisti) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Değişikliklerden vazgeçilsin mi?'),
            content: const Text('Kaydedilmemiş girişleriniz var.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Düzenlemeye dön'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Vazgeç'),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _sinifSec(int? id) async {
    if (id == null || id == _sinifId || _mesgul || !await _vazgec()) return;
    await _islem(() async {
      _sinifId = id;
      await _yukle();
    });
  }

  Future<void> _kaydet() => _islem(() async {
    final p = await _service.veliOnizle(_baglam!, _sinifId!, [
      for (final r in _satirlar)
        ImportKaynakSatiri(
          r['OgrenciId']!,
          '${r['OkulNo']} • ${r['Ad']} ${r['Soyad']}',
          {
            ...r,
            for (final e in _alanlar[r['OgrenciId']]!.entries)
              e.key: e.value.text,
          },
        ),
    ], beklenen: _satirlar);
    if (!mounted) return;
    final uygun = p.kayitlar.where((r) => r.aktarilabilir).toList();
    setState(() => _modal = true);
    final bool? onay;
    try {
      onay = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            p.engeller.isEmpty
                ? 'Değişiklikleri onaylayın'
                : 'Girişleri kontrol edin',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${uygun.length} öğrenci güncellenecek. Boş alanlar mevcut bilgileri silmez.',
                  ),
                  for (final r in p.kayitlar.where(
                    (r) => r.durum != ImportDurumu.atlanan,
                  )) ...[
                    const Divider(),
                    Text(r.konum, style: Theme.of(c).textTheme.titleSmall),
                    for (final m in r.mesajlar) Text(m),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Geri'),
            ),
            FilledButton(
              onPressed: p.engeller.isNotEmpty || uygun.isEmpty
                  ? null
                  : () => Navigator.pop(c, true),
              child: const Text('Onayla ve Kaydet'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _modal = false);
    }
    if (onay != true) return;
    final sonuc = await _service.veliAktar(p, uygun.map((r) => r.id).toSet());
    await _yukle();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(sonuc.mesaj)));
    }
  });

  Future<void> _sablon({bool bos = false}) => _islem(() async {
    final rows = await _service.veliSinifBilgileri(_baglam!, _sinifId!);
    final bytes = await BelgeDisariAktarService.excelOlustur(
      _service.veliImportTanimi(_baglam!, _sinifId!),
      [
        for (final r in rows)
          ImportKaydi(r['OgrenciId']!, '', {
            ...r,
            if (bos)
              for (final k in VeliBilgileriIslemleri.alanlar.keys) k: '',
          }),
      ],
      sablon: true,
    );
    final yol = await BelgeDisariAktarService.kaydet(
      '${_sinifAdi}_Veli_Bilgileri${bos ? "_Bos" : ""}.xlsx',
      bytes,
    );
    if (mounted && yol != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel şablonu kaydedildi.')),
      );
    }
  });

  Future<void> _import() => _islem(() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrtakImportScreen(
          tanim: _service.veliImportTanimi(_baglam!, _sinifId!),
          birlesikKaynakSecimi: true,
        ),
      ),
    );
    await _yukle();
  });

  Widget _baslik(IconData icon, String title, String desc) => Container(
    padding: const EdgeInsets.all(OrtakUi.bosluk),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(OrtakUi.radius),
    ),
    child: Row(
      children: [
        CircleAvatar(child: Icon(icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(desc, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _secimler() {
    final seviyeler =
        _siniflar
            .map((s) => _seviye(s['SinifKodu'].toString()))
            .toSet()
            .toList()
          ..sort();
    final seviye = _seviye(_sinifAdi);
    return LayoutBuilder(
      builder: (c, limits) {
        final sinif = DropdownButtonFormField<int>(
          key: ValueKey('seviye:$seviye'),
          initialValue: seviyeler.contains(seviye) ? seviye : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Sınıf'),
          items: [
            for (final n in seviyeler)
              DropdownMenuItem(value: n, child: Text('$n. Sınıf')),
          ],
          onChanged: _mesgul
              ? null
              : (n) => _sinifSec(
                  _siniflar.firstWhere(
                        (s) => _seviye(s['SinifKodu'].toString()) == n,
                      )['SinifSubeId']
                      as int,
                ),
        );
        final sube = DropdownButtonFormField<int>(
          key: ValueKey('sube:$_sinifId'),
          initialValue: _sinifId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Şube'),
          items: [
            for (final s in _siniflar.where(
              (s) => _seviye(s['SinifKodu'].toString()) == seviye,
            ))
              DropdownMenuItem(
                value: s['SinifSubeId'] as int,
                child: Text(
                  s['SinifKodu'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _mesgul ? null : _sinifSec,
        );
        return Row(
          children: [
            Expanded(child: sinif),
            const SizedBox(width: 12),
            Expanded(child: sube),
          ],
        );
      },
    );
  }

  Widget _alan(String id, String key) => TextFormField(
    key: ValueKey('$id:$key'),
    controller: _alanlar[id]![key],
    enabled: !_mesgul,
    maxLength: key.contains('Telefon') ? 50 : 200,
    keyboardType: key.contains('Telefon')
        ? TextInputType.phone
        : TextInputType.name,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: VeliBilgileriIslemleri.alanlar[key],
      counterText: '',
      errorText:
          key.contains('Telefon') &&
              _alanlar[id]![key]!.text.trim().isNotEmpty &&
              mesajTelefonNormalize(_alanlar[id]![key]!.text) == null
          ? 'Geçerli telefon girin.'
          : null,
      prefixIcon: Icon(
        key.contains('Telefon') ? Icons.phone_outlined : Icons.person_outline,
      ),
    ),
    onChanged: (_) => setState(() => _degisti = true),
  );

  Widget _ogrenci(Map<String, String> r) {
    final id = r['OgrenciId']!, a = _alanlar[r['OgrenciId']]!;
    final tur = a['VeliTuru']!.text;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (c, limits) {
                final baslik = Row(
                  children: [
                    OgrenciFotoWidget(
                      fotoYolu:
                          _fotograflar[int.parse(id)]?['DosyaYolu'] as String?,
                      fotoVerisi:
                          _fotograflar[int.parse(id)]?['FotoVerisi']
                              as Uint8List?,
                      yerel: true,
                      width: 36,
                      height: 36,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${r['OkulNo']} - ${r['Ad']} ${r['Soyad']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                );
                final secim = DropdownButtonFormField<String>(
                  key: ValueKey('$id:tur:$tur'),
                  initialValue: {'Anne', 'Baba', 'Diger'}.contains(tur)
                      ? tur
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Veli türü'),
                  items: const [
                    DropdownMenuItem(value: 'Anne', child: Text('Anne')),
                    DropdownMenuItem(value: 'Baba', child: Text('Baba')),
                    DropdownMenuItem(value: 'Diger', child: Text('Diğer')),
                  ],
                  onChanged: _mesgul
                      ? null
                      : (v) => setState(() {
                          a['VeliTuru']!.text = v!;
                          _degisti = true;
                        }),
                );
                if (limits.maxWidth >= 340 &&
                    MediaQuery.textScalerOf(c).scale(14) < 19) {
                  return Row(
                    children: [
                      Expanded(child: baslik),
                      const SizedBox(width: 8),
                      SizedBox(width: 130, child: secim),
                    ],
                  );
                }
                return Column(
                  children: [baslik, const SizedBox(height: 8), secim],
                );
              },
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (c, limits) {
                final alanlar = [
                  'Telefon',
                  'AnneAdi',
                  'AnneTelefon',
                  'BabaAdi',
                  'BabaTelefon',
                  if (tur == 'Diger') ...[
                    'VeliAdi',
                    'VeliYakinlik',
                    'VeliTelefonu',
                  ],
                ];
                final genis =
                    limits.maxWidth >= 320 &&
                    MediaQuery.textScalerOf(c).scale(14) < 21;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in alanlar)
                      SizedBox(
                        width: genis
                            ? (limits.maxWidth - 8) / 2
                            : limits.maxWidth,
                        child: _alan(id, k),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _excelIcerik() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 8,
        runSpacing: 8,
        children: [
          Text('1 Şablon'),
          Text('2 Yükle'),
          Text('3 Önizle'),
          Text('4 Kaydet'),
        ],
      ),
      const SizedBox(height: 12),
      _baslik(
        Icons.table_view,
        'Veli Bilgilerini Excel’den Güncelle',
        'Seçilen sınıftaki mevcut iletişim ve veli bilgilerini toplu olarak güncelleyin.',
      ),
      const SizedBox(height: 16),
      Text(
        '1  Dolu Şablonu İndir',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      _secimler(),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _mesgul || _sinifId == null ? null : () => _sablon(),
        icon: const Icon(Icons.download),
        label: Text('Dolu Şablonu İndir ($_sinifAdi)'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _mesgul || _sinifId == null
            ? null
            : () => _sablon(bos: true),
        icon: const Icon(Icons.download_outlined),
        label: const Text('Boş Şablon'),
      ),
      const SizedBox(height: 12),
      const Text(
        'Okul no, ad ve soyad otomatik doldurulur; değiştirilmez. '
        'Yalnız iletişim ve veli bilgilerini girin. Boş şablonda da öğrenci kimlikleri korunur. Boş hücreler mevcut veriyi silmez.',
      ),
      const SizedBox(height: 16),
      Text(
        '2  Excel Dosyasını Yükle',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'İleri ile Excel dosyanızı seçin. '
        'Önizleme, hata kontrolü ve açık onaydan sonra kayıt yapılır.',
      ),
      const SizedBox(height: 16),
      Text(
        '3  Şablon Sütunları',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (var i = 0; i < 12; i++)
              DataColumn(label: Text(String.fromCharCode(65 + i))),
          ],
          rows: [
            DataRow(
              cells: [
                for (final ad in [
                  'Okul No',
                  'Ad',
                  'Soyad',
                  ...VeliBilgileriIslemleri.alanlar.values,
                ])
                  DataCell(SizedBox(width: 80, child: Text(ad))),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Veli türü: Anne / Baba / Diğer. Diğer seçildiğinde veli adı, yakınlığı ve telefonu gereklidir.',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final filtre = _arama.text.trim().toLowerCase();
    final gorunen = _satirlar
        .where(
          (r) => '${r['OkulNo']} ${r['Ad']} ${r['Soyad']}'
              .toLowerCase()
              .contains(filtre),
        )
        .toList();
    return PopScope(
      canPop: _cikabilir || (!_degisti && !_mesgul),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _mesgul || !await _vazgec() || !context.mounted) return;
        setState(() => _cikabilir = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      },
      child: OrtakSayfa(
        appBar: ModulUstBar(
          title: Text(
            _excel
                ? 'Veli Bilgilerini İçe Aktar (Excel)'
                : 'Veli Bilgileri (Hızlı Giriş)',
          ),
        ),
        bottomNavigationBar: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (!_excel)
              Chip(label: Text('$_sinifAdi / ${_satirlar.length} öğrenci')),
            TextButton(
              onPressed: _mesgul ? null : () => Navigator.maybePop(context),
              child: const Text('İptal'),
            ),
            FilledButton.icon(
              onPressed: _mesgul || _sinifId == null
                  ? null
                  : _excel
                  ? _import
                  : _degisti
                  ? _kaydet
                  : null,
              icon: Icon(_excel ? Icons.arrow_forward : Icons.save_outlined),
              label: Text(_excel ? 'İleri' : 'Kaydet'),
            ),
          ],
        ),
        body: _baglam == null
            ? Center(
                child: _hata != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_hata!),
                          TextButton(
                            onPressed: _mesgul ? null : _hazirla,
                            child: const Text('Yeniden Dene'),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(),
              )
            : Column(
                children: [
                  if (_mesgul && !_modal) const LinearProgressIndicator(),
                  if (_hata != null)
                    MaterialBanner(
                      content: Text(_hata!),
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => _hata = null),
                          child: const Text('Kapat'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: _siniflar.isEmpty
                        ? const Center(
                            child: Text(
                              'Ders kapsamınızda sınıf yok. Önce ders programınızı yükleyin.',
                            ),
                          )
                        : _excel
                        ? _excelIcerik()
                        : CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.all(12),
                                sliver: SliverToBoxAdapter(
                                  child: Column(
                                    children: [
                                      _baslik(
                                        Icons.groups_outlined,
                                        'Sınıf Bazlı Veli Bilgisi Girişi',
                                        'Seçtiğiniz sınıftaki öğrencilerin veli ve iletişim bilgilerini hızla düzenleyin.',
                                      ),
                                      const SizedBox(height: 16),
                                      _secimler(),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: _arama,
                                        decoration: const InputDecoration(
                                          prefixIcon: Icon(Icons.search),
                                          hintText: 'Öğrenci ara…',
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: _mesgul
                                              ? null
                                              : () async {
                                                  if (!await _vazgec() ||
                                                      !mounted) {
                                                    return;
                                                  }
                                                  await _islem(_yukle);
                                                  if (mounted) {
                                                    setState(
                                                      () => _excel = true,
                                                    );
                                                  }
                                                },
                                          icon: const Icon(Icons.table_view),
                                          label: const Text(
                                            'Toplu İşlemler / Excel',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (gorunen.isEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _satirlar.isEmpty
                                          ? 'Bu sınıfta öğrenci yok.'
                                          : 'Arama sonucu yok.',
                                    ),
                                  ),
                                ),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                sliver: SliverList.builder(
                                  itemCount: gorunen.length,
                                  itemBuilder: (_, i) => _ogrenci(gorunen[i]),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
