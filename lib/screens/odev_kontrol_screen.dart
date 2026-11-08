import '../widgets/ortak_ui.dart';
import 'package:flutter/material.dart';

import '../models/odev_kontrol.dart';
import '../services/bireysel_liste_service.dart';
import '../services/bireysel_odev_kontrol_service.dart';
import 'bireysel_ders_programim_screen.dart';
import 'odev_kontrol_detay_screen.dart';
import 'odev_tanim_screen.dart';
import 'performans_not_screen.dart';
import '../widgets/odev_gorunum.dart';

class OdevKontrolScreen extends StatefulWidget {
  const OdevKontrolScreen({super.key});

  @override
  State<OdevKontrolScreen> createState() => _OdevKontrolScreenState();
}

class _OdevKontrolScreenState extends State<OdevKontrolScreen> {
  BireyselListeOturumu? _oturum;
  List<OdevTanim> _gorevler = [];
  List<OdevDersSecenegi> _dersler = [];
  int _sinifId = 0, _dersId = 0;
  String? _turFiltresi;
  bool _bekle = true, _pasifler = false;
  final _secili = <int>{};
  bool _topluIslem = false;
  bool get _kilitli => _excelIslem || _topluIslem;
  String? _hata;
  bool _excelIslem = false;
  int _durumFiltresi = 0;
  bool _filtreleriGoster = false;
  bool _aramaAcik = false;
  String _arama = "";
  int _siralama = 0;
  Map<int, Map<String, int>> _ozet = {};
  Map<int, int> _ekSayilari = {};

  Future<void> _excelAktar() async {
    if (_kilitli || _bekle || _oturum == null) return;
    setState(() => _excelIslem = true);
    try {
      final yol = await BireyselOdevKontrolService.gorevListesiExcelAktar(
        _oturum!,
        sinifSubeId: _sinifId == 0 ? null : _sinifId,
        dersId: _dersId == 0 ? null : _dersId,
        pasifleriDahilEt: _pasifler,
      );
      if (mounted && yol != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel kaydedildi: $yol')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ödev listesi aktarılamadı.\nOrijinal hata: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _excelIslem = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle({bool yenidenHazirla = false}) async {
    setState(() {
      _bekle = true;
      _hata = null;
    });
    try {
      final oturum = yenidenHazirla || _oturum == null
          ? await BireyselOdevKontrolService.hazirla()
          : _oturum!;
      var sinifId = _sinifId;
      if (sinifId != 0 &&
          !oturum.siniflar.any((s) => s.sinifSubeId == sinifId)) {
        sinifId = 0;
      }
      final dersler = await BireyselOdevKontrolService.dersler(
        oturum,
        sinifId == 0 ? null : sinifId,
      );
      final dersId = dersler.any((d) => d.dersId == _dersId) ? _dersId : 0;
      final ozet = await BireyselOdevKontrolService.listeOzeti(oturum);
      final gorevler = await BireyselOdevKontrolService.gorevler(
        oturum,
        sinifSubeId: sinifId == 0 ? null : sinifId,
        dersId: dersId == 0 ? null : dersId,
        pasifleriDahilEt: _pasifler,
      );
      final ekSayilari = <int, int>{};
      for (final gorev in gorevler) {
        final ekler = await OdevDosyaService.liste(oturum, gorev.odevId);
        ekSayilari[gorev.odevId] = ekler
            .where((e) => e['OdevKontrolSonucId'] == null)
            .length;
      }
      if (!mounted) return;
      setState(() {
        _ekSayilari = ekSayilari;
        _oturum = oturum;
        _sinifId = sinifId;
        _dersId = dersId;
        _dersler = dersler;
        _gorevler = gorevler;
        _ozet = ozet;
        _secili.removeWhere((id) => !gorevler.any((g) => g.odevId == id));
      });
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'Ödev listesi yüklenemedi.\nOrijinal hata: $e');
      }
    } finally {
      if (mounted) setState(() => _bekle = false);
    }
  }

  Future<void> _detay(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OdevKontrolDetayScreen(oturum: _oturum!, odevId: id),
      ),
    );
    if (mounted) await _yukle();
  }

  Future<void> _yeni() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => OdevTanimScreen(
          oturum: _oturum!,
          sinifSubeId: _sinifId == 0 ? null : _sinifId,
          dersId: _dersId == 0 ? null : _dersId,
        ),
      ),
    );
    if (!mounted) return;
    if (id != null) {
      await _detay(id);
    } else {
      await _yukle();
    }
  }

  Future<void> _secimiUygula({required bool birlestir}) async {
    if (_kilitli || _bekle || _secili.isEmpty) return;
    final idler = Set<int>.of(_secili);
    final gorevler = _gorevler.where((g) => idler.contains(g.odevId)).toList();
    var mesajlariSil = false;
    setState(() => _topluIslem = true);
    try {
      final onay = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, yenile) => AlertDialog(
            scrollable: true,
            title: Text(
              birlestir ? 'Defter ödevlerini birleştir' : 'Seçili ödevleri sil',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${gorevler.map((g) => '• ${g.baslik}').join('\n')}\n\n'
                  '${birlestir ? 'Aynı sınıf, ders, tür, dönem ve durumdaki görevler Defter Kontrol adıyla birleşir. Kontroller ve sonuçlar korunur.' : 'Bu ödevler, öğrenci katılımları, kontrolleri ve puanları kalıcı olarak silinecek. Öğrenci kayıtları korunur.'}',
                ),
                if (!birlestir) ...[
                  const SizedBox(height: 16),
                  const Text('Ödevle ilgili bildirim mesajları ne olsun?'),
                  RadioGroup<bool>(
                    groupValue: mesajlariSil,
                    onChanged: (v) => yenile(() => mesajlariSil = v ?? false),
                    child: const Column(
                      children: [
                        RadioListTile<bool>(
                          value: false,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Arşive kaldır'),
                          subtitle: Text(
                            'Geçmişte sakla, bekleyen gönderimleri durdur.',
                          ),
                        ),
                        RadioListTile<bool>(
                          value: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Mesaj kayıtlarını sil'),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Bu seçim uygulamadaki kayıtlar içindir. Gönderilmiş SMS ve WhatsApp mesajları geri alınmaz.',
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(birlestir ? 'Birleştir' : 'Sil'),
              ),
            ],
          ),
        ),
      );
      if (onay != true || !mounted) return;
      if (birlestir) {
        await BireyselOdevKontrolService.defterGorevleriniBirlestir(
          _oturum!,
          idler,
        );
      } else {
        await BireyselOdevKontrolService.gorevleriSil(
          _oturum!,
          idler,
          mesajlariSil: mesajlariSil,
        );
      }
      if (!mounted) return;
      _secili.clear();
      await _yukle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              birlestir
                  ? 'Defter ödevleri birleştirildi.'
                  : 'Seçili ödevler silindi.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem tamamlanamadı. Orijinal hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _topluIslem = false);
    }
  }

  List<OdevTanim> get _temelListe => _gorevler
      .where(
        (g) =>
            (_turFiltresi == null || (_turFiltresi == 'DersUygulamalari'
              ? g.dersUygulamalari : !g.dersUygulamalari && g.gorevTuru.kayitDegeri == _turFiltresi)) &&
            ('${g.baslik} ${_sinifAdi(g)} ${g.dersUygulamalari ? 'Ders Uygulamaları' : g.gorevTuru.baslik}'
                .toLowerCase()
                .contains(_arama.toLowerCase().trim())),
      )
      .toList();

  String _sinifAdi(OdevTanim g) =>
      {
        for (final x in _oturum!.siniflar) x.sinifSubeId: x.sinif,
      }[g.sinifSubeId] ??
      '';

  List<OdevTanim> get _gorunenler {
    final liste = _temelListe
        .where(
          (g) => _durumFiltresi == 0 || g.tamamlandi == (_durumFiltresi == 2),
        )
        .toList();
    if (_siralama == 1) {
      liste.sort(
        (a, b) => a.baslik.toLowerCase().compareTo(b.baslik.toLowerCase()),
      );
    }
    if (_siralama == 2) {
      liste.sort((a, b) {
        if (a.teslimTarihi == null) {
          return b.teslimTarihi == null ? a.odevId.compareTo(b.odevId) : 1;
        }
        if (b.teslimTarihi == null) return -1;
        final k = a.teslimTarihi!.compareTo(b.teslimTarihi!);
        return k == 0 ? a.odevId.compareTo(b.odevId) : k;
      });
    }
    return liste;
  }

  Widget _secimCubugu() => Wrap(
    alignment: WrapAlignment.end,
    children: [
      IconButton(
        tooltip: 'Seçimi temizle',
        onPressed: _kilitli ? null : () => setState(_secili.clear),
        icon: const Icon(Icons.close),
      ),
      if (_secili.length > 1 &&
          _gorevler
              .where((g) => _secili.contains(g.odevId))
              .every((g) => g.baslik.toLowerCase().contains('defter')))
        IconButton(
          tooltip: 'Defter ödevlerini birleştir',
          onPressed: _kilitli ? null : () => _secimiUygula(birlestir: true),
          icon: const Icon(Icons.merge),
        ),
      IconButton(
        tooltip: 'Seçili ödevleri sil',
        onPressed: _kilitli ? null : () => _secimiUygula(birlestir: false),
        icon: const Icon(Icons.delete_outline),
      ),
    ],
  );

  Widget _altCubuk() {
    final hazir = !_bekle && !_kilitli && _hata == null && _oturum != null;
    Widget dugme(IconData ikon, String ad, String ipucu, VoidCallback? tikla) =>
        Expanded(
          child: Tooltip(
            message: ipucu,
            child: TextButton(
              onPressed: tikla,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ikon, size: 21),
                  const SizedBox(height: 4),
                  Text(
                    ad,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d125f9c),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_secili.isNotEmpty) _secimCubugu(),
            Row(
              children: [
                dugme(
                  Icons.search,
                  'Ara',
                  'Ödev ara',
                  hazir
                      ? () => setState(() {
                          _aramaAcik = !_aramaAcik;
                          if (!_aramaAcik) _arama = '';
                        })
                      : null,
                ),
                dugme(
                  Icons.filter_alt_outlined,
                  'Filtrele',
                  'Filtreler',
                  hazir
                      ? () => setState(
                          () => _filtreleriGoster = !_filtreleriGoster,
                        )
                      : null,
                ),
                Expanded(
                  child: PopupMenuButton<int>(
                    tooltip: 'Sırala',
                    enabled: hazir,
                    initialValue: _siralama,
                    onSelected: (v) => setState(() => _siralama = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 0, child: Text('Varsayılan sıra')),
                      PopupMenuItem(value: 1, child: Text('Ödev adı (A–Z)')),
                      PopupMenuItem(value: 2, child: Text('Son teslim tarihi')),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_vert, color: odevMavi, size: 21),
                          SizedBox(height: 4),
                          Text(
                            'Sırala',
                            style: TextStyle(fontSize: 10, color: odevMavi),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                dugme(
                  Icons.add_circle_outline,
                  'Yeni Ödev',
                  'Yeni ödev oluştur',
                  hazir ? _yeni : null,
                ),
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: 'Ödev işlemleri',
                    enabled: !_bekle && !_kilitli,
                    onSelected: (v) async {
                      if (v == 'excel') {
                        await _excelAktar();
                      } else if (v == 'not') {
                        if (!mounted || _oturum == null) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PerformansNotScreen(oturum: _oturum!),
                          ),
                        );
                      } else {
                        await _yukle(yenidenHazirla: true);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'not',
                        enabled: hazir,
                        child: const Text('Not Hesaplama'),
                      ),
                      PopupMenuItem(
                        value: 'excel',
                        enabled: hazir,
                        child: const Text('Excel’e aktar'),
                      ),
                      const PopupMenuItem(
                        value: 'yenile',
                        child: Text('Yenile'),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.more_vert, color: odevMavi, size: 21),
                          SizedBox(height: 4),
                          Text(
                            'Diğer',
                            style: TextStyle(fontSize: 10, color: odevMavi),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _gorevKarti(OdevTanim g) {
    final (ikon, renk) = switch (g.gorevTuru) {
      OdevGorevTuru.normalOdev => (
        Icons.description_outlined,
        const Color(0xff087cff),
      ),
      OdevGorevTuru.rutinKontrol => (
        Icons.event_repeat,
        const Color(0xffff9c00),
      ),
      OdevGorevTuru.proje => (
        Icons.assignment_outlined,
        const Color(0xff00b880),
      ),
      OdevGorevTuru.performans => (
        Icons.fact_check_outlined,
        const Color(0xff8b36ec),
      ),
    };
    final girilen = _ozet[g.odevId]?['girilen'] ?? 0;
    final toplam = _ozet[g.odevId]?['toplam'] ?? 0;
    final durum = g.tamamlandi
        ? 'Tamamlandı'
        : girilen == 0
        ? 'Taslak'
        : 'Devam Ediyor';
    final durumRenk = g.tamamlandi
        ? const Color(0xff168450)
        : girilen == 0
        ? const Color(0xff69798e)
        : const Color(0xffa76a00);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: odevCizgi),
      ),
      child: InkWell(
        onTap: _kilitli ? null : () => _detay(g.odevId),
        onLongPress: _kilitli
            ? null
            : () => setState(() {
                if (!_secili.add(g.odevId)) _secili.remove(g.odevId);
              }),
        child: Container(
          color: _secili.contains(g.odevId)
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          padding: const EdgeInsets.fromLTRB(8, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                key: ValueKey('odev-sec-${g.odevId}'),
                tooltip: 'Ödev seç',
                onPressed: _kilitli
                    ? null
                    : () => setState(() {
                        if (!_secili.add(g.odevId)) _secili.remove(g.odevId);
                      }),
                style: IconButton.styleFrom(
                  backgroundColor: renk.withValues(alpha: .10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                icon: Icon(
                  _secili.isEmpty
                      ? ikon
                      : _secili.contains(g.odevId)
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: renk,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.baslik,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_sinifAdi(g)} • ${g.dersUygulamalari ? 'Ders Uygulamaları' : g.gorevTuru.baslik}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff6c7c93),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _bilgi(
                          Icons.calendar_month_outlined,
                          g.teslimTarihi == null
                              ? 'Tarih yok'
                              : odevTarihYaz(g.teslimTarihi!),
                        ),
                        _bilgi(
                          Icons.fact_check_outlined,
                          '$girilen/$toplam ${g.dersUygulamalari ? 'uygulama sonucu' : 'kontrol'}',
                        ),
                        _bilgi(
                          Icons.attach_file,
                          '${_ekSayilari[g.odevId] ?? 0} dosya',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: durumRenk.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        durum,
                        style: TextStyle(
                          color: durumRenk,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right, size: 20, color: odevMavi),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bilgi(IconData ikon, String metin) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(ikon, size: 13, color: const Color(0xff7389ad)),
      const SizedBox(width: 4),
      Text(
        metin,
        style: const TextStyle(fontSize: 10, color: Color(0xff65758b)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final oturum = _oturum;
    return OdevTema(
      child: OrtakSayfa(
        appBar: OdevBaslik(
          kompakt: true,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _secili.isEmpty ? 'Ödevlerim' : '${_secili.length} ödev seçili',
              ),
              if (oturum != null && _secili.isEmpty)
                Text(
                  oturum.yil,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _altCubuk(),
        body: SafeArea(
          child: _bekle
              ? const Center(child: CircularProgressIndicator())
              : _hata != null
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(_hata!),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _yukle(yenidenHazirla: true),
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                )
              : oturum == null
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
                  children: [
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Icon(Icons.assignment_turned_in_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 28),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Ödevlerim',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 3),
                              Text(
                                'Ödevleri tanımlayın, aynı ödev altında tekrarlı kontroller yapın.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          )),
                        ]),
                      ),
                    ),
                    if (_aramaAcik) ...[
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Ödev ara...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Aramayı kapat',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _aramaAcik = false;
                              _arama = "";
                            }),
                          ),
                        ),
                        onChanged: (v) => setState(() => _arama = v),
                      ),
                      const SizedBox(height: 10),
                    ],

                    Row(
                      children: [
                        for (final (id, ad) in [
                          (0, 'Tümü'),
                          (1, 'Bekleyen'),
                          (2, 'Tamamlanan'),
                        ]) ...[
                          if (id > 0) const SizedBox(width: 6),
                          Expanded(
                            child: ChoiceChip(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$ad (${_temelListe.where((g) => id == 0 || g.tamamlandi == (id == 2)).length})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _durumFiltresi == id
                                        ? Colors.white
                                        : const Color(0xff65758b),
                                  ),
                                ),
                              ),
                              selectedColor: odevMavi,
                              selected: _durumFiltresi == id,
                              onSelected: _kilitli
                                  ? null
                                  : (_) => setState(() => _durumFiltresi = id),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (oturum.siniflar.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text(
                                'Yeni görev oluşturmak için ders programınıza sınıf ve ders ekleyin.',
                              ),
                              TextButton(
                                onPressed: _kilitli
                                    ? null
                                    : () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const BireyselDersProgramimScreen(),
                                          ),
                                        );
                                        if (mounted) {
                                          await _yukle(yenidenHazirla: true);
                                        }
                                      },
                                child: const Text('Ders Programım'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_filtreleriGoster) ...[
                      DropdownButtonFormField<int>(
                        key: ValueKey('sinif-$_sinifId'),
                        initialValue: _sinifId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Sınıf / şube',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('Tüm sınıflar'),
                          ),
                          ...oturum.siniflar.map(
                            (s) => DropdownMenuItem(
                              value: s.sinifSubeId,
                              child: Text(s.sinif),
                            ),
                          ),
                        ],
                        onChanged: _kilitli
                            ? null
                            : (id) {
                                if (id == null) return;
                                _secili.clear();
                                _sinifId = id;
                                _dersId = 0;
                                _yukle();
                              },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        key: ValueKey('ders-$_sinifId-$_dersId'),
                        initialValue: _dersId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Ders',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('Tüm dersler'),
                          ),
                          ..._dersler.map(
                            (d) => DropdownMenuItem(
                              value: d.dersId,
                              child: Text(d.dersAdi),
                            ),
                          ),
                        ],
                        onChanged: _dersler.isEmpty || _kilitli
                            ? null
                            : (id) {
                                if (id == null) return;
                                _secili.clear();
                                _dersId = id;
                                _yukle();
                              },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String?>(
                        initialValue: _turFiltresi,
                        decoration: const InputDecoration(
                          labelText: 'Ödev türü',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Tüm ödev türleri'),
                          ),
                          const DropdownMenuItem<String?>(value:'DersUygulamalari', child:Text('Ders Uygulamaları')),
                          ...OdevGorevTuru.values.map(
                            (t) => DropdownMenuItem<String?>(
                              value: t.kayitDegeri,
                              child: Text(
                                t.baslik,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: _kilitli
                            ? null
                            : (t) => setState(() {
                                _secili.clear();
                                _turFiltresi = t;
                              }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pasif görevleri göster'),
                        value: _pasifler,
                        onChanged: _kilitli
                            ? null
                            : (v) {
                                _secili.clear();
                                _pasifler = v;
                                _yukle();
                              },
                      ),
                    ],
                    if (_gorunenler.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          'Bu seçim için görev bulunamadı.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ..._gorunenler.map(_gorevKarti),
                  ],
                ),
        ),
      ),
    );
  }
}
