import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../widgets/ogrenci_foto_widget.dart';
import 'package:flutter/material.dart';
import '../widgets/ana_sayfa_gorunumu.dart';
import '../services/bireysel_rehberlik_service.dart';
import 'bireysel_bilgi_toplama_screen.dart';
import 'rehberlik_tanima_form_screen.dart';
import 'rehberlik_kayit_editor.dart';
import 'mesaj_form_screen.dart';
import 'bilgi_toplama_ogretmen_gorus_screen.dart';
import 'mesajlasma_screen.dart';

class BireyselRehberlikDosyasiScreen extends StatefulWidget {
  const BireyselRehberlikDosyasiScreen({
    super.key,
    required this.service,
    required this.baglam,
    required this.atama,
    this.atamaYonetimiAc,
  });
  final BireyselRehberlikService service;
  final BireyselRehberlikBaglami baglam;
  final Map<String, Object?> atama;
  final Future<void> Function()? atamaYonetimiAc;
  @override
  State<BireyselRehberlikDosyasiScreen> createState() => _DosyaState();
}

class _DosyaState extends State<BireyselRehberlikDosyasiScreen>
    with WidgetsBindingObserver {
  static const _bolumler = ['Öğrencilerim', 'Toplantılar'];
  List<Map<String, Object?>> _kayitlar = [], _ogrenciler = [];
  String? _hata;
  int _bolum = -1, _istek = 0;
  final _gorunum = OrtakGorunumTercihi.instance;
  bool _islem = false, _hassas = false;
  bool _detayAcik = false;
  bool _fotografliOgrenciler = false, _ogrenciAramaAcik = false;
  final _ogrenciArama = TextEditingController();
  int get _id => widget.atama['RehberlikAtamaId'] as int;
  String get _sinif => widget.atama['SinifKodu'] as String;
  bool get _saltOkunur {
    final bugun = DateTime.now().toIso8601String().substring(0, 10);
    return widget.atama['EgitimOgretimYili'] !=
            widget.baglam.egitimOgretimYili ||
        (widget.atama['BaslangicTarihi'] as String).compareTo(bugun) > 0 ||
        (widget.atama['BitisTarihi'] != null &&
            (widget.atama['BitisTarihi'] as String).compareTo(bugun) < 0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gorunum.addListener(_gorunumYenile);
    _gorunum.yukle();
    _yukle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gorunum.removeListener(_gorunumYenile);
    _ogrenciArama.dispose();
    super.dispose();
  }

  List<Map<String, Object?>> get _gorunenOgrenciler {
    final q = _ogrenciArama.text.trim().toLowerCase();
    return _ogrenciler
        .where(
          (o) => '${o['OkulNo']} ${o['Ad']} ${o['Soyad']}'
              .toLowerCase()
              .contains(q),
        )
        .toList();
  }

  void _ogrenciFormuAc(Map<String, Object?> o) => _ac(
    RehberlikTanimaFormScreen(
      service: widget.service,
      baglam: widget.baglam,
      atamaId: _id,
      ogrenci: o,
      saltOkunur: _saltOkunur || o['OgrenciAktif'] != 1 || o['KayitAktif'] != 1,
    ),
  );

  Widget _ogrenciKarti(Map<String, Object?> o) => Card(
    key: ValueKey('rehberlik-ogrenci-${o['OgrenciId']}'),
    child: InkWell(
      borderRadius: BorderRadius.circular(OrtakUi.radius),
      onTap: _islem ? null : () => _ogrenciFormuAc(o),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (_fotografliOgrenciler) ...[
              OgrenciFotoWidget(
                fotoYolu: o['DosyaYolu'] as String?,
                fotoVerisi: o['FotoVerisi'] as Uint8List?,
                yerel: true,
                width: 64,
                height: 76,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${o['Ad']} ${o['Soyad']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No: ${o['OkulNo']} • $_sinif',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (o['OgrenciAktif'] != 1 || o['KayitAktif'] != 1)
                    const Text('Geçmiş kayıt • Salt okunur'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Öğrenci tanıma formunu aç',
              child: Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _ogrenciAltCubuk() {
    Widget action(String label, IconData icon, VoidCallback f) => Expanded(
      child: TextButton(
        onPressed: _islem ? null : f,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
    return Row(
      key: const ValueKey('rehberlik-ogrenci-alt-cubuk'),
      children: [
        action(
          'Ara',
          Icons.search,
          () => setState(() => _ogrenciAramaAcik = !_ogrenciAramaAcik),
        ),
        Expanded(
          child: PopupMenuButton<bool>(
            tooltip: 'Liste görünümü',
            enabled: !_islem,
            onSelected: (v) => setState(() => _fotografliOgrenciler = v),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: false,
                checked: !_fotografliOgrenciler,
                child: const Text('Düz liste'),
              ),
              CheckedPopupMenuItem(
                value: true,
                checked: _fotografliOgrenciler,
                child: const Text('Fotoğraflı liste'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.view_agenda_outlined, size: 22),
                  SizedBox(height: 4),
                  Text('Görünüm', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
        action('Yenile', Icons.refresh, _yukle),
        action(
          'Gizlilik',
          _hassas ? Icons.lock_open_outlined : Icons.lock_outline,
          _hassasAc,
        ),
      ],
    );
  }

  void _gorunumYenile() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _yukle();
    } else if (state != AppLifecycleState.inactive) {
      if (_detayAcik) {
        Navigator.of(context).pop();
        _detayAcik = false;
      }
      _istek++;
      setState(() {
        _hassas = false;
        _kayitlar = [];
        _ogrenciler = [];
      });
    }
  }

  Future<void> _yukle() async {
    final istek = ++_istek;
    setState(() {
      _islem = true;
      _hata = null;
    });
    try {
      final k = await widget.service.kayitlar(
        widget.baglam,
        _id,
        hassasOnay: _hassas,
      );
      final o = await widget.service.sinifOgrencileri(widget.baglam, _id);
      if (mounted && istek == _istek) {
        setState(() {
          _kayitlar = k;
          _ogrenciler = o;
        });
      }
    } catch (e) {
      if (mounted && istek == _istek) {
        setState(() {
          _hata = 'Rehberlik dosyası okunamadı.\nOrijinal hata: $e';
          _kayitlar = [];
          _ogrenciler = [];
        });
      }
    } finally {
      if (mounted && istek == _istek) setState(() => _islem = false);
    }
  }

  Future<void> _ac(Widget screen) async {
    if (_islem) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) await _yukle();
  }

  Future<void> _hassasAc() async {
    if (_hassas) {
      setState(() => _hassas = false);
      await _yukle();
      return;
    }
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hassas kayıtlara erişim'),
        content: const Text(
          'Hassas öğrenci ve aile bilgileri yalnız bu oturumda açılır. Uygulama arka plana geçince kapanır. SQLite ve okul yedekleri şifreli değildir; yedekleri güvenli saklayın.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Erişimi aç'),
          ),
        ],
      ),
    );
    if (onay == true && mounted) {
      setState(() => _hassas = true);
      await _yukle();
    }
  }

  Future<void> _duzenle(String tur, {Map<String, Object?>? kayit}) async {
    if (_saltOkunur || _islem) return;
    if ((kayit?['Hassas'] == 1 || tur == 'Gorusme') && !_hassas) {
      await _hassasAc();
      if (!_hassas) return;
    }
    if (!mounted) return;
    await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => RehberlikKayitEditor(
          service: widget.service,
          baglam: widget.baglam,
          atamaId: _id,
          tur: tur,
          ogrenciler: _ogrenciler,
          hassasOnay: _hassas,
        ),
      ),
    );
    if (mounted) await _yukle();
  }

  void _gorusler([Map<String, Object?>? k]) => _ac(
    k != null
        ? BilgiToplamaOgretmenGorusScreen(
            service: widget.service,
            baglam: widget.baglam,
            atamaId: _id,
            toplantiId: k['Id'] as int,
            hassasOnay: _hassas,
            saltOkunur: _saltOkunur,
          )
        : MesajFormScreen(
            kaynakModul: 'SinifRehberligim',
            kaynakKayit: 'atama:$_id${k == null ? '' : ':kayit:${k['Id']}'}',
            egitimOgretimYili: widget.atama['EgitimOgretimYili'] as String,
            saltOkunur: _saltOkunur,
            ogrenciIdleri: _ogrenciler
                .map((o) => o['OgrenciId'] as int)
                .toSet(),
            baslik: k == null
                ? '$_sinif sınıf değerlendirmesi'
                : '${k['Baslik']} için görüş',
          ),
  );
  void _davet(Map<String, Object?> k) {
    final veri = jsonDecode(k['Icerik'] as String) as Map;
    final metin =
        (veri['davet'] ??
                '${k['Baslik']} • ${k['Tarih'] ?? ''} ${veri['saat'] ?? ''} • ${veri['yer'] ?? ''}')
            .toString();
    final tur = veri['toplantiTuru'] ?? 'Veli';
    final ids = _ogrenciler.map((o) => o['OgrenciId'] as int).toSet();
    _ac(
      tur == 'Veli'
          ? MesajlasmaScreen(
              kaynakModul: 'SinifRehberligim',
              kaynakKayit: '${k['Id']}',
              baslangicMetni: metin,
              baslangicOgrenciIdleri: ids,
            )
          : MesajFormScreen(
              kaynakModul: 'SinifRehberligim',
              kaynakKayit: 'atama:$_id:kayit:${k['Id']}:davet',
              ogrenciIdleri: ids,
              baslik: '${k['Baslik']} daveti',
              baslangicSoru: metin,
              aliciTuru: tur == 'SOK' ? 'Ogretmen' : 'Ogrenci',
            ),
    );
  }

  Widget _toplantiKarti(Map<String, Object?> k) {
    final gizli = k['Hassas'] == 1 && !_hassas;
    final yazilabilir = !_islem && !_saltOkunur && !gizli;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '#${k['Id']} • ${k['Baslik']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${k['Tarih'] ?? ''} • ${rehberlikDurumAdlari[rehberlikDurumlari.indexOf(k['Durum'] as String)]}',
            ),
            const SizedBox(height: 16),
            if (gizli)
              const Text('Hassas kayıt için kilit simgesinden erişimi açın.'),
            AnaMenuYerlesimi(
              kompakt: true,
              yatay: true,
              children: [
                AnaMenuKart(
                  key: ValueKey('toplanti-davet-${k['Id']}'),
                  icon: Icons.outgoing_mail,
                  renk: const Color(0xff1675ed),
                  baslik: '1. Davet hazırla',
                  aciklama: 'Katılımcılara toplantı daveti hazırlayın.',
                  onTap: yazilabilir ? () => _davet(k) : null,
                ),
                AnaMenuKart(
                  key: ValueKey('toplanti-duzenle-${k['Id']}'),
                  icon: Icons.edit_note,
                  renk: const Color(0xff12a786),
                  baslik: '2. Düzenle',
                  aciklama: 'Tarih, gündem ve toplantı bilgilerini düzenleyin.',
                  onTap: yazilabilir
                      ? () => _duzenle('Toplanti', kayit: k)
                      : null,
                ),
                AnaMenuKart(
                  key: ValueKey('toplanti-gorus-${k['Id']}'),
                  icon: Icons.forum_outlined,
                  renk: const Color(0xff9357e9),
                  baslik: '3. Görüş topla',
                  aciklama: _saltOkunur
                      ? 'Toplantının geçmiş görüşlerini inceleyin.'
                      : 'Ders öğretmenlerinden fotoğraflı form ile görüş alın.',
                  onTap: !_islem && !gizli ? () => _gorusler(k) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _kayitlar
        .where((k) => _bolum == 1 && k['Tur'] == 'Toplanti')
        .toList();
    return PopScope(
      canPop: _bolum == -1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _bolum != -1) setState(() => _bolum = -1);
      },
      child: OrtakSayfa(
        appBar: ModulUstBar(
          title: Text('$_sinif • Rehberlik dosyam'),
          leading: _bolum == -1
              ? null
              : IconButton(
                  tooltip: 'Bölümlere dön',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _bolum = -1),
                ),
          actions: _bolum == 0
              ? []
              : [
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: _islem ? null : _yukle,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Hassas erişim',
                    onPressed: _islem ? null : _hassasAc,
                    icon: Icon(_hassas ? Icons.lock_open : Icons.lock),
                  ),
                ],
        ),
        bottomNavigationBar: _bolum == 0 ? _ogrenciAltCubuk() : null,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${widget.atama['EgitimOgretimYili']} • ${widget.baglam.ogretmenAdi}',
            ),
            if (_saltOkunur)
              const Text('Geçmiş / henüz başlamamış atama: salt okunur.'),
            if (_hata != null) Text(_hata!),
            if (_bolum == -1)
              AnaMenuYerlesimi(
                kompakt: _gorunum.kompakt,
                children: [
                  if (widget.atamaYonetimiAc != null)
                    AnaMenuKart(
                      icon: Icons.manage_accounts_outlined,
                      baslik: 'Rehberlik atamam',
                      onTap: () async {
                        if (_islem) return;
                        await widget.atamaYonetimiAc!();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  for (final i in const [0, 1])
                    AnaMenuKart(
                      icon: const [
                        Icons.people_outline,
                        Icons.event_note_outlined,
                      ][i],
                      baslik: _bolumler[i],
                      onTap: () {
                        if (!_islem) setState(() => _bolum = i);
                      },
                    ),
                  if (!_saltOkunur)
                    AnaMenuKart(
                      icon: Icons.assignment_outlined,
                      baslik: 'Öğrenci Tanıma Formu',
                      onTap: () {
                        if (_islem) return;
                        _ac(
                          RehberlikBilgiFormScreen(
                            service: widget.service,
                            baglam: widget.baglam,
                            atamaId: _id,
                            sinifId: widget.atama['SinifSubeId'] as int,
                          ),
                        );
                      },
                    ),
                ],
              )
            else
              Text(
                _bolumler[_bolum],
                style: Theme.of(context).textTheme.titleLarge,
              ),
            const SizedBox(height: 12),
            if (_bolum == 0) ...[
              const SizedBox(height: 4),
              Text(
                '${_gorunenOgrenciler.length} öğrenci • ${_fotografliOgrenciler ? 'Fotoğraflı görünüm' : 'Düz liste'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_ogrenciAramaAcik)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: TextField(
                    controller: _ogrenciArama,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Öğrenci adı veya okul numarası',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              for (final o in _gorunenOgrenciler) _ogrenciKarti(o),
              if (_gorunenOgrenciler.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Öğrenci bulunamadı.'),
                ),
            ],
            if (_bolum == 1 && !_saltOkunur)
              FilledButton(
                onPressed: _islem ? null : () => _duzenle('Toplanti'),
                child: const Text('Toplantı oluştur'),
              ),
            if (_bolum == 1 && rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Bu bölümde kayıt bulunmuyor.'),
              ),
            for (final k in rows) _toplantiKarti(k),
          ],
        ),
      ),
    );
  }
}
