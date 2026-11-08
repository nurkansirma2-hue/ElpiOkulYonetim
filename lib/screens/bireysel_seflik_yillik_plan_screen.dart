import 'package:flutter/material.dart';
import '../services/bireysel_profil_service.dart';
import '../services/bireysel_seflik_yillik_plan_service.dart';
import 'bireysel_seflik_aylik_form_screen.dart';
import 'bireysel_ders_programim_screen.dart';
import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import '../services/bireysel_seflik_haftalik_sablon_service.dart';
import '../services/bireysel_seflik_excel_import_service.dart';

class BireyselSeflikYillikPlanScreen extends StatefulWidget {
  const BireyselSeflikYillikPlanScreen({super.key});
  @override
  State<BireyselSeflikYillikPlanScreen> createState() =>
      _BireyselSeflikYillikPlanScreenState();
}

class _BireyselSeflikYillikPlanScreenState
    extends State<BireyselSeflikYillikPlanScreen> {
  int? _profilId;
  String _yil = '';
  String _ogretmenAdi = '';
  String _okulAdi = '';
  DateTime? _ilkGun;
  DateTime? _sonGun;
  List<SeflikYillikFaaliyet> _satirlar = [];
  List<String> _uyarilar = [];
  List<String> _bilgiler = [];
  bool _onayli = false;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _hazirla();
  }

  Future<void> _hazirla() async {
    try {
      final profil = await BireyselProfilService.getir();
      final id = profil?['OgretmenProfilId'] as int?;
      final yil = (profil?['EgitimOgretimYili'] ?? '').toString().trim();
      final yillar = RegExp(r'^(\d{4})\D+(\d{4})$').firstMatch(yil);
      if (id == null || id <= 0 || yillar == null ||
          int.parse(yillar.group(2)!) != int.parse(yillar.group(1)!) + 1) {
        throw StateError('Öğretmen profili veya eğitim yılı geçersiz.');
      }
      final kayitlar = await BireyselSeflikYillikPlanService.onayliPlaniGetir(
        ogretmenProfilId: id, egitimOgretimYili: yil);
      if (!mounted) return;
      setState(() {
        _profilId = id;
        _yil = yil;
        _ogretmenAdi = (profil?['AdSoyad'] ?? '').toString().trim();
        _okulAdi = (profil?['OkulAdi'] ?? '').toString().trim();
        _ilkGun = DateTime(int.parse(yillar.group(1)!), 9, 1);
        _sonGun = DateTime(int.parse(yillar.group(2)!), 6, 30);
        _satirlar = kayitlar;
        _onayli = kayitlar.isNotEmpty;
        _yukleniyor = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _yukleniyor = false);
      _mesaj('Şeflik planı açılamadı. Orijinal hata: $e');
    }
  }

  void _mesaj(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj)));
  }

  Future<void> _taslakUret() async {
    if (_profilId == null || _ilkGun == null || _sonGun == null) return;
    setState(() => _yukleniyor = true);
    try {
      final plan = await BireyselSeflikYillikPlanService.taslakOlustur(
        ogretmenProfilId: _profilId!, egitimOgretimYili: _yil,
        ilkGun: _ilkGun!, sonGun: _sonGun!);
      if (!mounted) return;
      setState(() {
        _satirlar = List.of(plan.faaliyetler);
        _uyarilar = plan.uyarilar;
        _bilgiler = [];
      });
    } catch (e) {
      if (mounted) _mesaj('Taslak oluşturulamadı. Orijinal hata: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _exceldenAl() async {
    if (_profilId == null || _onayli || _yukleniyor) return;
    setState(() => _yukleniyor = true);
    try {
      final bytes = await BireyselSeflikExcelImportService.dosyaSec();
      if (bytes == null) return;
      final sonuc = await BireyselSeflikExcelImportService.onIzleme(
        bytes: bytes,
        ogretmenAdi: _ogretmenAdi,
        ogretmenProfilId: _profilId!,
        egitimOgretimYili: _yil,
      );
      if (!mounted) return;
      setState(() {
        _satirlar = List.of(sonuc.taslak.faaliyetler);
        _uyarilar = List.of(sonuc.taslak.uyarilar);
        _bilgiler = List.of(sonuc.bilgiler);
      });
      _mesaj('${sonuc.sayfaAdi}: ${sonuc.haftaSayisi} hafta okundu. '
          'Kaydetmeden önce önizlemeyi kontrol edin.');
    } catch (e) {
      if (mounted) _mesaj('Şeflik Excel içe aktarılamadı. Orijinal hata: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _duzenle(int index) async {
    final faaliyet = _satirlar[index];
    final kontrol = TextEditingController(text: faaliyet.faaliyet);
    final yeni = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Faaliyeti düzenle'),
        content: TextField(controller: kontrol, maxLines: 4,
          maxLength: 300, autofocus: true,
          decoration: const InputDecoration(labelText: 'Yapılacak çalışma')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, kontrol.text.trim()),
            child: const Text('Uygula')),
        ],
      ),
    );
    kontrol.dispose();
    if (yeni == null || !mounted) return;
    if (yeni.isEmpty) {
      _mesaj('Faaliyet açıklaması boş olamaz.');
      return;
    }
    setState(() => _satirlar[index] = SeflikYillikFaaliyet(
      tarih: faaliyet.tarih, gun: faaliyet.gun,
      dersSaatiNo: faaliyet.dersSaatiNo, baslangic: faaliyet.baslangic,
      bitis: faaliyet.bitis, faaliyet: yeni));
  }

  Future<void> _kaydet() async {
    if (_profilId == null || _satirlar.isEmpty || _uyarilar.isNotEmpty) return;
    final onay = await showDialog<bool>(context: context, builder: (c) =>
      AlertDialog(
        title: const Text('Yıllık planı onayla'),
        content: Text('${_satirlar.length} faaliyet kaydedilecek. '
          'Onaylı planın üzerine otomatik yazılmayacaktır. Devam edilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Onayla ve kaydet')),
        ],
      ));
    if (onay != true || !mounted) return;
    setState(() => _yukleniyor = true);
    try {
      await BireyselSeflikYillikPlanService.onaylaVeKaydet(
        ogretmenProfilId: _profilId!,
        taslak: SeflikYillikPlanTaslagi(
          egitimOgretimYili: _yil,
          faaliyetler: _satirlar, uyarilar: _uyarilar));
      if (!mounted) return;
      setState(() => _onayli = true);
      _mesaj('Yıllık şeflik planı kaydedildi.');
    } catch (e) {
      if (mounted) _mesaj('Plan kaydedilemedi. Orijinal hata: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _tarihSec(bool ilk) async {
    final mevcut = (ilk ? _ilkGun : _sonGun);
    if (mevcut == null) return;
    final tarih = await showDatePicker(context: context,
      initialDate: mevcut,
      firstDate: DateTime(mevcut.year - 1),
      lastDate: DateTime(mevcut.year + 1, 12, 31));
    if (tarih == null || !mounted) return;
    setState(() {
      if (ilk) { _ilkGun = tarih; } else { _sonGun = tarih; }
      _satirlar = [];
      _uyarilar = [];
      _bilgiler = [];
    });
  }

  Future<void> _haftalikSablonIndir() async {
    try {
      final yol = await BireyselSeflikHaftalikSablonService.indir(
        yil: _yil, ogretmen: _ogretmenAdi);
      if (mounted && yol != null) {
        _mesaj('Haftalık şeflik saati şablonu oluşturuldu.');
      }
    } catch (e) {
      if (mounted) _mesaj('Şablon oluşturulamadı. Orijinal hata: $e');
    }
  }

  Future<void> _aylikRaporOlustur() async {
    if (_satirlar.isEmpty) return;
    final aylar = <DateTime>[
      for (var ay = 9; ay <= 12; ay++) DateTime(int.parse(_yil.substring(0, 4)), ay),
      for (var ay = 1; ay <= 6; ay++) DateTime(int.parse(_yil.substring(0, 4)) + 1, ay),
    ];
    const adlar = ['', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
    final secili = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Aylık rapor için ay seçin')),
          for (final ay in aylar)
            ListTile(
              title: Text('${adlar[ay.month]} ${ay.year}'),
              subtitle: Text('${_satirlar.where((f) =>
                f.tarih.year == ay.year && f.tarih.month == ay.month).length} faaliyet'),
              onTap: () => Navigator.pop(c, ay),
            ),
        ],
      )),
    );
    if (secili == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BireyselSeflikAylikFormScreen(
        egitimOgretimYili: _yil,
        faaliyetler: List.unmodifiable(_satirlar),
        ogretmenAdi: _ogretmenAdi,
        okulAdi: _okulAdi,
        ilkAy: secili,
        taslak: !_onayli,
      ),
    ));
  }

  bool get _seflikSaatiYok => !_onayli && _satirlar.isEmpty &&
      _uyarilar.any((u) => u.contains('şeflik saati bulunamadı'));

  Future<void> _dersPrograminaGit() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const BireyselDersProgramimScreen(seflikRehberi: true)));
    if (mounted) {
      await _taslakUret();
    }
  }

  Widget _isAkisiKarti(BuildContext context) {
    final renkler = Theme.of(context).colorScheme;
    const basliklar = [
      'Yıllık Plan',
      'Excel İçe Aktar',
      'Haftalık Program',
      'Aylık Form',
    ];
    const simgeler = [
      Icons.calendar_month_outlined,
      Icons.table_chart_outlined,
      Icons.view_week_outlined,
      Icons.description_outlined,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          width: double.infinity,
          color: renkler.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: const Row(children: [
            Icon(Icons.fact_check_outlined, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text('Atölye Şefliği İş Akışı',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 2),
          child: Text(
            'Yıllık planı oluşturun, Excel’den içe aktarın, haftalık şeflik '
            'programıyla ilişkilendirin ve aylık çalışma formunu hazırlayın.',
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            for (var i = 0; i < basliklar.length; i++)
              Expanded(child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  switch (i) {
                    case 0:
                      if (_onayli) {
                        _mesaj('Yıllık plan onaylı ve salt okunur.');
                      } else {
                        _taslakUret();
                      }
                    case 1:
                      if (_onayli) {
                        _mesaj('Onaylı yıllık plan değiştirilemez.');
                      } else {
                        _exceldenAl();
                      }
                    case 2:
                      _dersPrograminaGit();
                    case 3:
                      _aylikRaporOlustur();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: renkler.primaryContainer,
                      child: Icon(simgeler[i], size: 19, color: renkler.primary),
                    ),
                    const SizedBox(height: 5),
                    Text(basliklar[i], textAlign: TextAlign.center,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
              )),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => OrtakSayfa(
    appBar: ModulUstBar(title: const Text('Yıllık Şeflik Planı')),
    body: _yukleniyor
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
            Expanded(child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                _isAkisiKarti(context),
                Card(child: Padding(padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('ATÖLYE ŞEFLİĞİ',
                        style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 5),
                      Text('Yıllık Çalışma Planı',
                        style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text('$_yil eğitim öğretim yılı',
                        style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 6),
                      Text('$_ogretmenAdi',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]))),
                const SizedBox(height: 12),
                if (!_onayli) Card(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Plan hazırlama',
                        style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      const Text('Ders programındaki şeflik saatlerini kullanın '
                        'veya hazır Excel planını içe aktarın.'),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(onPressed: () => _tarihSec(true),
                          icon: const Icon(Icons.event_outlined),
                          label: Text('Başlangıç: ${_ilkGun?.day}.${_ilkGun?.month}.${_ilkGun?.year}')),
                        OutlinedButton.icon(onPressed: () => _tarihSec(false),
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text('Bitiş: ${_sonGun?.day}.${_sonGun?.month}.${_sonGun?.year}')),
                      ]),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _taslakUret,
                        icon: const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Ders programından oluştur')),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(onPressed: _exceldenAl,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Excel’den içe aktar')),
                    ]))),
                if (_onayli) Card(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(children: [
                        Icon(Icons.verified_outlined), SizedBox(width: 8),
                        Expanded(child: Text('Onaylı yıllık plan — salt okunur')),
                      ]),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) =>
                            BireyselSeflikAylikFormScreen(
                              egitimOgretimYili: _yil,
                              faaliyetler: List.unmodifiable(_satirlar),
                              ogretmenAdi: _ogretmenAdi,
                              okulAdi: _okulAdi))),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Aylık çalışma formları')),
                    ]))),
                if (_seflikSaatiYok) Card(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Şeflik saati henüz belirlenmemiş',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                      ]),
                      const SizedBox(height: 8),
                      const Text('Yıllık planın oluşması için önce haftalık '
                        'ders programınızda boş saatlere şeflik görevi atayın.'),
                      const SizedBox(height: 8),
                      const Text('1. Ders Programım ekranına gidin.\n'
                        '2. Boş bir hücreye uzun basın (bilgisayarda sağ tıklayın).\n'
                        '3. “Şeflik olarak ata” seçimini onaylayın.\n'
                        '4. Şeflik saatlerini belirleyip bu ekrana dönün.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _dersPrograminaGit,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Ders Programım’a git')),
                    ]))),
                if (_bilgiler.isNotEmpty)
                  Card(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ders programına uyarlanan haftalar',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ..._bilgiler.take(15).map((bilgi) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $bilgi'))),
                      ]))),
                if (_uyarilar.isNotEmpty && !_seflikSaatiYok)
                  Card(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_uyarilar.length} takvim uyarısı — kayıt kapalı',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ..._uyarilar.take(15).map((u) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $u'))),
                      ]))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text('Faaliyet önizlemesi',
                    style: Theme.of(context).textTheme.titleMedium)),
                  Text('${_satirlar.length} faaliyet'),
                ]),
                const SizedBox(height: 8),
                if (_satirlar.isEmpty && !_seflikSaatiYok)
                  const Padding(padding: EdgeInsets.all(20),
                    child: Text('Henüz faaliyet yok. Yukarıdan plan oluşturun '
                      'veya Excel dosyası seçin.')),
                ...List.generate(_satirlar.length, (i) {
                  final f = _satirlar[i];
                  return Card(child: ListTile(
                    title: Text(f.faaliyet),
                    subtitle: Text('${f.tarih.day}.${f.tarih.month}.${f.tarih.year} '
                      '• ${f.gun} • ${f.dersSaatiNo}. saat '
                      '(${f.baslangic}–${f.bitis})'),
                    trailing: _onayli ? null : IconButton(
                      tooltip: 'Düzenle',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _duzenle(i)),
                  ));
                }),
              ],
            )),
            SafeArea(top: false, child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: SizedBox(width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _haftalikSablonIndir,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Boş haftalık şeflik saati şablonu'),
                )))),
            if (_satirlar.isNotEmpty)
              SafeArea(top: false, child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: SizedBox(width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _aylikRaporOlustur,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Aylık rapor oluştur'),
                  )))),
            if (!_onayli && _satirlar.isNotEmpty)
              SafeArea(top: false, child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SizedBox(width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _uyarilar.isEmpty ? _kaydet : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Önizlemeyi onayla ve kaydet'))))),
          ]),
  );
}
