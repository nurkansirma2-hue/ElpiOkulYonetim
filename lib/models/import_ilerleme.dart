class ImportIlerleme {
  const ImportIlerleme(this.aciklama, {this.tamamlanan, this.toplam});
  final String aciklama;
  final int? tamamlanan, toplam;
  double? get oran => toplam != null && toplam! > 0 && tamamlanan != null
      ? (tamamlanan! / toplam!).clamp(0.0, 1.0)
      : null;
}
