import 'ortak_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const anaSayfaZemin = Color(0xFFF4F6FA);
const anaSayfaMetin = Color(0xFF1E3557);
const anaSayfaVurgu = Color(0xFF46689A);
const anaSayfaPastel = Color(0xFFEAF0FB);

enum AnaSayfaTemasi {
  mavi('Okul Mavisi', 0xFF126BA5, 0xFFF5F9FD, 0xFFEAF1FF, 0xFF16244A),
  yesil('Doğa Yeşili', 0xFF28704F, 0xFFF3F7F4, 0xFFE4F2E9, 0xFF183E32),
  turkuaz('Sakin Turkuaz', 0xFF216F7D, 0xFFF2F8F9, 0xFFE1F2F4, 0xFF163D47),
  mor('Yumuşak Mor', 0xFF705293, 0xFFF7F4FA, 0xFFF0EAFA, 0xFF3E3056),
  toprak('Sıcak Toprak', 0xFF895C36, 0xFFFAF6F0, 0xFFF5EADF, 0xFF49382B),
  grafit('Duru Grafit', 0xFF536579, 0xFFF5F6F8, 0xFFE9EDF1, 0xFF29333D);

  const AnaSayfaTemasi(
    this.baslik,
    this.vurgu,
    this.zemin,
    this.pastel,
    this.metin,
  );
  final String baslik;
  final int vurgu, zemin, pastel, metin;

  ThemeData olustur(Brightness brightness) {
    final koyu = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Color(vurgu),
          brightness: brightness,
        ).copyWith(
          primary: koyu ? null : Color(vurgu),
          surface: koyu ? null : Colors.white,
          onSurface: koyu ? null : Color(metin),
          primaryContainer: koyu ? null : Color(pastel),
          onPrimaryContainer: koyu ? null : Color(metin),
        );
    return OrtakUi.tema(
      ThemeData(
        useMaterial3: true,
        fontFamily: 'NotoSans',
        colorScheme: scheme,
        scaffoldBackgroundColor: koyu ? scheme.surface : Color(zemin),
      ),
    );
  }
}

/// Her iki çalışma modu aynı kalıcı menü tercihini kullanır.
/// Destekleyen ekranlar bu bildirimi dinleyerek yeniden kurulmadan yenilenir.
class OrtakGorunumTercihi extends ChangeNotifier {
  OrtakGorunumTercihi._();

  static final instance = OrtakGorunumTercihi._();
  static const _anahtar = 'ana_sayfa_kompakt';
  bool _kompakt = false;
  bool get kompakt => _kompakt;
  AnaSayfaTemasi tema = AnaSayfaTemasi.mavi;
  ThemeMode ekranModu = ThemeMode.light;
  void temaUygula(AnaSayfaTemasi yeniTema, ThemeMode yeniMod) {
    if (tema == yeniTema && ekranModu == yeniMod) return;
    tema = yeniTema;
    ekranModu = yeniMod;
    notifyListeners();
  }

  Future<void>? _sira;

  Future<void> _sirali(Future<void> Function() islem) {
    final sonuc = (_sira ?? Future<void>.value()).then((_) => islem());
    final tamamlandi = sonuc.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _sira = tamamlandi;
    tamamlandi.then((_) {
      if (identical(_sira, tamamlandi)) _sira = null;
    });
    return sonuc;
  }

  Future<void> yukle() => _sirali(() async {
    final prefs = await SharedPreferences.getInstance();
    _guncelle(prefs.getBool(_anahtar) ?? false);
    temaUygula(
      AnaSayfaTemasi.values.firstWhere(
        (t) => t.name == prefs.getString('ana_sayfa_tema'),
        orElse: () => AnaSayfaTemasi.mavi,
      ),
      ThemeMode.values.firstWhere(
        (t) => t.name == prefs.getString('ana_sayfa_ekran_modu'),
        orElse: () => ThemeMode.light,
      ),
    );
  });

  Future<void> kaydet(bool kompakt) => _sirali(() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_anahtar, kompakt)) {
      throw Exception('Görünüm tercihi kaydedilemedi.');
    }
    _guncelle(kompakt);
  });

  void _guncelle(bool kompakt) {
    if (_kompakt == kompakt) return;
    _kompakt = kompakt;
    notifyListeners();
  }
}

mixin AnaSayfaGorunumTercihi<T extends StatefulWidget> on State<T> {
  final _ortakGorunum = OrtakGorunumTercihi.instance;
  bool get kompaktGorunum => _ortakGorunum.kompakt;
  bool derslerAcik = true;
  bool _tercihHazir = false;
  static const _dersKey = 'ana_sayfa_dersler_acik';
  static const _temaKey = 'ana_sayfa_tema';
  static const _ekranKey = 'ana_sayfa_ekran_modu';
  AnaSayfaTemasi seciliTema = AnaSayfaTemasi.mavi;
  ThemeMode ekranModu = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _ortakGorunum.addListener(_gorunumDegisti);
  }

  void _gorunumDegisti() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ortakGorunum.removeListener(_gorunumDegisti);
    super.dispose();
  }

  ThemeData get anaSayfaTema {
    final brightness = ekranModu == ThemeMode.system
        ? MediaQuery.platformBrightnessOf(context)
        : ekranModu == ThemeMode.dark
        ? Brightness.dark
        : Brightness.light;
    return seciliTema.olustur(brightness);
  }

  Color get anaSayfaZemin => anaSayfaTema.scaffoldBackgroundColor;
  Color get anaSayfaMetin => anaSayfaTema.colorScheme.onSurface;
  Color get anaSayfaVurgu => anaSayfaTema.colorScheme.primary;
  Color get anaSayfaPastel => anaSayfaTema.colorScheme.primaryContainer;

  Widget temaIleGoster(WidgetBuilder builder) => Theme(
    data: anaSayfaTema,
    child: Builder(builder: builder),
  );

  Future<void> gorunumTercihiniYukle() async {
    try {
      await _ortakGorunum.yukle();
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        derslerAcik = prefs.getBool(_dersKey) ?? true;
        seciliTema = AnaSayfaTemasi.values.firstWhere(
          (tema) => tema.name == prefs.getString(_temaKey),
          orElse: () => AnaSayfaTemasi.mavi,
        );
        ekranModu = ThemeMode.values.firstWhere(
          (mod) => mod.name == prefs.getString(_ekranKey),
          orElse: () => ThemeMode.light,
        );
        _tercihHazir = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _tercihHazir = true);
      _tercihHatasi(e);
    }
  }

  void _tercihHatasi(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Görünüm tercihi kaydedilemedi veya okunamadı. '
          'Orijinal hata: $e',
        ),
      ),
    );
  }

  Future<void> _kaydet(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(key, value)) {
        throw Exception('Tercih kaydı başarısız.');
      }
    } catch (e) {
      if (mounted) _tercihHatasi(e);
    }
  }

  void dersleriDaraltGenislet() {
    if (!_tercihHazir) return;
    setState(() => derslerAcik = !derslerAcik);
    _kaydet(_dersKey, derslerAcik);
  }

  Future<void> ayarlariAc({
    Future<void> Function()? onOkulBilgileri,
    Future<void> Function()? onYonetimBakim,
  }) async {
    final secim = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Theme(
        data: anaSayfaTema,
        child: AlertDialog(
          title: const Text('Ayarlar'),
          scrollable: true,
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onOkulBilgileri != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('Okul Bilgileri'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(dialogContext, 'okul'),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Görünüm'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(dialogContext, 'gorunum'),
                ),
                if (onYonetimBakim != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.build_outlined),
                    title: const Text('Yönetim ve Bakım'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(dialogContext, 'bakim'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Kapat'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (secim) {
      case 'okul':
        await onOkulBilgileri?.call();
      case 'gorunum':
        await gorunumAyarlariniAc();
      case 'bakim':
        await onYonetimBakim?.call();
    }
  }

  Future<void> gorunumAyarlariniAc() async {
    if (!_tercihHazir) return;
    var kompakt = kompaktGorunum;
    var tema = seciliTema;
    var mod = ekranModu;
    final sonuc = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, yenile) {
          final brightness = mod == ThemeMode.system
              ? MediaQuery.platformBrightnessOf(context)
              : mod == ThemeMode.dark
              ? Brightness.dark
              : Brightness.light;
          return Theme(
            data: tema.olustur(brightness),
            child: AlertDialog(
              title: const Text('Görünüm ayarları'),
              scrollable: true,
              content: SizedBox(
                width: 340,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Renk teması'),
                    const SizedBox(height: 8),
                    for (final secenek in AnaSayfaTemasi.values)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Color(secenek.vurgu),
                          child: tema == secenek
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                        title: Text(secenek.baslik),
                        selected: tema == secenek,
                        onTap: () => yenile(() => tema = secenek),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<ThemeMode>(
                      initialValue: mod,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Ekran modu',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text('Açık'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text('Koyu'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text('Sisteme göre'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) yenile(() => mod = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Kompakt liste'),
                      subtitle: Text(
                        kompakt ? 'Modüller alt alta' : 'Dengeli kartlar',
                      ),
                      value: kompakt,
                      onChanged: (value) => yenile(() => kompakt = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Uygula'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || sonuc != true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_temaKey, tema.name) ||
          !await prefs.setString(_ekranKey, mod.name)) {
        throw Exception('Tercih kaydı başarısız.');
      }
      await _ortakGorunum.kaydet(kompakt);
      _ortakGorunum.temaUygula(tema, mod);
      if (!mounted) return;
      setState(() {
        seciliTema = tema;
        ekranModu = mod;
      });
    } catch (e) {
      if (mounted) _tercihHatasi(e);
    }
  }
}

Color _baslikRengi(BuildContext context) {
  final renk = Theme.of(context).colorScheme.primary;
  return Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(renk, Colors.black, .55)!
      : renk;
}

/// Ana sayfa üst barı; bildirim sayısı yalnız gerçek bir kaynaktan verilirse görünür.
class AnaSayfaUstBar extends AppBar {
  AnaSayfaUstBar({
    super.key,
    required BuildContext context,
    required String modAdi,
    required List<Widget> islemler,
    Widget? geri,
  }) : super(
         title: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             const Text(
               'OkulYonetim',
               maxLines: 1,
               overflow: TextOverflow.ellipsis,
               style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
             ),
             Text(
               modAdi,
               maxLines: 1,
               overflow: TextOverflow.ellipsis,
               style: const TextStyle(
                 fontSize: 12,
                 fontWeight: FontWeight.normal,
               ),
             ),
           ],
         ),
         leading: geri,
         automaticallyImplyLeading: false,
         centerTitle: false,
         titleSpacing: geri == null ? 16 : 0,
         toolbarHeight:
             (MediaQuery.textScalerOf(context).scale(21) * 1.25 +
                     MediaQuery.textScalerOf(context).scale(12) * 1.3 +
                     14)
                 .clamp(72, 120)
                 .toDouble(),
         foregroundColor: Colors.white,
         backgroundColor: _baslikRengi(context),
         surfaceTintColor: Colors.transparent,
         elevation: 0,
         scrolledUnderElevation: 0,
         systemOverlayStyle: SystemUiOverlayStyle.light,
         flexibleSpace: DecoratedBox(
           decoration: BoxDecoration(
             gradient: LinearGradient(
               colors: [
                 _baslikRengi(context),
                 Color.lerp(_baslikRengi(context), Colors.cyan, .18)!,
               ],
             ),
           ),
         ),
         actions: islemler,
       );
}

class AnaSayfaBildirimSimgesi extends StatelessWidget {
  const AnaSayfaBildirimSimgesi({
    super.key,
    required this.onPressed,
    this.okunmamis,
  });
  final VoidCallback onPressed;
  final int? okunmamis;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Bildirimler',
    onPressed: onPressed,
    icon: Badge(
      isLabelVisible: (okunmamis ?? 0) > 0,
      label: Text((okunmamis ?? 0) > 99 ? '99+' : '${okunmamis ?? 0}'),
      child: const Icon(Icons.notifications_outlined),
    ),
  );
}

class AnaMenuYerlesimi extends StatelessWidget {
  const AnaMenuYerlesimi({
    super.key,
    required this.kompakt,
    required this.children,
    this.yatay = false,
    this.kutucuk = false,
  });
  final bool kompakt, yatay, kutucuk;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final buyukYazi = MediaQuery.textScalerOf(context).scale(14) > 21;
      var kolon = kompakt || buyukYazi || (!yatay && constraints.maxWidth < 340)
          ? 1
          : !yatay && constraints.maxWidth >= 800
          ? 3
          : 2;
      if (kutucuk && !kompakt && !buyukYazi) {
        kolon = constraints.maxWidth >= 700 ? 5 : 3;
      }
      final bosluk = yatay ? 8.0 : 12.0;
      if (kolon > 1) {
        final adayGenislik =
            (constraints.maxWidth - (kolon - 1) * bosluk) / kolon;
        final metinAlani =
            adayGenislik -
            (kutucuk
                ? 16
                : yatay
                ? 90
                : 32);
        final stil = Theme.of(context).textTheme.titleMedium!.copyWith(
          fontSize: kutucuk
              ? 12
              : yatay
              ? 13
              : 14,
          fontWeight: FontWeight.w600,
        );
        final guvenli = children.whereType<AnaMenuKart>().every((kart) {
          final p = TextPainter(
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          );
          for (final kelime in kart.baslik.split(RegExp(r'\s+'))) {
            p.text = TextSpan(text: kelime, style: stil);
            p.layout();
            if (p.width > metinAlani) return false;
          }
          p.text = TextSpan(text: kart.baslik, style: stil);
          p.layout(maxWidth: metinAlani.clamp(1, double.infinity));
          return p.computeLineMetrics().length <= 2;
        });
        if (!guvenli) kolon = kutucuk && kolon > 2 ? 2 : 1;
      }
      final width = (constraints.maxWidth - (kolon - 1) * bosluk) / kolon;
      return AnaMenuStili(
        kompakt: kompakt,
        yatay: yatay,
        kutucuk: kutucuk,
        dar: width < 170,
        child: yatay
            ? Column(
                children: [
                  for (var i = 0; i < children.length; i += kolon) ...[
                    if (i > 0) SizedBox(height: bosluk),
                    Padding(
                      padding: EdgeInsets.zero,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var j = 0; j < kolon; j++) ...[
                            if (j > 0) SizedBox(width: bosluk),
                            Expanded(
                              child: i + j < children.length
                                  ? children[i + j]
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              )
            : Wrap(
                spacing: bosluk,
                runSpacing: bosluk,
                children: [
                  for (final child in children)
                    SizedBox(width: width, child: child),
                ],
              ),
      );
    },
  );
}

class AnaMenuStili extends InheritedWidget {
  const AnaMenuStili({
    super.key,
    required this.kompakt,
    required super.child,
    this.yatay = false,
    this.dar = false,
    this.kutucuk = false,
  });
  final bool kompakt, yatay, dar, kutucuk;
  @override
  bool updateShouldNotify(AnaMenuStili oldWidget) =>
      oldWidget.kompakt != kompakt ||
      oldWidget.yatay != yatay ||
      oldWidget.dar != dar ||
      oldWidget.kutucuk != kutucuk;
}

class AnaMenuKart extends StatelessWidget {
  const AnaMenuKart({
    super.key,
    required this.icon,
    required this.baslik,
    required this.onTap,
    this.renk,
    this.aciklama,
  });
  final IconData icon;
  final String baslik;
  final String? aciklama;
  final VoidCallback? onTap;
  final Color? renk;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stil = context.dependOnInheritedWidgetOfExactType<AnaMenuStili>();
    final yatay = stil?.yatay ?? false,
        kompakt = stil?.kompakt ?? false,
        dar = stil?.dar ?? false;
    if (stil?.kutucuk == true) {
      final vurgu = renk ?? scheme.primary;
      final koyu = Theme.of(context).brightness == Brightness.dark;
      final yaziYuksekligi =
          MediaQuery.textScalerOf(context).scale(12) * 1.25 * 2;
      return Semantics(
        button: true,
        label: baslik,
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: Color.alphaBlend(
            vurgu.withValues(alpha: koyu ? .18 : .09),
            scheme.surface,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 34,
                    color: koyu ? Color.lerp(vurgu, Colors.white, .35) : vurgu,
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: yaziYuksekligi),
                    child: Center(
                      child: OrtakBaslik(
                        baslik,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final vurgu = yatay
        ? renk ?? scheme.primary
        : renk == Colors.red
        ? scheme.error
        : scheme.primary;
    final simge = Container(
      width: yatay ? (dar ? 32 : 40) : null,
      height: yatay ? (dar ? 38 : 44) : null,
      padding: EdgeInsets.all(yatay ? 6 : 10),
      decoration: BoxDecoration(
        color: yatay ? vurgu : vurgu.withAlpha(20),
        borderRadius: BorderRadius.circular(yatay ? 7 : 12),
        gradient: yatay
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(vurgu, Colors.white, .08)!, vurgu],
              )
            : null,
      ),
      child: Icon(
        icon,
        size: yatay ? (dar ? 24 : 28) : 24,
        color: yatay ? Colors.white : vurgu,
      ),
    );
    final yazi = OrtakBaslik(
      baslik,
      style: TextStyle(
        color: scheme.onSurface,
        fontSize: yatay ? 13 : 14,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: yatay ? .5 : 0,
      shadowColor: scheme.shadow.withAlpha(12),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(yatay ? 9 : 16),
        side: BorderSide(
          color: yatay ? scheme.primary.withAlpha(22) : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: yatay ? (dar ? 88 : 76) : 0),
          padding: EdgeInsets.all(
            yatay
                ? 8
                : kompakt
                ? 12
                : 16,
          ),
          child: yatay
              ? Row(
                  children: [
                    simge,
                    SizedBox(width: dar ? 7 : 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          yazi,
                          if (aciklama?.isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              aciklama!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: dar ? 9.5 : 10.5,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: dar ? 14 : 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                )
              : kompakt
              ? Row(
                  children: [
                    simge,
                    const SizedBox(width: 12),
                    Expanded(child: yazi),
                    Icon(Icons.chevron_right, color: scheme.primary),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [simge, const SizedBox(height: 10), yazi],
                ),
        ),
      ),
    );
  }
}

class GunlukDersGorunumu extends StatelessWidget {
  const GunlukDersGorunumu({
    super.key,
    required this.acik,
    required this.onToggle,
    required this.tarih,
    required this.bugun,
    required this.oncekiGun,
    required this.sonrakiGun,
    required this.buguneDon,
    this.onTarihSec,
    required this.dersAdi,
    required this.sinif,
    required this.saat,
    required this.konu,
    required this.durum,
    required this.durumIcon,
    required this.sira,
    this.oncekiDers,
    this.sonrakiDers,
    this.ogretmen = '',
    this.derslik = '',
    this.uyari = '',
    this.gorevMi = false,
    this.onGunlukPlan,
    this.onYillikPlan,
    this.gunlukPlanMenusu = false,
    this.gunlukPlanYukleniyor = false,
    this.konuGoster = true,
    this.bosMesaji,
  });
  final bool acik, bugun, gorevMi;
  final VoidCallback onToggle, oncekiGun, sonrakiGun, buguneDon;
  final VoidCallback? onTarihSec;
  final VoidCallback? oncekiDers, sonrakiDers;
  final VoidCallback? onGunlukPlan, onYillikPlan;
  final bool gunlukPlanMenusu;
  final bool gunlukPlanYukleniyor;
  final bool konuGoster;
  final String? bosMesaji;
  final String tarih,
      dersAdi,
      sinif,
      saat,
      konu,
      durum,
      sira,
      ogretmen,
      derslik,
      uyari;
  final IconData durumIcon;

  Widget _tarihVeDersKontrolleri(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(tooltip: 'Önceki ders', onPressed: oncekiDers,
            icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('Dersler arasında geçiş',
            textAlign: TextAlign.center, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'Sonraki ders', onPressed: sonrakiDers,
            icon: const Icon(Icons.chevron_right)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(tooltip: 'Önceki gün', onPressed: oncekiGun,
            icon: const Icon(Icons.chevron_left)),
          Expanded(child: OutlinedButton.icon(
            onPressed: onTarihSec,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(tarih.split(' ').first,
              maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          )),
          IconButton(tooltip: 'Sonraki gün', onPressed: sonrakiGun,
            icon: const Icon(Icons.chevron_right)),
        ]),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: bugun ? null : buguneDon,
          icon: const Icon(Icons.today_outlined, size: 18),
          label: const Text('Bugün'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: colors.primaryContainer.withValues(alpha: .55)),
        ),
      ]),
    );
  }

  Widget _onayliDersKarti(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrtakBolumBasligi(
            title: Text(bugun ? 'O Anki Dersim' : 'Seçili Günün Dersleri', maxLines: 1, overflow: TextOverflow.ellipsis),
            leading: const Icon(Icons.school_outlined), acik: acik, onToggle: onToggle,
          ),
          if (acik) ...[
          Padding(
            padding: const EdgeInsets.all(10),
            child: LayoutBuilder(builder: (context, constraints) {
              final dar = constraints.maxWidth < 390;
              final dersBilgisi = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(sinif.isEmpty ? dersAdi : '$sinif  $dersAdi',
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.menu_book_outlined, size: 16,
                      color: colors.primary),
                    const SizedBox(width: 6),
                    Text('Yıllık Plan Konusu',
                      style: theme.textTheme.labelSmall),
                  ]),
                  Text(konu.trim().isEmpty ? 'Bu tarih için konu bulunamadı.' : konu,
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
                  if (derslik.isNotEmpty)
                    Text('Derslik: $derslik', style: theme.textTheme.bodySmall),
                ],
              );
              final saatKarti = Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.schedule, color: colors.onPrimaryContainer),
                  Text(saat, textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
                  if (sira.isNotEmpty)
                    Text(sira, style: theme.textTheme.labelSmall),
                ]),
              );
              if (dar) {
                return Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 106, child: saatKarti),
                    const SizedBox(width: 10),
                    Expanded(child: dersBilgisi),
                  ]),
                ]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                SizedBox(width: 108, child: saatKarti),
                const SizedBox(width: 10),
                Expanded(child: dersBilgisi),
              ]);
            }),
          ),
          _tarihVeDersKontrolleri(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: gunlukPlanYukleniyor ? null : onGunlukPlan,
                  icon: const Icon(Icons.event_note_outlined, size: 18),
                  label: const Text('Günlük Plan', maxLines: 1),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: onYillikPlan,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Yıllık Plan', maxLines: 1),
                ),
              ],
            ),
          ),
          ],
          if (uyari.isNotEmpty)
            Padding(padding: const EdgeInsets.all(8),
                child: Text(uyari, style: TextStyle(color: colors.error))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => gunlukPlanMenusu && bosMesaji == null
      ? _onayliDersKarti(context)
      : Container(
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withAlpha(24),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                bugun ? 'Bugünkü dersler' : 'Seçili günün dersleri',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onToggle,
              iconAlignment: IconAlignment.end,
              icon: Icon(
                acik ? Icons.keyboard_double_arrow_up : Icons.keyboard_double_arrow_down,
                size: 18,
              ),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                textStyle: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontSize: 11),
              ),
              label: Text(acik ? 'Daralt' : 'Genişlet'),
            ),
          ],
        ),
        if (acik) ...[
          Row(
            children: [
              IconButton(
                onPressed: oncekiGun,
                tooltip: 'Önceki gün',
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(child: Text(tarih, textAlign: TextAlign.center)),
              IconButton(
                onPressed: sonrakiGun,
                tooltip: 'Sonraki gün',
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (!bugun)
            Center(
              child: TextButton.icon(
                onPressed: buguneDon,
                icon: const Icon(Icons.today),
                label: const Text('Bugüne dön'),
              ),
            ),
          if (bosMesaji != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(bosMesaji!),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (acik) ...[
                    Row(
                      children: [
                        Icon(
                          durumIcon,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            durum,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    sinif.trim().isEmpty ? dersAdi : '$dersAdi · $sinif',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$saat · $sira',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                  if (!gorevMi) ...[
                    if (konuGoster) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Yıllık plan konusu',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        konu.isEmpty ? 'Bu tarih için konu bulunamadı.' : konu,
                        maxLines: acik ? null : 2,
                        overflow: acik ? null : TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                    Wrap(
                      spacing: 8,
                      children: [
                        if (onGunlukPlan != null || gunlukPlanYukleniyor)
                          if (gunlukPlanMenusu)
                            PopupMenuButton<String>(
                              tooltip: 'Ders işlemleri',
                              icon: const Icon(Icons.more_vert),
                              onSelected: (v) {
                                if (v == 'gunlukPlan') {
                                  onGunlukPlan?.call();
                                } else if (v == 'konu') {
                                  showDialog<void>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Yıllık plan konusu'),
                                      content: Text(
                                        konu.trim().isEmpty
                                            ? 'Bu tarih için konu bulunamadı.'
                                            : konu,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext),
                                          child: const Text('Kapat'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem<String>(
                                  value: 'konu',
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.menu_book_outlined),
                                    title: Text('Yıllık plan konusu'),
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'gunlukPlan',
                                  enabled: onGunlukPlan != null,
                                  child: const ListTile(
                                    dense: true,
                                    leading: Icon(Icons.event_note_outlined),
                                    title: Text('Günlük Plan Oluştur'),
                                  ),
                                ),
                              ],
                            )
                          else TextButton.icon(
                            onPressed: onGunlukPlan,
                            icon: gunlukPlanYukleniyor
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.event_note_outlined),
                            label: Text(
                              gunlukPlanYukleniyor
                                  ? 'Hazırlanıyor…'
                                  : 'Günlük Plan',
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (acik && derslik.isNotEmpty) Text('Derslik: $derslik'),
                  if (acik && ogretmen.isNotEmpty)
                    Text(
                      ogretmen,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          if (uyari.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                uyari,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
        if (!acik && bosMesaji == null) ...[
          const SizedBox(height: 8),
          Text(
            sinif.trim().isEmpty ? dersAdi : '$dersAdi · $sinif',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('$saat · $sira', style: Theme.of(context).textTheme.bodySmall),
        ],
        if (bosMesaji == null)
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  key: const ValueKey('onceki-ders'),
                  onPressed: oncekiDers,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('Önceki ders'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('sonraki-ders'),
                  onPressed: sonrakiDers,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('Sonraki ders'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
