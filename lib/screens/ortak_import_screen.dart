import '../widgets/ortak_ui.dart';
import '../widgets/modul_ust_bar.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/ortak_import.dart';
import '../models/import_ilerleme.dart';
import '../widgets/import_ilerleme_karti.dart';
import '../services/ortak_import_service.dart';
import 'bireysel_belgelerim_screen.dart';
import '../services/bireysel_belge_service.dart';
import '../services/belge_analiz_service.dart';
import '../services/belge_disari_aktar_service.dart';
import '../services/drive_belge_service.dart';

enum _ImportDosyaKaynagi { cihaz, belgelerim, drive }

class OrtakImportScreen extends StatefulWidget {
  const OrtakImportScreen({
    super.key,
    required this.tanim,
    this.baslangicDosyasi,
    this.secimleDon = false,
    this.kayitGorseli,
    this.belgeService,
    this.secimOnayi,
    this.secimiKaydet,
    this.ozelOnIzlemeyiHazirla,
    this.alternatifOnIzlemeyiHazirla,
    this.alternatifOnIzlemeAdi,
    this.sonucIleDon = true,
    this.bosSecimleAktarilabilir,
    this.cokluOnIzlemeyiHazirla,
    this.birlesikKaynakSecimi = false,
    this.driveDosyasiSec,
    this.ilerleme,
  }) : assert((secimOnayi == null) == (secimiKaydet == null)),
       assert(!secimleDon || secimiKaydet == null),
       assert(bosSecimleAktarilabilir == null || secimiKaydet != null);
  final ImportTanimi tanim;
  final ValueNotifier<ImportIlerleme?>? ilerleme;
  final BireyselBelgeService? belgeService;
  final ImportDosya? baslangicDosyasi;
  final bool secimleDon;

  /// Tek dosyalı pilotlarda kaynak seçimi aynı girişten yapılır.
  /// Çoklu resim seçimi ve diğer modüllerin mevcut düğmeleri korunur.
  final bool birlesikKaynakSecimi;
  final Future<ImportDosya?> Function()? driveDosyasiSec;
  final Widget? Function(ImportOnIzleme, ImportKaydi)? kayitGorseli;
  final Future<bool> Function(BuildContext, ImportSecimi, String)? secimOnayi;
  final Future<ImportOzet> Function(ImportSecimi)? secimiKaydet;
  final Future<ImportOnIzleme?> Function(BuildContext, ImportDosya)?
  ozelOnIzlemeyiHazirla;
  final Future<ImportOnIzleme?> Function(BuildContext, ImportDosya)?
  alternatifOnIzlemeyiHazirla;
  final String? alternatifOnIzlemeAdi;
  final bool sonucIleDon;
  final bool Function(ImportOnIzleme)? bosSecimleAktarilabilir;

  /// null olduğunda mevcut tek dosyalı modüllerin davranışı değişmez.
  final Future<ImportOnIzleme?> Function(BuildContext, List<ImportDosya>)?
  cokluOnIzlemeyiHazirla;
  @override
  State<OrtakImportScreen> createState() => _OrtakImportScreenState();
}

class _OrtakImportScreenState extends State<OrtakImportScreen> {
  ImportDosya? _dosya;
  List<ImportDosya> _dosyalar = [];
  List<ImportTablosu> _tablolar = [];
  List<ImportProfili> _profiller = [];
  int _tablo = 0, _baslik = -1;
  Map<String, int> _esleme = {};
  ImportOturumu? _oturum;
  ImportOzet? _sonuc;
  String? _hata, _profilBilgisi, _grup;
  bool _mesgul = false, _ozel = false, _modal = false;
  final _baslikController = TextEditingController();
  final _yerelIlerleme = ValueNotifier<ImportIlerleme?>(null);
  ValueNotifier<ImportIlerleme?> get _ilerleme => widget.ilerleme ?? _yerelIlerleme;
  void _asama(String metin) { if (mounted) _ilerleme.value = ImportIlerleme(metin); }
  List<ImportKaynakSatiri> _duzenlemeKaynaklari = [];
  ImportTanimi get _tanim => widget.tanim;
  BireyselBelgeService get _belgeService =>
      widget.belgeService ?? BireyselBelgeService.instance;
  ImportTablosu get _aktifTablo => _tablolar[_tablo];

  @override
  void initState() {
    super.initState();
    if (widget.baslangicDosyasi != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _islem(() => _dosyayiYukle(widget.baslangicDosyasi!));
      });
    }
  }

  @override
  void dispose() {
    _baslikController.dispose();
    _yerelIlerleme.dispose();
    super.dispose();
  }

  Future<void> _islem(Future<void> Function() action) async {
    if (_mesgul) return;
    _asama('İşlem hazırlanıyor…');
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await OrtakImportService.bireyselModuDogrula();
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _hata = 'İşlem tamamlanamadı.\nOrijinal hata: $e');
        if (widget.secimiKaydet != null ||
            widget.ozelOnIzlemeyiHazirla != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_hata!)));
        }
      }
    } finally {
      if (mounted) _ilerleme.value = null;
      if (mounted) setState(() => _mesgul = false);
    }
  }

  void _gecersizKil() {
    _oturum = null;
    _sonuc = null;
    _grup = null;
  }

  Future<T?> _dialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    _ilerleme.value = null;
    setState(() => _modal = true);
    try {
      return await showDialog<T>(context: context, builder: builder);
    } finally {
      if (mounted) setState(() => _modal = false);
    }
  }

  Future<void> _dosyaSec() => _islem(() async {
    _asama('Cihazın dosya seçimi bekleniyor. Dosyanızı seçin veya seçim ekranından iptal edin.');
    if (widget.cokluOnIzlemeyiHazirla != null) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _tanim.uzantilar.toList(),
        allowMultiple: true,
        withData: false,
        withReadStream: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      if (result.files.length > 50 ||
          result.files.fold<int>(0, (n, f) => n + f.size) > 100 * 1024 * 1024) {
        throw const FormatException(
          'Bir seferde en fazla 50 resim ve toplam 100 MB seçin.',
        );
      }
      final files = <ImportDosya>[];
      var total = 0;
      for (final f in result.files) {
        if (f.size > 20 * 1024 * 1024 ||
            !_tanim.uzantilar.contains(f.extension?.toLowerCase())) {
          throw FormatException(
            '${f.name}: desteklenmeyen tür veya 20 MB üzerinde resim.',
          );
        }
        final builder = BytesBuilder(copy: false);
        if (f.bytes != null) {
          builder.add(f.bytes!);
        } else if (f.readStream != null) {
          await for (final chunk in f.readStream!) {
            if (builder.length + chunk.length > 20 * 1024 * 1024 ||
                total + builder.length + chunk.length > 100 * 1024 * 1024) {
              throw const FormatException(
                'Resim veya toplam seçim boyut sınırını aşıyor.',
              );
            }
            builder.add(chunk);
          }
        } else {
          throw StateError('${f.name} okunamadı; dosyayı yeniden seçin.');
        }
        final file = ImportDosya(f.name, builder.takeBytes());
        total += file.bytes.length;
        if (file.bytes.length > 20 * 1024 * 1024 || total > 100 * 1024 * 1024) {
          throw const FormatException(
            'Resim veya toplam seçim boyut sınırını aşıyor.',
          );
        }
        await BelgeAnalizService.bicimiDogrulaAsync(file);
        files.add(file);
      }
      if (!mounted) return;
      await _dosyayiYukle(files.first);
      if (mounted) setState(() => _dosyalar = List.unmodifiable(files));
      return;
    }
    PlatformFile? file;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _tanim.uzantilar.toList(),
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) file = result.files.first;
    if (!mounted || file == null) return;
    if (file.bytes == null) throw StateError('Dosya okunamadı; yeniden seçin.');
    await _dosyayiYukle(ImportDosya(file.name, file.bytes!));
  });

  Future<void> _dosyayiYukle(ImportDosya dosya) async {
    _asama('${dosya.ad}: dosya biçimi ve boyutu kontrol ediliyor…');
    await BelgeAnalizService.bicimiDogrulaAsync(dosya);
    setState(() {
      _gecersizKil();
      _dosya = null;
      _dosyalar = [dosya];
      _tablolar = [];
      _profiller = [];
      _profilBilgisi = null;
      _esleme = {};
      _baslik = -1;
      _ozel = false;
    });
    if (!_tanim.uzantilar.contains(dosya.uzanti)) {
      throw StateError('Dosya türü desteklenmiyor.');
    }
    final forced =
        _tanim.yalnizOzelOkuyucu ||
        !const {'xls', 'xlsx', 'csv'}.contains(dosya.uzanti);
    if (forced) {
      if (_tanim.ozelOku == null) {
        throw StateError('Dosya okuyucusu tanımlanmamış.');
      }
      if (mounted) {
        setState(() {
          _dosya = dosya;
          _ozel = true;
        });
      }
      return;
    }
    _asama('Tablolar okunuyor ve sütunlar hazırlanıyor…');
    final tables = await OrtakImportService.oku(dosya);
    final profiles = await OrtakImportService.profilleriGetir(_tanim);
    if (!mounted) return;
    if (tables.isEmpty || tables.every((t) => t.satirlar.isEmpty)) {
      throw StateError('Dosyada tablo bulunamadı.');
    }
    setState(() {
      _dosya = dosya;
      _tablolar = tables;
      _profiller = profiles;
      _tablo = tables.indexWhere((t) => t.satirlar.isNotEmpty);
      for (var i = 0; i < tables.length; i++) {
        final header = tables[i].baslikBul(_tanim);
        if (header >= 0 &&
            tables[i]
                .eslemeHatalari(
                  _tanim,
                  header,
                  tables[i].otomatikEsle(_tanim, header),
                )
                .isEmpty) {
          _tablo = i;
          break;
        }
      }
      _baslikSec(_aktifTablo.baslikBul(_tanim));
      _ozel =
          dosya.uzanti != 'csv' &&
          _tanim.ozelOku != null &&
          (_tanim.ozelDuzeniTani?.call(
                tables.map((t) => t.satirlar).toList(),
              ) ??
              false);
    });
  }

  void _baslikSec(int header) {
    _baslik = header;
    _baslikController.text = header < 0 ? '' : '${header + 1}';
    _esleme = _aktifTablo.otomatikEsle(_tanim, header);
    _profilBilgisi = null;
    _gecersizKil();
    if (header < 0) {
      // Başlık adları alışılmış değilse kayıtlı profil yapısından başlık ara.
      for (var r = 0; r < _aktifTablo.satirlar.length && r < 100; r++) {
        if (_profiller.any(
          (p) => p.uygula(_tanim, _aktifTablo.satirlar[r]) != null,
        )) {
          _baslik = r;
          _baslikController.text = '${r + 1}';
          break;
        }
      }
    }
    if (_baslik < 0) return;
    final exact = _profiller
        .where((p) => p.uygula(_tanim, _aktifTablo.satirlar[_baslik]) != null)
        .toList();
    if (exact.length == 1) {
      _esleme = exact.single.uygula(_tanim, _aktifTablo.satirlar[_baslik])!;
      _profilBilgisi =
          '${exact.single.ad} profili tanındı. Eşleştirmeyi kontrol edin.';
    } else if (exact.length > 1) {
      _profilBilgisi =
          'Birden fazla uygun profil var; kullanacağınız profili seçin.';
    } else if (_profiller.any(
      (p) =>
          p.uygula(_tanim, _aktifTablo.satirlar[_baslik], benzer: true) != null,
    )) {
      _profilBilgisi =
          'Benzer dosya profili bulundu. Profil listesinden seçip kontrol edebilirsiniz.';
    }
  }

  Future<void> _onIzle() => _islem(() async {
    _asama('Belge okunuyor; ön izleme hazırlanıyor…');
    final file = _dosya;
    if (file == null) throw StateError('Dosya seçin.');
    final ImportOnIzleme preview;
    if (widget.cokluOnIzlemeyiHazirla != null) {
      setState(() {
        _modal = true;
        _gecersizKil();
      });
      final ImportOnIzleme? result;
      try {
        result = await widget.cokluOnIzlemeyiHazirla!(
          context,
          List.unmodifiable(_dosyalar),
        );
      } finally {
        if (mounted) setState(() => _modal = false);
      }
      if (!mounted || result == null) return;
      preview = result;
      setState(_gecersizKil);
    } else if (widget.ozelOnIzlemeyiHazirla != null) {
      setState(() => _modal = true);
      final ImportOnIzleme? ozelPreview;
      try {
        ozelPreview = await widget.ozelOnIzlemeyiHazirla!(context, file);
      } finally {
        if (mounted) setState(() => _modal = false);
      }
      if (!mounted || ozelPreview == null) return;
      preview = ozelPreview;
      setState(_gecersizKil);
    } else {
      setState(_gecersizKil);
      if (!_ozel &&
          file.uzanti != 'csv' &&
          _tanim.ozelOku != null &&
          _tanim.alanlar.any(
            (f) =>
                f.zorunlu &&
                f.kolonDisiKapsam == null &&
                !_esleme.containsKey(f.anahtar),
          ) &&
          (_tanim.ozelDuzeniTani?.call(
                _tablolar.map((t) => t.satirlar).toList(),
              ) ??
              false)) {
        setState(() => _ozel = true);
      }
      if (_ozel) {
        final reader = _tanim.ozelOku;
        if (reader == null) throw StateError('Özel okuyucu tanımlanmamış.');
        preview = await reader(file);
      } else {
        if (_tanim.karmaKaynakli) {
          preview = await _tanim.hazirla(
            OrtakImportService.kaynaklariOku(
              _tanim,
              _tablolar,
              tablo: _tablo,
              baslik: _baslik < 0 ? null : _baslik,
              esleme: _esleme,
            ),
          );
        } else {
          final errors = _aktifTablo.eslemeHatalari(_tanim, _baslik, _esleme);
          if (errors.isNotEmpty) throw StateError(errors.join('\n'));
          preview = await _tanim.hazirla(_aktifTablo.esle(_baslik, _esleme));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _oturum = ImportOturumu(preview);
      _oturum!.topluSec(
        preview.kayitlar.where((r) => r.durum == ImportDurumu.uygun),
        true,
      );
      _duzenlemeKaynaklari = preview.kayitlar
          .map((r) => ImportKaynakSatiri(r.id, r.konum, r.degerler))
          .toList();
    });
  });

  Future<void> _alternatifOnIzle() => _islem(() async {
    final file = _dosya;
    final hazirla = widget.alternatifOnIzlemeyiHazirla;
    if (file == null || hazirla == null || _sonuc != null) return;
    setState(() => _modal = true);
    final ImportOnIzleme? preview;
    try {
      preview = await hazirla(context, file);
    } finally {
      if (mounted) setState(() => _modal = false);
    }
    final hazirPreview = preview;
    if (!mounted || hazirPreview == null) return;
    if (hazirPreview.engeller.isNotEmpty) {
      throw StateError(hazirPreview.engeller.join('\n'));
    }
    setState(() {
      _gecersizKil();
      _oturum = ImportOturumu(hazirPreview);
      _oturum!.topluSec(
        hazirPreview.kayitlar.where((r) => r.durum == ImportDurumu.uygun),
        true,
      );
      _duzenlemeKaynaklari = hazirPreview.kayitlar
          .map((r) => ImportKaynakSatiri(r.id, r.konum, r.degerler))
          .toList();
    });
  });

  Future<void> _profilKaydet() => _islem(() async {
    final controller = TextEditingController();
    String? name;
    try {
      name = await _dialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import Profilini Kaydet'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Profil adı'),
            maxLength: 80,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      );
    } finally {
      // Dialog kapanış animasyonu sırasında TextField controller'ı kullanabilir.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
    if (!mounted || name == null) return;
    if (_profiller.any((p) => p.ad == name)) {
      final replace = await _dialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Profilin Üzerine Yazılsın mı?'),
          content: Text('$name profili zaten var.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Güncelle'),
            ),
          ],
        ),
      );
      if (!mounted || replace != true) return;
    }
    await OrtakImportService.profilKaydet(
      _tanim,
      _aktifTablo,
      _baslik,
      _esleme,
      name,
    );
    final profiles = await OrtakImportService.profilleriGetir(_tanim);
    if (mounted) {
      setState(() {
        _profiller = profiles;
        _profilBilgisi = '$name profili kaydedildi.';
      });
    }
  });

  bool _ekKayitVar(ImportOnIzleme preview) =>
      widget.bosSecimleAktarilabilir?.call(preview) ?? false;

  Future<void> _aktar() => _islem(() async {
    final session = _oturum;
    final dosya = _dosya;
    if (session == null ||
        dosya == null ||
        session.onIzleme.engeller.isNotEmpty ||
        _sonuc != null ||
        (session.secimler.isEmpty && !_ekKayitVar(session.onIzleme))) {
      throw StateError('Ön izlemeyi hazırlayıp aktarılacak kayıtları seçin.');
    }
    final selected = Set<String>.unmodifiable(session.secimler);
    final secim = ImportSecimi(dosya, session.onIzleme, selected);
    final hidden =
        selected.length -
        session.gorunen.where((r) => selected.contains(r.id)).length;
    final warnings = session.onIzleme.kayitlar
        .where(
          (r) => selected.contains(r.id) && r.durum == ImportDurumu.uyarili,
        )
        .length;
    final destination = widget.secimleDon
        ? '${selected.length} kayıt modülün onay ekranına gönderilecek. Henüz kayıt yapılmayacak.'
        : '${selected.length} kayıt bu cihazın yerel veritabanına aktarılacak.';
    final kaynak = dosya.belgeKaynagi;
    var belgeUyarisi = '';
    if (kaynak != null) {
      await _belgeService.importKapsaminiDogrula(kaynak);
      final belge = await _belgeService.belgeGetir(
        kaynak.arsivId,
        kaynak.belgeId,
      );
      final gecmis = await _belgeService.gecmis(belge);
      if (belge.egitimOgretimYili != kaynak.yil) {
        belgeUyarisi =
            '\n\nBelge ${belge.egitimOgretimYili} yılına ait; aktarım ${kaynak.yil} yılına yapılacak. Alanları ve sınıfları kontrol edin.';
      }
      if (gecmis.any((g) => g.modul == _tanim.ad)) {
        belgeUyarisi +=
            '\n\nBu belge bu modüle daha önce aktarıldı. Yeniden aktarım güncelleme yapabilir. Geçmiş, kayıtların bugünkü durumunu göstermez.';
      }
    }
    if (!mounted) return;
    final ortakOzet =
        '$destination\nFiltreyle gizlenen seçili: $hidden\nUyarılı seçili: $warnings\n\n${_tanim.aciklama}$belgeUyarisi';
    final bool? confirm;
    if (widget.secimOnayi != null) {
      _ilerleme.value = null;
      setState(() => _modal = true);
      try {
        confirm = await widget.secimOnayi!(context, secim, ortakOzet);
      } finally {
        if (mounted) setState(() => _modal = false);
      }
    } else {
      confirm = await _dialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            widget.secimleDon
                ? 'Seçilen Kayıtlarla Devam Et'
                : 'Seçilen Kayıtları Aktar',
          ),
          content: Text(ortakOzet),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                widget.secimleDon
                    ? 'Seçimi Onayla ve Devam Et'
                    : 'Onayla ve Aktar',
              ),
            ),
          ],
        ),
      );
    }
    if (!mounted || confirm != true) return;
    await OrtakImportService.bireyselModuDogrula();
    if (kaynak != null) await _belgeService.importKapsaminiDogrula(kaynak);
    if (widget.secimleDon) {
      if (mounted) {
        // İşlem kilidi route'un PopScope'una yansımadan pop engellenir.
        setState(() => _mesgul = false);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) {
          Navigator.pop(
            context,
            ImportSecimi(_dosya!, session.onIzleme, selected),
          );
        }
      }
      return;
    }
    _asama('${selected.length} seçili kayıt kaydediliyor…');
    var result = widget.secimiKaydet != null
        ? await widget.secimiKaydet!(secim)
        : await _tanim.aktar(session.onIzleme, selected);
    if (mounted) setState(() => _sonuc = result);
    if (kaynak != null) {
      try {
        await _belgeService.importSonucunuKaydet(kaynak, _tanim.ad, result);
      } catch (e) {
        if (widget.secimiKaydet != null) {
          result = ImportOzet(
            eklenen: result.eklenen,
            guncellenen: result.guncellenen,
            atlanan: result.atlanan,
            hatali: result.hatali,
            mesaj:
                '${result.mesaj}\n\nVeriler kaydedildi; belge geçmişi '
                'yazılamadı. Orijinal hata: $e',
          );
          if (mounted) setState(() => _sonuc = result);
        } else if (mounted) {
          setState(
            () => _hata =
                'Veriler aktarıldı ancak belge geçmişi kaydedilemedi. Tekrar aktarım yapmadan kontrol edin.\nOrijinal hata: $e',
          );
        }
      }
    }
    if (widget.secimiKaydet != null && widget.sonucIleDon && mounted) {
      setState(() => _mesgul = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop<ImportOzet>(context, result);
    } else if (widget.secimiKaydet != null && mounted) {
      await _dialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kayıt Tamamlandı'),
          content: SingleChildScrollView(
            child: Text(
              '${result.mesaj}\n\nYeni: ${result.eklenen}\n'
              'Güncellenen: ${result.guncellenen}\n'
              'Atlanan: ${result.atlanan}\nHatalı: ${result.hatali}',
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
    }
  });

  Future<void> _belgelerimdenSec() => _islem(() async {
    _asama('Belgelerimden dosya seçimi bekleniyor…');
    final file = await Navigator.of(context).push<ImportDosya>(
      MaterialPageRoute(
        builder: (_) => BireyselBelgelerimScreen(
          service: widget.belgeService,
          secimUzantilari: _tanim.uzantilar,
        ),
      ),
    );
    if (!mounted || file == null) return;
    await _dosyayiYukle(file);
  });

  Future<void> _kaynakSec() async {
    if (_mesgul || _modal) return;
    final kaynak = await _dialog<_ImportDosyaKaynagi>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Dosya Seç'),
        children: [
          if (Platform.isAndroid)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, _ImportDosyaKaynagi.drive),
              child: const ListTile(
                leading: Icon(Icons.cloud_outlined),
                title: Text('Google Drive’dan Seç'),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _ImportDosyaKaynagi.cihaz),
            child: const ListTile(
              leading: Icon(Icons.attach_file),
              title: Text('Cihazımdan Seç'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, _ImportDosyaKaynagi.belgelerim),
            child: const ListTile(
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('Belgelerimden Seç'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
    if (!mounted || kaynak == null) return;
    switch (kaynak) {
      case _ImportDosyaKaynagi.cihaz:
        await _dosyaSec();
      case _ImportDosyaKaynagi.belgelerim:
        await _belgelerimdenSec();
      case _ImportDosyaKaynagi.drive:
        await _islem(() async {
          _asama('Google Drive bağlantısı ve dosya seçimi bekleniyor…');
          final service = DriveBelgeService();
          try {
            final file = widget.driveDosyasiSec == null
                ? await service.sec(_tanim.uzantilar, ilerleme: (d) { if (mounted) _ilerleme.value = d; })
                : await widget.driveDosyasiSec!();
            if (!mounted || file == null) return;
            await OrtakImportService.bireyselModuDogrula();
            if (mounted) await _dosyayiYukle(file);
          } finally {
            service.dispose();
          }
        });
    }
  }

  Future<void> _sablon() => _islem(() async {
    final confirm = await _dialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rehber Şablon'),
        content: SingleChildScrollView(
          child: Text(
            [
              'Şablon zorunlu değildir. Kendi dosyanızdaki alanları eşleştirebilirsiniz.',
              _tanim.aciklama,
              ..._tanim.alanlar
                  .where((f) => f.kolondan)
                  .map((f) => '${f.ad}${f.zorunlu ? ' (gerekli)' : ''}'),
            ].join('\n\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excel Şablonu Kaydet'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final bytes = await BelgeDisariAktarService.excelOlustur(
      _tanim,
      [],
      sablon: true,
    );
    await BelgeDisariAktarService.kaydet('${_tanim.id}_sablon.xlsx', bytes);
  });

  Future<void> _excelAktar() => _islem(() async {
    final session = _oturum!;
    final rows = session.secimler.isEmpty
        ? session.gorunen
        : session.onIzleme.kayitlar
              .where((r) => session.secimler.contains(r.id))
              .toList();
    final bytes = await BelgeDisariAktarService.excelOlustur(_tanim, rows);
    if (!mounted) return;
    final arsive = await _dialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excel Çıktısı'),
        content: Text(
          '${rows.length} kayıt dışa aktarılacak. Orijinal dosya değişmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cihaza Kaydet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Belgelerime Kaydet'),
          ),
        ],
      ),
    );
    if (arsive == null) return;
    final ad = '${_tanim.id}_onizleme.xlsx';
    if (arsive) {
      final service = _belgeService;
      final arsiv = (await service.arsivleriGetir()).aktif;
      await service.ekle(
        arsivId: arsiv.id,
        dosya: PlatformFile(name: ad, size: bytes.length, bytes: bytes),
      );
    } else {
      await BelgeDisariAktarService.kaydet(ad, bytes);
    }
  });

  bool get _duzenlenebilir =>
      !_ozel ||
      _tanim.id == 'bireysel_ogrenci' ||
      _tanim.duzenlemeHazirla != null;
  bool _satirDuzenlenebilir(ImportKaydi row) =>
      _duzenlenebilir &&
      row.degerler['tur'] != 'Şeflik' &&
      (_tanim.id != 'bireysel_yillik_plan' || row.degerler['tur'] == 'Plan');

  Future<void> _duzenle(ImportKaydi? row) => _islem(() async {
    final fields = _tanim.alanlar.where((f) => f.kolondan).toList();
    final controllers = {
      for (final f in fields)
        f.anahtar: TextEditingController(text: row?.degerler[f.anahtar] ?? ''),
    };
    Map<String, String>? result;
    try {
      result = await _dialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            row == null ? 'Görünen Satırlara Ortak Bilgi' : 'Satırı Düzenle',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    row == null
                        ? 'Yalnız dolu bıraktığınız alanlar görünen satırlara uygulanır. Filtre kapsamını kontrol edin.'
                        : row.konum,
                  ),
                  for (final f in fields)
                    TextField(
                      controller: controllers[f.anahtar],
                      decoration: InputDecoration(labelText: f.ad),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                for (final e in controllers.entries) e.key: e.value.text.trim(),
              }),
              child: const Text('Uygula ve Yeniden Kontrol Et'),
            ),
          ],
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in controllers.values) {
          c.dispose();
        }
      });
    }
    if (result == null || !mounted) return;
    final ids = row == null
        ? _oturum!.gorunen.where(_satirDuzenlenebilir).map((r) => r.id).toSet()
        : {row.id};
    final degisiklikler = Map<String, String>.from(result);
    if (row == null) degisiklikler.removeWhere((_, v) => v.isEmpty);
    final sources = _duzenlemeKaynaklari
        .map(
          (r) => ids.contains(r.id)
              ? ImportKaynakSatiri(r.id, r.konum, {
                  ...r.degerler,
                  ...degisiklikler,
                })
              : r,
        )
        .toList();
    final preview = _tanim.duzenlemeHazirla != null
        ? await _tanim.duzenlemeHazirla!(_oturum!.onIzleme, sources)
        : await _tanim.hazirla(sources);
    if (!mounted) return;
    setState(() {
      _duzenlemeKaynaklari = preview.kayitlar
          .map((r) => ImportKaynakSatiri(r.id, r.konum, r.degerler))
          .toList();
      _oturum = ImportOturumu(preview);
      _sonuc = null;
      _grup = null;
    });
  });

  String _durumAdi(ImportDurumu status) => switch (status) {
    ImportDurumu.uygun => 'Uygun',
    ImportDurumu.uyarili => 'Uyarılı',
    ImportDurumu.hatali => 'Hatalı',
    ImportDurumu.atlanan => 'Atlanan',
  };

  Widget _kart(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _eslemeAlani() {
    final table = _aktifTablo;
    final validHeader = _baslik >= 0 && _baslik < table.satirlar.length;
    final headers = validHeader ? table.satirlar[_baslik] : <String>[];
    final usable = validHeader
        ? _profiller
              .where((p) => p.uygula(_tanim, headers, benzer: true) != null)
              .toList()
        : <ImportProfili>[];
    return _kart([
      if (_ozel)
        const Text(
          'Dosyanın özel düzeni tanındı. Ortak bilgiler ilgili kayıtlara '
          'uygulanır. Tüm sayfalar birlikte okunur.',
        ),
      if (!_ozel && _tanim.karmaKaynakli)
        const Text(
          'Kolonlar ve dosya/sayfa/blok bilgileri birlikte okunur. '
          'Kolonda bulunmayan ortak alanlar için kolon seçmeniz gerekmez.',
        ),
      if (_tanim.ozelOku != null && _dosya!.uzanti != 'csv')
        SwitchListTile(
          title: Text(_tanim.ozelOkuyucuAdi),
          subtitle: const Text(
            'Sınıf başlıkları veya kart hücreleri olan dosyalarda kullanın.',
          ),
          value: _ozel,
          onChanged: _mesgul
              ? null
              : (value) => setState(() {
                  _ozel = value;
                  _gecersizKil();
                }),
        ),
      if (!_ozel) ...[
        DropdownButtonFormField<int>(
          key: ValueKey('tablo:$_tablo:${_dosya!.ad}'),
          initialValue: _tablo,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Sayfa / tablo'),
          items: [
            for (var i = 0; i < _tablolar.length; i++)
              DropdownMenuItem(value: i, child: Text(_tablolar[i].ad)),
          ],
          onChanged: _mesgul
              ? null
              : (value) {
                  if (value != null) {
                    setState(() {
                      _tablo = value;
                      _baslikSec(_aktifTablo.baslikBul(_tanim));
                    });
                  }
                },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _baslikController,
          enabled: !_mesgul,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Başlık satırı (1’den başlar)',
            helperText: 'Otomatik tespit yanlışsa satır numarasını düzeltin.',
          ),
          onChanged: (text) => setState(() {
            final row = int.tryParse(text);
            _baslik = row != null && row > 0 && row <= table.satirlar.length
                ? row - 1
                : -1;
            _esleme = table.otomatikEsle(_tanim, _baslik);
            _profilBilgisi = null;
            _gecersizKil();
          }),
        ),
        OrtakGenisleyenBolum(
          title: const Text('Dosyanın ilk satırlarını göster'),
          children: [
            for (var r = 0; r < table.satirlar.length && r < 10; r++)
              ListTile(
                dense: true,
                title: Text('${r + 1}: ${table.satirlar[r].join(' | ')}'),
              ),
          ],
        ),
        if (_profilBilgisi != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_profilBilgisi!),
          ),
        if (usable.isNotEmpty)
          DropdownButtonFormField<int>(
            key: ValueKey('profil:$_tablo:$_baslik:$_profilBilgisi'),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Kayıtlı profili kullan',
            ),
            items: [
              for (var i = 0; i < usable.length; i++)
                DropdownMenuItem(value: i, child: Text(usable[i].ad)),
            ],
            onChanged: _mesgul
                ? null
                : (i) {
                    if (i != null) {
                      setState(() {
                        _esleme = usable[i].uygula(
                          _tanim,
                          headers,
                          benzer: true,
                        )!;
                        _gecersizKil();
                        _profilBilgisi =
                            '${usable[i].ad} uygulandı; eşleştirmeyi kontrol edin.';
                      });
                    }
                  },
          ),
        if (validHeader) ...[
          for (final field in _tanim.alanlar.where((f) => f.kolondan))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<int>(
                key: ValueKey(
                  '${field.anahtar}:$_tablo:$_baslik:${_esleme[field.anahtar]}',
                ),
                initialValue: _esleme[field.anahtar] ?? -1,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText:
                      '${field.ad}${field.zorunlu ? ' *' : ''}${field.kolonDisiKapsam != null ? ' (ortak bilgi de olabilir)' : ''}',
                  helperText: _esleme[field.anahtar] == null
                      ? null
                      : _ornekDeger(_esleme[field.anahtar]!),
                ),
                items: [
                  const DropdownMenuItem(
                    value: -1,
                    child: Text('Eşleştirilmedi'),
                  ),
                  for (var c = 0; c < headers.length; c++)
                    DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${c + 1}. ${headers[c].isEmpty ? '(Başlık boş)' : headers[c]}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _mesgul
                    ? null
                    : (column) => setState(() {
                        _gecersizKil();
                        _profilBilgisi = null;
                        if (column == null || column == -1) {
                          _esleme.remove(field.anahtar);
                        } else {
                          _esleme[field.anahtar] = column;
                        }
                      }),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _mesgul ? null : _profilKaydet,
            child: const Text('Eşleştirmeyi Profil Olarak Kaydet'),
          ),
        ],
      ],
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _mesgul ? null : _onIzle,
        icon: const Icon(Icons.preview),
        label: const Text('Ön İzleme Hazırla'),
      ),
    ]);
  }

  String _ornekDeger(int column) {
    final rows = _aktifTablo.satirlar;
    final values = <String>[];
    for (var r = _baslik + 1; r < rows.length && values.length < 2; r++) {
      if (column < rows[r].length && rows[r][column].isNotEmpty) {
        values.add(rows[r][column]);
      }
    }
    return 'Örnek: ${values.join(' / ')}';
  }

  Widget _onIzlemeAlani() {
    final session = _oturum!, preview = session.onIzleme;
    final visible = session.gorunen;
    final fields = _tanim.alanlar.where((f) => f.onIzlemede).toList();
    final groupFields = _tanim.alanlar.where((f) => f.gruplanabilir).toList();
    final locked = _mesgul || _sonuc != null || preview.engeller.isNotEmpty;
    final groups = <String, List<ImportKaydi>>{};
    if (_grup != null) {
      for (final row in visible) {
        groups.putIfAbsent(row.degerler[_grup] ?? '', () => []).add(row);
      }
    }
    final groupNames = groups.keys.toList()..sort();
    return _kart([
      const Text(
        'Ön İzleme ve Seçim',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const Text(
        'Uygun kayıtlar başlangıçta seçilir. İstemediklerinizi kaldırabilir, '
        'uyarılı kayıtları kontrol ederek seçebilirsiniz.',
      ),
      for (final info in preview.bilgiler) Text(info),
      for (final error in preview.engeller)
        Text(error, style: const TextStyle(color: Colors.red)),
      Text(
        'Toplam: ${preview.kayitlar.length} • Görünen: ${visible.length} • '
        'Seçili: ${session.secimler.length} • Görünen seçili: ${visible.where((r) => session.secimler.contains(r.id)).length}',
      ),
      Text(
        ImportDurumu.values
            .map(
              (status) =>
                  '${_durumAdi(status)}: '
                  '${preview.kayitlar.where((r) => r.durum == status).length}',
            )
            .join(' • '),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<int>(
        key: ValueKey('durum:${session.durumFiltresi}'),
        initialValue: session.durumFiltresi?.index ?? -1,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Kayıt durumu'),
        items: [
          const DropdownMenuItem(value: -1, child: Text('Tümü')),
          for (final status in ImportDurumu.values)
            DropdownMenuItem(
              value: status.index,
              child: Text(_durumAdi(status)),
            ),
        ],
        onChanged: _mesgul
            ? null
            : (i) => setState(
                () => session.durumFiltresi = i == null || i == -1
                    ? null
                    : ImportDurumu.values[i],
              ),
      ),
      for (final field in _tanim.alanlar.where((f) => f.filtrelenebilir))
        Builder(
          builder: (context) {
            final values =
                preview.kayitlar
                    .map((r) => r.degerler[field.anahtar] ?? '')
                    .toSet()
                    .toList()
                  ..sort();
            final selected = session.filtreler[field.anahtar];
            return DropdownButtonFormField<int>(
              key: ValueKey('filtre:${field.anahtar}:$selected'),
              initialValue: selected == null ? -1 : values.indexOf(selected),
              isExpanded: true,
              decoration: InputDecoration(labelText: field.ad),
              items: [
                const DropdownMenuItem(value: -1, child: Text('Tümü')),
                for (var i = 0; i < values.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      values[i].isEmpty ? '(Boş)' : values[i],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _mesgul
                  ? null
                  : (i) => setState(() {
                      if (i == null || i == -1) {
                        session.filtreler.remove(field.anahtar);
                      } else {
                        session.filtreler[field.anahtar] = values[i];
                      }
                    }),
            );
          },
        ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: locked
                ? null
                : () => setState(() => session.topluSec(visible, true)),
            child: const Text('Görünenleri Seç'),
          ),
          TextButton(
            onPressed: locked
                ? null
                : () => setState(() => session.topluSec(visible, false)),
            child: const Text('Görünenlerin Seçimini Kaldır'),
          ),
          TextButton(
            onPressed: locked
                ? null
                : () =>
                      setState(() => session.topluSec(preview.kayitlar, true)),
            child: const Text('Tüm Aktarılabilirleri Seç'),
          ),
          TextButton(
            onPressed: locked ? null : () => setState(session.secimiKaldir),
            child: const Text('Bütün Seçimleri Kaldır'),
          ),
        ],
      ),
      if (groupFields.isNotEmpty)
        DropdownButtonFormField<String>(
          key: ValueKey('grup:$_grup'),
          initialValue: _grup ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Grup bazlı seçim'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Gruplama yok')),
            for (final f in groupFields)
              DropdownMenuItem(value: f.anahtar, child: Text(f.ad)),
          ],
          onChanged: _mesgul
              ? null
              : (key) => setState(() => _grup = key == '' ? null : key),
        ),
      if (groups.isNotEmpty)
        SizedBox(
          height: 160,
          child: ListView.builder(
            itemCount: groupNames.length,
            itemBuilder: (context, index) {
              final name = groupNames[index];
              final eligible = groups[name]!
                  .where((r) => r.aktarilabilir)
                  .toList();
              final count = eligible
                  .where((r) => session.secimler.contains(r.id))
                  .length;
              return CheckboxListTile(
                tristate: true,
                value: count == 0
                    ? false
                    : count == eligible.length
                    ? true
                    : null,
                title: Text(name.isEmpty ? '(Boş)' : name),
                subtitle: Text(
                  '$count/${eligible.length} görünen aktarılabilir kayıt seçili',
                ),
                onChanged: locked || eligible.isEmpty
                    ? null
                    : (_) => setState(
                        () => session.topluSec(
                          eligible,
                          count != eligible.length,
                        ),
                      ),
              );
            },
          ),
        ),
      if (_duzenlenebilir && _sonuc == null)
        TextButton.icon(
          onPressed: _mesgul ? null : () => _duzenle(null),
          icon: const Icon(Icons.edit_note),
          label: const Text('Görünen Satırlara Ortak Bilgi Uygula'),
        ),
      if (_duzenlenebilir && _sonuc == null)
        const Text(
          'Satırı düzenlemek için kayıt bilgilerine uzun basın. Düzeltme sonrası seçimleri yeniden yapın.',
        ),
      const Divider(),
      if (visible.isEmpty)
        const Text('Filtrelere uygun kayıt yok. Önceki seçimler korunuyor.'),
      SizedBox(
        height: 400,
        child: ListView.builder(
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final row = visible[index];
            final color = switch (row.durum) {
              ImportDurumu.hatali => Colors.red,
              ImportDurumu.uyarili => Colors.orange.shade800,
              ImportDurumu.atlanan => Colors.grey,
              ImportDurumu.uygun => Colors.green.shade700,
            };
            return CheckboxListTile(
              key: ValueKey(row.id),
              value: session.secimler.contains(row.id),
              controlAffinity: ListTileControlAffinity.leading,
              secondary: widget.kayitGorseli?.call(preview, row),
              onChanged: locked || !row.aktarilabilir
                  ? null
                  : (value) => setState(() => session.sec(row, value == true)),
              title: Text(
                '${_durumAdi(row.durum)} • ${row.konum}',
                style: TextStyle(color: color),
              ),
              subtitle: GestureDetector(
                onLongPress:
                    _satirDuzenlenebilir(row) && !_mesgul && _sonuc == null
                    ? () => _duzenle(row)
                    : null,
                child: Text(
                  [
                    for (final f in fields)
                      '${f.ad}: ${row.degerler[f.anahtar] ?? ''}',
                    ...row.mesajlar,
                  ].join('\n'),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_mesgul,
    child: OrtakSayfa(
      appBar: ModulUstBar(title: Text(_tanim.ad)),
      bottomNavigationBar: _oturum == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed:
                      _mesgul ||
                          _sonuc != null ||
                          _oturum!.onIzleme.engeller.isNotEmpty ||
                          (_oturum!.secimler.isEmpty &&
                              !_ekKayitVar(_oturum!.onIzleme))
                      ? null
                      : _aktar,
                  icon: const Icon(Icons.save),
                  label: Text(
                    _sonuc == null
                        ? widget.secimiKaydet != null && widget.sonucIleDon
                              ? 'Seçilenleri Onayla ve Kaydet'
                              : _ekKayitVar(_oturum!.onIzleme)
                              ? 'Sınıfları Seç ve Kaydet'
                              : '${_oturum!.secimler.length} Seçili Kaydı ${widget.secimleDon ? 'Onaya Gönder' : 'Aktar'}'
                        : 'Aktarım Tamamlandı',
                  ),
                ),
              ),
            ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(_tanim.aciklama),
              _kart([
                if (widget.birlesikKaynakSecimi &&
                    widget.cokluOnIzlemeyiHazirla == null)
                  OutlinedButton.icon(
                    onPressed: _mesgul || _modal ? null : _kaynakSec,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(_dosya == null ? 'Dosya Seç' : 'Başka Dosya Seç'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _mesgul ? null : _belgelerimdenSec,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Belgelerimden Seç'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _mesgul ? null : _dosyaSec,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      widget.cokluOnIzlemeyiHazirla == null
                          ? 'Cihazdan Dosya Seç'
                          : 'Cihazdan Birden Fazla Resim Seç',
                    ),
                  ),
                ],
                if (_dosya != null)
                  Text(
                    _dosyalar.length > 1
                        ? '${_dosyalar.length} resim seçildi'
                        : _dosya!.ad,
                  ),
                if (_dosyalar.length > 1)
                  OrtakGenisleyenBolum(
                    title: const Text('Seçilen resimler'),
                    children: [
                      for (final f in _dosyalar)
                        ListTile(dense: true, title: Text(f.ad)),
                    ],
                  ),
                if (_tanim.uzantilar.length != 1 ||
                    !_tanim.uzantilar.contains('pdf'))
                  TextButton.icon(
                    onPressed: _mesgul ? null : _sablon,
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Örnek Şablon ve Gerekli Alanlar'),
                  ),
              ]),
              if (_tablolar.isNotEmpty) _eslemeAlani(),
              if (_dosya != null && _tablolar.isEmpty)
                _kart([
                  Text(_tanim.ozelOkuyucuAdi),
                  FilledButton.icon(
                    onPressed: _mesgul ? null : _onIzle,
                    icon: const Icon(Icons.preview),
                    label: const Text('Ön İzleme Hazırla'),
                  ),
                ]),
              if (_hata != null)
                _kart([
                  Text(_hata!, style: const TextStyle(color: Colors.red)),
                ]),
              if (_dosya != null &&
                  widget.alternatifOnIzlemeyiHazirla != null &&
                  (_oturum != null || _hata != null))
                _kart([
                  OutlinedButton.icon(
                    key: const ValueKey('import-alternatif-onizle'),
                    onPressed: _mesgul || _sonuc != null
                        ? null
                        : _alternatifOnIzle,
                    icon: const Icon(Icons.grid_on),
                    label: Text(
                      widget.alternatifOnIzlemeAdi ?? 'Alternatif Ön İzleme',
                    ),
                  ),
                ]),
              if (_sonuc != null)
                _kart([
                  Text(_sonuc!.mesaj),
                  Text('Yeni: ${_sonuc!.eklenen}'),
                  Text('Güncellenen: ${_sonuc!.guncellenen}'),
                  Text('Atlanan: ${_sonuc!.atlanan}'),
                  Text('Hatalı: ${_sonuc!.hatali}'),
                  const Text(
                    'Atlanan sayısı seçilmeyen, kapsam dışı, tekrar ve değişmeyen kayıtları kapsar.',
                  ),
                ]),
              if (_oturum != null) _onIzlemeAlani(),
              if (_oturum != null)
                _kart([
                  OutlinedButton.icon(
                    onPressed: _mesgul ? null : _excelAktar,
                    icon: const Icon(Icons.download),
                    label: const Text('Ön İzlemeyi Excel Olarak Dışa Aktar'),
                  ),
                ]),
            ],
          ),
          if (_mesgul)
            Positioned.fill(child: ValueListenableBuilder<ImportIlerleme?>(
              valueListenable: _ilerleme,
              builder: (_, durum, __) => _modal && (widget.ilerleme == null || durum == null)
                  ? const SizedBox.shrink()
                  : ColoredBox(color: const Color(0x55000000), child: AbsorbPointer(
                      child: ImportIlerlemeKarti(durum: durum ?? const ImportIlerleme('İşlem sürüyor…')))),
            )),
        ],
      ),
    ),
  );
}
