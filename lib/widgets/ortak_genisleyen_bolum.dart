import 'package:flutter/material.dart';

/// Ana sayfadaki bölüm başlığı: tema rengi ve çift ok bütün ekranlarda aynıdır.
class OrtakBolumBasligi extends StatelessWidget {
  const OrtakBolumBasligi({
    super.key,
    required this.title,
    required this.acik,
    required this.onToggle,
    this.leading,
    this.subtitle,
    this.padding,
  });
  final Widget title;
  final Widget? leading, subtitle;
  final bool acik;
  final VoidCallback? onToggle;
  final EdgeInsetsGeometry? padding;
  Widget _baslikRengi(Widget w, Color renk) {
    if (w is Text && w.data != null) {
      return Text(w.data!,key:w.key,style:(w.style??const TextStyle()).copyWith(color:renk),
        maxLines:w.maxLines??2,overflow:w.overflow??TextOverflow.ellipsis,textAlign:w.textAlign,
        textScaler:w.textScaler,semanticsLabel:w.semanticsLabel);
    }
    return w;
  }
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top:const Radius.circular(12),bottom:Radius.circular(acik?0:12)),
      child: Material(
      color: c.primary,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.primary, c.primary.withValues(alpha: .85)],
          ),
        ),
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding:
                padding ??
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: IconTheme(
              data: IconThemeData(color: c.onPrimary),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  color: c.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
                child: Row(
                  children: [
                    if (leading != null) ...[
                      if (leading is Icon) Icon((leading! as Icon).icon,key:leading!.key,
                        color:c.onPrimary,size:(leading! as Icon).size,semanticLabel:(leading! as Icon).semanticLabel)
                      else leading!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _baslikRengi(title,c.onPrimary),
                          if (subtitle != null)
                            DefaultTextStyle(
                              style: Theme.of(context).textTheme.bodySmall!
                                  .copyWith(color: c.onPrimary),
                              child: _baslikRengi(subtitle!,c.onPrimary),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: acik ? 'Daralt' : 'Genişlet',
                      onPressed: onToggle,
                      icon: Icon(
                        acik
                            ? Icons.keyboard_double_arrow_up
                            : Icons.keyboard_double_arrow_down,
                        color: c.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

/// Kapanırken değerleri koruma ve PageStorage davranışı mevcut bölümlerle uyumludur.
class OrtakGenisleyenBolum extends StatefulWidget {
  const OrtakGenisleyenBolum({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.children = const [],
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.onExpansionChanged,
    this.tilePadding,
    this.childrenPadding,
    this.dense,
    this.minTileHeight,
  });
  final Widget title;
  final Widget? leading, subtitle;
  final List<Widget> children;
  final bool initiallyExpanded, maintainState;
  final ValueChanged<bool>? onExpansionChanged;
  final EdgeInsetsGeometry? tilePadding, childrenPadding;
  final bool? dense;
  final double? minTileHeight;
  @override
  State<OrtakGenisleyenBolum> createState() => _OrtakGenisleyenBolumState();
}

class _OrtakGenisleyenBolumState extends State<OrtakGenisleyenBolum> {
  final _controller = ExpansibleController();
  late bool _acik = widget.initiallyExpanded;
  bool _okundu = false;
  @override
  void initState() {
    super.initState();
    _controller.addListener(_degisim);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_okundu) {
      final kayit = widget.key == null
          ? null
          : PageStorage.maybeOf(
              context,
            )?.readState(context, identifier: widget.key);
      _acik = kayit is bool ? kayit : widget.initiallyExpanded;
      if (_acik) _controller.expand();
      _okundu = true;
    }
  }

  void _degisim() {
    if (!_okundu || !mounted) return;
    setState(() => _acik = _controller.isExpanded);
    if (widget.key != null) {
      PageStorage.maybeOf(
        context,
      )?.writeState(context, _acik, identifier: widget.key);
    }
    widget.onExpansionChanged?.call(_acik);
  }

  @override
  void dispose() {
    _controller.removeListener(_degisim);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Expansible(
    controller: _controller,
    maintainState: widget.maintainState,
    animationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 220),
            curve: Curves.easeInOut,
          ),
    headerBuilder: (ctx, animation) => Semantics(
      expanded: _acik,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.minTileHeight ?? 0),
        child: OrtakBolumBasligi(
          title: widget.title,
          leading: widget.leading,
          subtitle: widget.subtitle,
          acik: _acik,
          onToggle: () {
            if (_controller.isExpanded) {
              _controller.collapse();
            } else {
              _controller.expand();
            }
          },
          padding:
              widget.tilePadding ??
              (widget.dense == true
                  ? const EdgeInsets.symmetric(horizontal: 12)
                  : null),
        ),
      ),
    ),
    bodyBuilder: (ctx, animation) => Padding(
      padding: widget.childrenPadding ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.children,
      ),
    ),
  );
}
