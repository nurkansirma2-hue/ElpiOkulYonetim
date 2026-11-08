import 'package:flutter/material.dart';
export 'ortak_genisleyen_bolum.dart';
import 'modul_ust_bar.dart';

/// Modüller aynı yüzey, form ve işlem stillerini kullanır.
abstract final class OrtakUi {
  static const radius = 12.0;
  static const bosluk = 12.0;

  static ThemeData tema(ThemeData base) {
    final s = base.colorScheme;
    final kenar = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: s.outlineVariant),
    );
    final sekil = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 14),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 13),
            bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 11),
          )
          .apply(fontFamily: 'NotoSans'),
      cardTheme: CardThemeData(
        color: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: s.outlineVariant.withValues(alpha: .6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerLowest,
        isDense: true,
        contentPadding: const EdgeInsets.all(bosluk),
        border: kenar,
        enabledBorder: kenar,
        disabledBorder: kenar,
        focusedBorder: kenar.copyWith(
          borderSide: BorderSide(color: s.primary, width: 1.5),
        ),
        errorBorder: kenar.copyWith(borderSide: BorderSide(color: s.error)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: sekil,
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: sekil,
          minimumSize: const Size(48, 48),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: sekil,
          minimumSize: const Size(48, 48),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: base.chipTheme.copyWith(
        showCheckmark: false,
        side: BorderSide(color: s.outlineVariant),
        selectedColor: s.primaryContainer,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: s.surface,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: s.outlineVariant.withValues(alpha: .6),
        space: 1,
      ),
    );
  }
}

class OrtakTema extends StatelessWidget {
  const OrtakTema({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
    data: OrtakUi.tema(
      ModulUstBarBaglantisi.aktif?.tema?.call() ?? Theme.of(context),
    ),
    child: child,
  );
}

/// İçerik ve callback'ler ekranda kalır; başlık ve sabit alt alan ortaklaşır.
class OrtakSayfa extends StatelessWidget {
  const OrtakSayfa({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.floatingActionButtonLocation,
    this.bottomSheet,
    this.ustIslemler,
  });
  final PreferredSizeWidget? appBar;
  final List<Widget>? ustIslemler;
  final Widget? body, bottomNavigationBar, floatingActionButton, bottomSheet;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    final baslik = appBar;
    final islemler = baslik is ModulUstBar
        ? baslik.actions ?? const <Widget>[]
        : const <Widget>[];
    return OrtakTema(
      child: Builder(
        builder: (context) => Scaffold(
          appBar: baslik is ModulUstBar
              ? ModulUstBar(
                  title: baslik.title,
                  leading: baslik.leading,
                  centerTitle: baslik.centerTitle,
                  automaticallyImplyLeading: baslik.automaticallyImplyLeading,
                  kompakt: true,
                  actions: ustIslemler,
                  toolbarHeight:
                      (MediaQuery.textScalerOf(context).scale(18) * 1.2 +
                              MediaQuery.textScalerOf(context).scale(11) * 1.3 +
                              16)
                          .clamp(64, double.infinity),
                )
              : baslik,
          backgroundColor: backgroundColor,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          floatingActionButton: floatingActionButton,
          floatingActionButtonLocation: floatingActionButtonLocation,
          bottomSheet: bottomSheet,
          body: body == null ? null : SafeArea(top: false, child: body!),
          bottomNavigationBar: islemler.isEmpty && bottomNavigationBar == null
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bottomNavigationBar != null)
                      OrtakIslemCubugu(child: bottomNavigationBar),
                    if (islemler.isNotEmpty)
                      OrtakIslemCubugu(children: islemler),
                  ],
                ),
        ),
      ),
    );
  }
}

class OrtakIslemCubugu extends StatelessWidget {
  const OrtakIslemCubugu({super.key, this.children = const [], this.child});
  final List<Widget> children;
  final Widget? child;

  Widget _tasanIslem(BuildContext context, Widget islem) {
    if (islem is IconButton) {
      return ListTile(
        enabled: islem.onPressed != null,
        leading: islem.icon,
        title: Text(islem.tooltip ?? 'İşlem'),
        onTap: islem.onPressed == null
            ? null
            : () {
                Navigator.pop(context);
                islem.onPressed!();
              },
      );
    }
    if (islem is ButtonStyleButton) {
      return ListTile(
        enabled: islem.onPressed != null,
        title: islem.child,
        onTap: islem.onPressed == null
            ? null
            : () {
                Navigator.pop(context);
                islem.onPressed!();
              },
      );
    }
    return islem;
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Material(
      color: s.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: s.outlineVariant.withValues(alpha: .6)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: IconTheme.merge(
              data: IconThemeData(color: s.primary),
              child:
                  child ??
                  LayoutBuilder(
                    builder: (context, limits) => Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        for (final child in children.take(4))
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: limits.maxWidth,
                            ),
                            child: child,
                          ),
                        if (children.length > 4)
                          IconButton(
                            tooltip: 'Diğer modül işlemleri',
                            icon: const Icon(Icons.more_horiz),
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (c) => SingleChildScrollView(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Modül işlemleri'),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: children
                                          .skip(4)
                                          .map((w) => _tasanIslem(c, w))
                                          .toList(),
                                    ),
                                  ],
                                ),
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
  }
}

/// Satır kırılmasını yalnız sözcük sınırlarında yapar; uzun sözcük kısaltılır.
class OrtakBaslik extends StatelessWidget {
  const OrtakBaslik(
    this.metin, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.textAlign = TextAlign.start,
  });
  final String metin;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limits) {
      final stil = DefaultTextStyle.of(context).style.merge(style);
      final scaler = MediaQuery.textScalerOf(context);
      final satirlar = <String>[];
      var satir = '';
      double genislik(String t) => (TextPainter(
        text: TextSpan(text: t, style: stil),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout()).width;
      for (final kelime in metin.split(RegExp(r'\s+'))) {
        final aday = satir.isEmpty ? kelime : '$satir $kelime';
        if (satir.isNotEmpty && genislik(aday) > limits.maxWidth) {
          satirlar.add(satir);
          satir = kelime;
        } else {
          satir = aday;
        }
      }
      if (satir.isNotEmpty) satirlar.add(satir);
      return Tooltip(
        message: metin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: textAlign == TextAlign.center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < satirlar.length && i < maxLines; i++)
              Text(
                i == maxLines - 1 && satirlar.length > maxLines
                    ? '${satirlar[i]}…'
                    : satirlar[i],
                textAlign: textAlign,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: stil,
              ),
          ],
        ),
      );
    },
  );
}
