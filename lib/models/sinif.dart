class Sinif {
  final int sinifSubeId;
  final String sinif;
  final String? alan;

  Sinif({
    required this.sinifSubeId,
    required this.sinif,
    this.alan,
  });

  factory Sinif.fromJson(Map<String, dynamic> json) {
    return Sinif(
      sinifSubeId: json['sinifSubeId'] ?? 0,
      sinif: json['sinif'] ?? '',
      alan: json['alan'],
    );
  }
}