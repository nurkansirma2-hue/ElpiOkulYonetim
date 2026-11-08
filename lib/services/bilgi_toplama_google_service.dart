import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bireysel_bilgi_toplama_service.dart';
import 'rehberlik_google_form_service.dart';

/// Genel bilgi formu soruları; rehberlik formunun soru/öğrenci akışını değiştirmez.
class BilgiToplamaTopluSilmeSonucu {
  BilgiToplamaTopluSilmeSonucu(this.basarili, this.kalan, List<String> hatalar)
    : hatalar = List.unmodifiable(hatalar);
  final int basarili, kalan;
  final List<String> hatalar;
}

class BilgiToplamaGoogleService {
  BilgiToplamaGoogleService({http.Client? client})
    : _client = client ?? http.Client(),
      _sahibi = client == null;
  final http.Client _client;
  final bool _sahibi;
  static const _kok = 'https://forms.googleapis.com/v1/forms';
  static const silmeScope = 'https://www.googleapis.com/auth/forms';
  void dispose() {
    if (_sahibi) _client.close();
  }

  Map<String, String> _headers(String token) {
    if (token.trim().isEmpty) {
      throw StateError('Google hesap bağlantısı gerekli.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=utf-8',
    };
  }

  Map<String, dynamic> _oku(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StateError(
        'Google Forms işlemi başarısız (HTTP ${r.statusCode}). Hesap iznini ve bağlantınızı kontrol edin.',
      );
    }
    final data = jsonDecode(utf8.decode(r.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Google yanıtı geçersiz.');
    }
    return data;
  }

  static Map<String, Object?> _item(Map<String, Object?> s) {
    final tur = s['VeriTuru'];
    // Tarih metin olarak istenir; Google'ın yerel tarih gösterimi veri sözleşmesini değiştirmez.
    final secenekler = tur == 'EvetHayir'
        ? ['Evet', 'Hayır']
        : jsonDecode(s['Secenekler'] as String) as List;
    final qid =
        s['GoogleSoruId'] as String? ??
        (s['Id'] as int).toRadixString(16).padLeft(8, '0');
    return {
      'itemId': qid,
      'title': s['Baslik'],
      if (tur == 'Tarih')
        'description': 'YYYY-AA-GG biçiminde yazın (örnek: 2026-10-22).',
      if (tur == 'Sayi') 'description': 'Yalnız sayı yazın.',
      'questionItem': {
        'question': {
          'questionId': qid,
          'required': s['Zorunlu'] == 1,
          if (tur == 'Secenek' || tur == 'EvetHayir')
            'choiceQuestion': {
              'type': s['AlanAnahtari'] == 'ogrenciSecimi'
                  ? 'DROP_DOWN'
                  : 'RADIO',
              'shuffle': false,
              'options': [
                for (final v in secenekler)
                  {'value': v is Map ? v['etiket'] : v},
              ],
            }
          else
            'textQuestion': {'paragraph': false},
        },
      },
    };
  }

  static void dogrula(
    Map<String, dynamic> remote,
    List<Map<String, Object?>> ss,
  ) {
    final items = remote['items'] as List? ?? [];
    if (items.length != ss.length) {
      throw StateError(
        'Google formundaki sorular kayıtlı formdan farklı. Soruları değiştirmeden mevcut formu kontrol edin.',
      );
    }
    for (var i = 0; i < ss.length; i++) {
      final beklenen = _item(ss[i]), gelen = items[i];
      if (gelen is! Map ||
          gelen['title'] != beklenen['title'] ||
          gelen['itemId'] != beklenen['itemId']) {
        throw StateError(
          'Google soru eşleştirmesi değişmiş. İşlem durduruldu.',
        );
      }
      final q = (gelen['questionItem'] as Map?)?['question'];
      final bq = (beklenen['questionItem'] as Map)['question'] as Map;
      if (q is! Map ||
          q['questionId'] != bq['questionId'] ||
          (q['required'] == true) != (bq['required'] == true)) {
        throw StateError('Google soru kimliği veya zorunluluğu değişmiş.');
      }
      if (bq.containsKey('choiceQuestion')) {
        final c = q['choiceQuestion'];
        final bc = bq['choiceQuestion'] as Map;
        if (c is! Map ||
            c['type'] != bc['type'] ||
            c['options'] is! List ||
            (c['options'] as List).any(
              (o) => o is! Map || o['isOther'] == true,
            ) ||
            jsonEncode(
                  (c['options'] as List).map((o) => o['value']).toList(),
                ) !=
                jsonEncode(
                  (bc['options'] as List).map((o) => o['value']).toList(),
                )) {
          throw StateError('Google seçenekleri değişmiş.');
        }
      } else if (q['textQuestion'] is! Map ||
          (q['textQuestion']['paragraph'] == true)) {
        throw StateError('Google soru türü değişmiş.');
      }
    }
  }

  Future<Map<String, dynamic>> durum(String token, String id) =>
      RehberlikGoogleFormService(
        client: _client,
      ).durumGetir(erisimBelirteci: token, googleFormId: id);

  Future<void> hazirla(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token, {
    String? kurtarilacakId,
  }) async {
    final headers = _headers(token);
    final f = await yerel.formGetir(b, id);
    final ss = await yerel.sorular(b, id);
    var gid = f['GoogleFormId'] as String?;
    if (f['Durum'] != 'Taslak') {
      await kontrolEt(yerel, b, id, token);
      return;
    }
    if (kurtarilacakId != null) {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(kurtarilacakId)) {
        throw const FormatException(
          'Google düzenleme adresindeki form kimliğini girin.',
        );
      }
      gid = kurtarilacakId;
      // Önce uzak soruları doğrula; ilgisiz formu yerel kayda kilitleme.
      final remote = await durum(token, gid);
      if ((remote['items'] as List? ?? []).isNotEmpty) dogrula(remote, ss);
      await yerel.googleTaslakKimliginiKaydet(b, id, gid);
    }
    if (gid == null) {
      await yerel.googleOlusturmayiBaslat(b, id);
      final created = _oku(
        await _client
            .post(
              Uri.parse('$_kok?unpublished=true'),
              headers: headers,
              body: jsonEncode({
                'info': {'title': f['Baslik']},
              }),
            )
            .timeout(const Duration(seconds: 30)),
      );
      gid = created['formId'] as String?;
      if (gid == null || gid.isEmpty) {
        throw StateError(
          'Google form kimliği alınamadı. Yeniden oluşturmadan hesabınızı kontrol edin.',
        );
      }
      try {
        await yerel.googleTaslakKimliginiKaydet(b, id, gid);
      } catch (e) {
        throw StateError(
          'Google formu oluşturuldu. Tekrar oluşturmayın; mevcut formu bağlayın. Form kimliği: $gid. Orijinal hata: $e',
        );
      }
    }
    var remote = await durum(token, gid);
    if ((remote['items'] as List? ?? []).isEmpty) {
      _oku(
        await _client
            .post(
              Uri.parse('$_kok/$gid:batchUpdate'),
              headers: headers,
              body: jsonEncode({
                'requests': [
                  for (var i = 0; i < ss.length; i++)
                    {
                      'createItem': {
                        'item': _item(ss[i]),
                        'location': {'index': i},
                      },
                    },
                ],
              }),
            )
            .timeout(const Duration(seconds: 30)),
      );
      remote = await durum(token, gid);
    }
    dogrula(remote, ss);
    await yerel.googleBagla(b, id, gid, {
      for (final s in ss)
        s['AlanAnahtari'] as String: (s['Id'] as int)
            .toRadixString(16)
            .padLeft(8, '0'),
    });
  }

  Future<Map<String, dynamic>> kontrolEt(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async {
    if (await yerel.bekleyenFormDuzenlemesi(b, id) != null) {
      throw StateError(
        'Bekleyen form düzenlemesi var. Listeden formu seçip Düzenle ile tamamlayın.',
      );
    }
    final f = await yerel.formGetir(b, id);
    final gid = f['GoogleFormId'] as String?;
    if (gid == null) throw StateError('Önce Google formunu hazırlayın.');
    final remote = await durum(token, gid);
    dogrula(remote, await yerel.sorular(b, id));
    return remote;
  }

  Future<bool> formdaYanitVar(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async {
    final bilgi = await yerel.formDuzenlemeBilgileri(b, id);
    if (bilgi['yanitVar'] == true) return true;
    final gid = (bilgi['form'] as Map)['GoogleFormId'] as String?;
    if (gid == null) return false;
    return (await RehberlikGoogleFormService(
      client: _client,
    ).yanitlariGetir(erisimBelirteci: token, googleFormId: gid)).isNotEmpty;
  }

  Future<void> formDuzenle(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token, {
    required Map<String, Object?> beklenenForm,
    required String baslik,
    List<BilgiToplamaSorusu>? sorular,
    String? hedefTuru,
    Set<int> ogrenciIdleri = const {},
    Set<int> sinifIdleri = const {},
  }) async {
    final gid = beklenenForm['GoogleFormId'] as String?;
    Map<String, dynamic>? yayin;
    if (gid != null) {
      final remote = await durum(token, gid);
      if (sorular != null && await formdaYanitVar(yerel, b, id, token)) {
        throw StateError(
          'Forma yanıt gelmiş. Düzenlemeyi yeniden açın; yalnız adını değiştirebilirsiniz.',
        );
      }
      yayin = (remote['publishSettings'] as Map?)?['publishState'] == null
          ? null
          : Map<String, dynamic>.from(
              remote['publishSettings']['publishState'] as Map,
            );
      if (sorular != null && yayin == null) {
        throw StateError('Google formu güvenli düzenleme için kapatılamıyor.');
      }
    }
    await yerel.formDuzenlemeHazirla(
      b,
      id,
      beklenenForm: beklenenForm,
      baslik: baslik,
      sorular: sorular,
      hedefTuru: hedefTuru,
      ogrenciIdleri: ogrenciIdleri,
      sinifIdleri: sinifIdleri,
      yayinDurumu: yayin,
    );
    await formDuzenlemeyiSurdur(yerel, b, id, token);
  }

  Future<void> _yayinDurumuKaydet(
    String gid,
    String token,
    Map<String, dynamic> state,
  ) async {
    _oku(
      await _client
          .post(
            Uri.parse('$_kok/${Uri.encodeComponent(gid)}:setPublishSettings'),
            headers: _headers(token),
            body: jsonEncode({
              'publishSettings': {
                'publishState': {
                  'isPublished': state['isPublished'] == true,
                  'isAcceptingResponses': state['isAcceptingResponses'] == true,
                },
              },
              'updateMask': 'publishState',
            }),
          )
          .timeout(const Duration(seconds: 30)),
    );
    final remote = await durum(token, gid);
    final gelen = (remote['publishSettings'] as Map?)?['publishState'];
    if (gelen is! Map ||
        (gelen['isPublished'] == true) != (state['isPublished'] == true) ||
        (gelen['isAcceptingResponses'] == true) !=
            (state['isAcceptingResponses'] == true)) {
      throw StateError(
        'Formun yayın durumu doğrulanamadı. Listeden Düzenle ile işlemi yeniden sürdürün.',
      );
    }
  }

  Future<void> formDuzenlemeyiSurdur(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async {
    final plan = await yerel.bekleyenFormDuzenlemesi(b, id);
    if (plan == null) return;
    final eski = plan['eski'] as Map, f = eski['form'] as Map;
    final gid = f['GoogleFormId'] as String?;
    final yapisal = plan['sorular'] != null;
    if (gid != null && plan['yerelKaydedildi'] != true) {
      var remote = await durum(token, gid);
      if (yapisal) {
        await _yayinDurumuKaydet(gid, token, {
          'isPublished': false,
          'isAcceptingResponses': false,
        });
        remote = await durum(token, gid);
        final state = (remote['publishSettings'] as Map?)?['publishState'];
        if (state is! Map ||
            state['isPublished'] == true ||
            state['isAcceptingResponses'] == true) {
          throw StateError(
            'Google formunun kapatıldığı doğrulanamadı; düzenleme bekliyor.',
          );
        }
        final yeni = (plan['sorular'] as List)
            .map((q) => Map<String, Object?>.from(q as Map))
            .toList();
        var zatenYeni = false;
        try {
          dogrula(remote, yeni);
          zatenYeni = true;
        } on StateError {
          /* İlk uygulama. */
        }
        final cevaplar = await RehberlikGoogleFormService(
          client: _client,
        ).yanitlariGetir(erisimBelirteci: token, googleFormId: gid);
        if (cevaplar.isNotEmpty && !zatenYeni) {
          // Sorulara henüz dokunulmadı. Yanıt gelmişse yalnız ad düzenlenebilir.
          await _yayinDurumuKaydet(
            gid,
            token,
            Map<String, dynamic>.from(plan['yayin'] as Map),
          );
          await yerel.formDuzenlemeyiBitir(b, id);
          throw StateError(
            'Forma yanıt geldi. Soru ve hedefler değiştirilmedi; yalnız adını değiştirebilirsiniz.',
          );
        }
        if (!zatenYeni) {
          final eskiSorular = (eski['sorular'] as List)
              .map((q) => Map<String, Object?>.from(q as Map))
              .toList();
          if ((remote['items'] as List? ?? []).isNotEmpty) {
            dogrula(remote, eskiSorular);
          }
          final items = remote['items'] as List? ?? [];
          _oku(
            await _client
                .post(
                  Uri.parse('$_kok/${Uri.encodeComponent(gid)}:batchUpdate'),
                  headers: _headers(token),
                  body: jsonEncode({
                    'requests': [
                      for (var i = items.length - 1; i >= 0; i--)
                        {
                          'deleteItem': {
                            'location': {'index': i},
                          },
                        },
                      for (var i = 0; i < yeni.length; i++)
                        {
                          'createItem': {
                            'item': _item(yeni[i]),
                            'location': {'index': i},
                          },
                        },
                      {
                        'updateFormInfo': {
                          'info': {'title': plan['baslik']},
                          'updateMask': 'title',
                        },
                      },
                    ],
                    if (remote['revisionId'] is String)
                      'writeControl': {
                        'requiredRevisionId': remote['revisionId'],
                      },
                  }),
                )
                .timeout(const Duration(seconds: 30)),
          );
        }
        remote = await durum(token, gid);
        dogrula(remote, yeni);
      }
      if ((remote['info'] as Map?)?['title'] != plan['baslik']) {
        _oku(
          await _client
              .post(
                Uri.parse('$_kok/${Uri.encodeComponent(gid)}:batchUpdate'),
                headers: _headers(token),
                body: jsonEncode({
                  'requests': [
                    {
                      'updateFormInfo': {
                        'info': {'title': plan['baslik']},
                        'updateMask': 'title',
                      },
                    },
                  ],
                }),
              )
              .timeout(const Duration(seconds: 30)),
        );
      }
      if (((await durum(token, gid))['info'] as Map?)?['title'] !=
          plan['baslik']) {
        throw StateError(
          'Google form adı doğrulanamadı; düzenlemeyi yeniden deneyin.',
        );
      }
    }
    await yerel.formDuzenlemeyiKaydet(b, id);
    if (gid != null && yapisal) {
      await _yayinDurumuKaydet(
        gid,
        token,
        Map<String, dynamic>.from(plan['yayin'] as Map),
      );
    }
    await yerel.formDuzenlemeyiBitir(b, id);
  }

  Future<String> yayinla(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async {
    await kontrolEt(yerel, b, id, token);
    final f = await yerel.formGetir(b, id);
    final m = await yerel.yonetim(b, id);
    if (f['Durum'] == 'Kapali' || m['arsiv'] == true) {
      throw StateError('Önce yanıt alımını açın.');
    }
    await RehberlikGoogleFormService(client: _client).formuYayinla(
      erisimBelirteci: token,
      googleFormId: f['GoogleFormId'] as String,
    );
    final link = paylasimBaglantisi(await kontrolEt(yerel, b, id, token));
    await yerel.yayinDurumuKaydet(b, id, f['GoogleFormId'] as String, true);
    return link;
  }

  static String paylasimBaglantisi(Map<String, dynamic> remote) {
    final state = (remote['publishSettings'] as Map?)?['publishState'] as Map?;
    final uri = Uri.tryParse(remote['responderUri']?.toString() ?? '');
    if (state?['isPublished'] != true ||
        state?['isAcceptingResponses'] != true ||
        uri == null ||
        uri.scheme != 'https' ||
        !{'docs.google.com', 'forms.gle'}.contains(uri.host)) {
      throw StateError(
        'Form henüz yayımlanmamış veya yanıtlara kapalı. Önce yayımlayın.',
      );
    }
    return uri.toString();
  }

  /// Kaynak modül kapsamı önce/sonra doğrulanır; yerel durum yalnız uzak doğrulamadan sonra değişir.
  Future<void> yanitAliminiAyarla(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
    bool acik,
  ) async {
    final f = await yerel.formGetir(b, id);
    final gid = f['GoogleFormId'] as String?;
    if (gid == null) throw StateError('Önce formu hazırlayın.');
    await kontrolEt(yerel, b, id, token);
    await googleYayinAyarla(token, gid, acik);
    await yerel.yayinDurumuKaydet(b, id, gid, acik);
  }

  Future<void> googleYayinAyarla(String token, String formId, bool acik) async {
    final remote = await durum(token, formId);
    final state = (remote['publishSettings'] as Map?)?['publishState'] as Map?;
    // Kapatma işlemi yayımlanmamış fotoğraflı bir formu yayımlamamalıdır.
    await _yayinDurumuKaydet(formId, token, {
      'isPublished': acik || state?['isPublished'] == true,
      'isAcceptingResponses': acik,
    });
  }

  Future<void> googleYanitSil(
    String deploymentId,
    String token,
    String formId,
    String responseId,
  ) => _googleYanitiSil(deploymentId, token, formId, responseId);

  Future<List<int>> yanitlariAl(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async {
    await kontrolEt(yerel, b, id, token);
    return yerel.googleYanitlariniAl(
      b,
      id,
      erisimBelirteci: token,
      google: RehberlikGoogleFormService(client: _client),
    );
  }

  Future<void> yanitiSil(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p,
    String token,
  ) async {
    final deploymentId = await yerel.silmeBaglantisi(b);
    if (!RegExp(r'^[a-zA-Z0-9_-]{10,300}$').hasMatch(deploymentId)) {
      throw StateError(
        'Google’dan silme kurulumu eksik. Form ekranındaki Google’dan silme ayarına API dağıtım kimliğini kaydedin.',
      );
    }
    await yerel.yanitiGoogleIleSil(
      b,
      p,
      googleSil: (formId, responseId) =>
          _googleYanitiSil(deploymentId, token, formId, responseId),
    );
  }

  Future<BilgiToplamaTopluSilmeSonucu> yanitlariTopluSil(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    BilgiToplamaSilmePlani plan,
    String token, {
    bool Function()? devamEt,
    void Function(int tamamlanan, int toplam)? ilerleme,
  }) async {
    final deploymentId = await yerel.silmeBaglantisi(b);
    if (!RegExp(r'^[a-zA-Z0-9_-]{10,300}$').hasMatch(deploymentId)) {
      throw StateError('Google’dan silme kurulumu eksik.');
    }
    var basarili = 0, denenen = 0;
    final hatalar = <String>[];
    for (final id in plan.googleYanitIdleri) {
      if (devamEt != null && !devamEt()) break;
      try {
        await yerel.topluSilmeYanitiSil(
          b,
          plan,
          id,
          googleSil: (fid, rid) =>
              _googleYanitiSil(deploymentId, token, fid, rid),
        );
        basarili++;
      } catch (e) {
        hatalar.add('Yanıt ${denenen + 1}: $e');
      }
      denenen++;
      ilerleme?.call(denenen, plan.toplam);
    }
    return BilgiToplamaTopluSilmeSonucu(
      basarili,
      plan.toplam - basarili,
      hatalar,
    );
  }

  Future<String> duzeltmeBaglantisi(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    BilgiToplamaOnizleme p,
    String token,
  ) async {
    final hedef = await yerel.duzeltmeHedefi(b, p);
    final deployment = await yerel.silmeBaglantisi(b);
    if (!RegExp(r'^[a-zA-Z0-9_-]{10,300}$').hasMatch(deployment)) {
      throw StateError('Google bağlantısı kurulumu eksik.');
    }
    final data = _oku(
      await _client
          .post(
            Uri.https('script.googleapis.com', '/v1/scripts/$deployment:run'),
            headers: _headers(token),
            body: jsonEncode({
              'function': 'okulYanitDuzenlemeBaglantisi',
              'parameters': [hedef['googleFormId'], hedef['responseId']],
              'devMode': false,
            }),
          )
          .timeout(const Duration(seconds: 60)),
    );
    final response = data['response'];
    final result = response is Map ? response['result'] : null;
    if (data['error'] != null ||
        data['done'] != true ||
        result is! Map ||
        result['protocol'] != 'okul-yanit-duzelt/v1' ||
        result['formId'] != hedef['googleFormId'] ||
        result['responseId'] != hedef['responseId']) {
      throw StateError(
        'Düzeltme bağlantısı alınamadı. Apps Script dağıtımını yeni sürüme güncelleyin.',
      );
    }
    final uri = Uri.tryParse(result['editUrl']?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'docs.google.com' ||
        !uri.path.startsWith('/forms/') ||
        !uri.queryParameters.containsKey('edit2') ||
        uri.queryParameters['edit2']!.isEmpty) {
      throw StateError('Google düzenleme bağlantısı doğrulanamadı.');
    }
    await yerel.duzeltmeHedefi(b, p);
    return uri.toString();
  }

  Future<void> formuSil(
    BireyselBilgiToplamaService yerel,
    BilgiToplamaOturumu b,
    int id,
    String token,
  ) async {
    await yerel.formuSil(
      b,
      id,
      googleTemizle: (gid) async {
        final deployment = await yerel.silmeBaglantisi(b);
        if (!RegExp(r'^[a-zA-Z0-9_-]{10,300}$').hasMatch(deployment)) {
          throw StateError('Google’dan silme kurulumu eksik.');
        }
        await durum(token, gid);
        _oku(
          await _client
              .post(
                Uri.parse(
                  '$_kok/${Uri.encodeComponent(gid)}:setPublishSettings',
                ),
                headers: _headers(token),
                body: jsonEncode({
                  'publishSettings': {
                    'publishState': {
                      'isPublished': false,
                      'isAcceptingResponses': false,
                    },
                  },
                  'updateMask': 'publishState',
                }),
              )
              .timeout(const Duration(seconds: 30)),
        );
        Future<void> kapaliKontrol() async {
          final remote = await durum(token, gid);
          final state = (remote['publishSettings'] as Map?)?['publishState'];
          if (state is! Map ||
              state['isAcceptingResponses'] == true ||
              state['isPublished'] == true) {
            throw StateError('Google formunun kapatıldığı doğrulanamadı.');
          }
        }

        await kapaliKontrol();
        final g = RehberlikGoogleFormService(client: _client);
        final yanitlar = await g.yanitlariGetir(
          erisimBelirteci: token,
          googleFormId: gid,
        );
        for (final y in yanitlar) {
          await _googleYanitiSil(
            deployment,
            token,
            gid,
            y['responseId'] as String,
          );
        }
        await kapaliKontrol();
        if ((await g.yanitlariGetir(
          erisimBelirteci: token,
          googleFormId: gid,
        )).isNotEmpty) {
          throw StateError(
            'Google’da yanıtlar kaldı. Form listede korunuyor; yeniden deneyin.',
          );
        }
      },
    );
  }

  Future<void> _googleYanitiSil(
    String deploymentId,
    String token,
    String formId,
    String responseId,
  ) async {
    final headers = _headers(token);
    final data = _oku(
      await _client
          .post(
            Uri.https('script.googleapis.com', '/v1/scripts/$deploymentId:run'),
            headers: headers,
            body: jsonEncode({
              'function': 'okulYanitSil',
              'parameters': [formId, responseId],
              'devMode': false,
            }),
          )
          .timeout(const Duration(seconds: 60)),
    );
    if (data['error'] != null) {
      throw StateError(
        'Google silme betiği tamamlanamadı. Apps Script dağıtımını, aynı Cloud projesini ve Google Forms iznini kontrol edin. Yanıt uygulamada korundu.',
      );
    }
    final response = data['response'];
    final result = response is Map ? response['result'] : null;
    if (data['done'] != true ||
        result is! Map ||
        result['protocol'] != 'okul-yanit-sil/v1' ||
        result['formId'] != formId ||
        result['responseId'] != responseId ||
        result['absent'] != true) {
      throw StateError(
        'Google silme sonucu doğrulanamadı. Yanıt uygulamada korundu; yeniden deneyebilirsiniz.',
      );
    }
    // Betiğin dönüşüne ek olarak, aynı hesaptan Forms API ile doğrula.
    // Önce form erişimini doğrula: formun 404 olması yanıt silindi demek değildir.
    await durum(token, formId);
    final g = RehberlikGoogleFormService(client: _client);
    // Google Forms API bazen silinen yanıtı kısa süre daha listeler.
    // Silme kesinleşmeden yerel yanıt kaydını asla kaldırma.
    const beklemeler = <Duration>[
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ];
    for (var deneme = 0; deneme < beklemeler.length; deneme++) {
      if (deneme > 0) await Future<void>.delayed(beklemeler[deneme]);
      final kontrol = await _client
          .get(
            Uri.parse(
              '$_kok/${Uri.encodeComponent(formId)}/responses/${Uri.encodeComponent(responseId)}',
            ),
            headers: {...headers, 'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 30));
      if (kontrol.statusCode == 404) {
        await durum(token, formId);
        return;
      }
      if (kontrol.statusCode != 200) {
        throw StateError(
          'Google silme doğrulaması başarısız (HTTP ${kontrol.statusCode}). Yerel kayıt korundu.',
        );
      }
      final rows = await g.yanitlariGetir(
        erisimBelirteci: token,
        googleFormId: formId,
      );
      if (!rows.any((r) => r['responseId'] == responseId)) {
        await durum(token, formId);
        return;
      }
    }
    throw StateError(
      'Silme betiği tamamlandı ancak yanıt Google Forms API listesinde hâlâ görünüyor. '
      '15 saniyelik tekrar kontrolünden sonra da yanıt doğrulanamadı. Yerel kayıt korundu. Google Forms üzerinden yanıtı kontrol edin ve daha sonra yeniden deneyin.',
    );
  }
}
