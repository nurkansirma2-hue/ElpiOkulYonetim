import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ana sayfanın mevcut işlemlerini açık modüllerden de kullanır.
/// Kayıt/kurulum ekranı tek başına açıldığında ana sayfa varmış gibi davranmaz.
class ModulUstBarBaglantisi {
  ModulUstBarBaglantisi({
    required this.sahip,
    required this.ayarlar,
    required this.profil,
    required this.bildirimler,
    this.renk,
    this.tema,
  });

  static ModulUstBarBaglantisi? aktif;
  final Object sahip;
  final Future<void> Function() ayarlar, profil, bildirimler;
  final Color Function()? renk;
  final ThemeData Function()? tema;
}

/// Home dönüşünde her sayfanın PopScope/kayıt/işlem kilidini korur.
/// popUntil ile sayfaları zorla kaldırmaz; engel veya onay penceresinde durur.
Future<void> moduldenAnaSayfayaDon(BuildContext context) async {
  final navigator = Navigator.of(context);
  Route<dynamic>? ustRota() {
    Route<dynamic>? sonuc;
    navigator.popUntil((route) {
      sonuc = route;
      return true;
    });
    return sonuc;
  }

  while (navigator.mounted && navigator.canPop()) {
    final onceki = ustRota();
    await navigator.maybePop();
    if (!navigator.mounted) return;
    final sonraki = ustRota();
    if (identical(onceki, sonraki)) return;
    if (onceki?.isActive == true && sonraki is PopupRoute) {
      // PopScope bir onay penceresi açtıysa kullanıcının kararını bekle.
      await sonraki.completed;
      if (!navigator.mounted || onceki?.isActive == true) return;
    }
    // maybePop geçiş animasyonu bitmeden dönebilir. Eski rota tamamen
    // kapanmadan sıradaki pop'u denemek ana sayfa dönüşünü yarıda keser.
    if (onceki is TransitionRoute<dynamic>) {
      await onceki.completed;
    }
    if (!navigator.mounted) return;
  }
}

/// Ortak üst alan; ekranın mevcut işlem düğmeleri aynen korunur.
class ModulUstBar extends StatelessWidget implements PreferredSizeWidget {
  const ModulUstBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.centerTitle,
    this.automaticallyImplyLeading = true,
    this.flexibleSpace,
    this.kompakt = false,
    this.toolbarHeight,
  });

  final Widget? title, leading, flexibleSpace;
  final List<Widget>? actions;
  final bool? centerTitle;
  final bool automaticallyImplyLeading;
  final bool kompakt;
  final double? toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? (kompakt ? 64 : 56)) + (kompakt ? 0 : 56),
  );

  @override
  Widget build(BuildContext context) {
    final baglanti = ModulUstBarBaglantisi.aktif;
    final temelRenk =
        baglanti?.renk?.call() ?? Theme.of(context).colorScheme.primary;
    final renk = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(temelRenk, Colors.black, .55)!
        : temelRenk;
    final genelIslemler = <Widget>[
      IconButton(
        tooltip: 'Ana Sayfa',
        color: Colors.white,
        disabledColor: Colors.white54,
        onPressed: baglanti == null
            ? null
            : () => moduldenAnaSayfayaDon(context),
        icon: const Icon(Icons.home_rounded),
      ),
      IconButton(
        tooltip: 'Bildirimler',
        color: Colors.white,
        disabledColor: Colors.white54,
        onPressed: baglanti?.bildirimler,
        icon: const Icon(Icons.notifications_outlined),
      ),
      PopupMenuButton<String>(
        tooltip: 'Diğer işlemler',
        iconColor: Colors.white,
        enabled: baglanti != null,
        onSelected: (secim) async {
          if (secim == 'ayarlar') await baglanti?.ayarlar();
          if (secim == 'profil') await baglanti?.profil();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'ayarlar', child: Text('Ayarlar')),
          PopupMenuItem(value: 'profil', child: Text('Profilim')),
        ],
      ),
    ];
    return AppBar(
      title: title == null
          ? null
          : DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: title!,
            ),
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: centerTitle ?? false,
      toolbarHeight: toolbarHeight ?? (kompakt ? 64 : 56),
      actions: kompakt ? [...?actions, ...genelIslemler] : null,
      backgroundColor: renk,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace:
          flexibleSpace ??
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [renk, Color.lerp(renk, Colors.cyan, .18)!],
              ),
            ),
          ),
      bottom: kompakt
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (actions?.isNotEmpty == true)
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TextButtonTheme(
                            data: TextButtonThemeData(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                            ),
                            child: IconTheme.merge(
                              data: const IconThemeData(color: Colors.white),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: actions!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ...genelIslemler,
                  ],
                ),
              ),
            ),
    );
  }
}
