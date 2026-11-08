import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ogrenci_bilgi_formu.dart';

/// Google Forms API için, oturum açma ve SQLite kaydından bağımsız istemci.
/// Bu servis kendi başına ağ çağrısı yapmaz; çağıran kod geçerli OAuth
/// erişim belirtecini ve sınıf başına tek form kontrolünü sağlamalıdır.
class RehberlikGoogleFormService {
  RehberlikGoogleFormService({http.Client? client})
    : _client = client ?? http.Client(),
      _clientSahibi = client == null;

  final http.Client _client;
  final bool _clientSahibi;
  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      _client.get(uri, headers: headers).timeout(const Duration(seconds: 30));
  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) => _client
      .post(uri, headers: headers, body: body)
      .timeout(const Duration(seconds: 30));
  static const _kok = 'https://forms.googleapis.com/v1/forms';
  static const davetSorusu = 'Öğrenci davet kodu';
  static const ogrenciSecimSorusu = googleOgrenciSecimSorusu;

  /// Yayın durumu yerel taslak/aktif etiketinden tahmin edilmez.
  Future<Map<String, dynamic>> durumGetir({
    required String erisimBelirteci,
    required String googleFormId,
  }) async => _oku(
    await _get(
      Uri.parse('$_kok/${Uri.encodeComponent(googleFormId)}'),
      headers: {'Authorization': 'Bearer $erisimBelirteci'},
    ),
  );

  void dispose() {
    if (_clientSahibi) _client.close();
  }

  /// Form soru metinlerini mevcut RehberlikForm JSON anahtarlarıyla aynı tutar.
  /// Ek sorular, MEB soru sıralamasının sonuna eklenir.
  static List<String> sorulariHazirla(Iterable<String> ekSorular) {
    final sorular = <String>{ogrenciSecimSorusu, ...ogrenciBilgiFormuSorulari};
    for (final soru in ekSorular) {
      final temiz = soru.trim();
      if (temiz.isNotEmpty) sorular.add(temiz);
    }
    sorular.removeAll({...googleElleKimlikSorulari, davetSorusu});
    return List.unmodifiable(sorular);
  }

  /// Google tarafından üretilen ID'ler mevcut soru metinlerine eşlenir.
  /// Dönen değer SQLite RehberlikGoogleForm.SoruEslemeleri alanına
  /// jsonEncode ile yazılabilecek bir haritadır.
  Future<GoogleRehberlikFormSonucu> formOlustur({
    required String erisimBelirteci,
    required String baslik,
    required List<String> sorular,
    required List<String> ogrenciSecenekleri,
    required Future<void> Function(String formId) onFormOlusturuldu,
  }) async {
    if (erisimBelirteci.trim().isEmpty) {
      throw StateError('Google hesap yetkilendirmesi gerekiyor.');
    }
    if (ogrenciSecenekleri.isEmpty ||
        ogrenciSecenekleri.toSet().length != ogrenciSecenekleri.length) {
      throw const FormatException('Öğrenci listesi boş veya tekrar içeriyor.');
    }
    if (baslik.trim().isEmpty ||
        sorular.isEmpty ||
        sorular.any((s) => s.trim().isEmpty) ||
        sorular.toSet().length != sorular.length) {
      throw ArgumentError('Form başlığı ve benzersiz sorular gerekli.');
    }

    final headers = <String, String>{
      'Authorization': 'Bearer $erisimBelirteci',
      'Content-Type': 'application/json; charset=utf-8',
    };
    final olustur = await _post(
      Uri.parse(_kok),
      headers: headers,
      body: jsonEncode({
        'info': {'title': baslik.trim()},
      }),
    );
    final yeni = _oku(olustur);
    final formId = yeni['formId']?.toString();
    if (formId == null || formId.isEmpty) {
      throw const FormatException('Google Forms kimlik döndürmedi.');
    }

    // Kimlik, soru isteklerinden önce SQLite'a yazılır.
    try {
      await onFormOlusturuldu(formId);
    } catch (e) {
      throw StateError(
        'Google Form oluşturuldu ancak SQLite kaydına bağlanamadı. '
        'Aynı sınıf için tekrar form açmayın. Google Form kimliği: $formId. '
        'Mevcut formu bağla seçeneğiyle kurtarabilirsiniz. '
        'Orijinal hata: $e',
      );
    }

    // Form Google tarafında artık oluşmuştur. Bağlantı kesilirse istemci
    // yeniden form oluşturmak yerine bu kimliği kurtarmalıdır.
    try {
      final istekler = <Map<String, Object?>>[];
      for (var i = 0; i < sorular.length; i++) {
        istekler.add({
          'createItem': {
            'item': _soru(sorular[i], ogrenciSecenekleri),
            'location': {'index': i},
          },
        });
      }
      final yanit = await _post(
        Uri.parse('$_kok/${Uri.encodeComponent(formId)}:batchUpdate'),
        headers: headers,
        body: jsonEncode({
          'requests': istekler,
          'includeFormInResponse': false,
        }),
      );
      final sonuc = _oku(yanit);
      final cevaplar = sonuc['replies'];
      if (cevaplar is! List || cevaplar.length != sorular.length) {
        throw const FormatException('Google soru kimlikleri eksik.');
      }
      final eslemeler = <String, Map<String, String>>{};
      for (var i = 0; i < sorular.length; i++) {
        final item = (cevaplar[i] as Map)['createItem'] as Map?;
        final id = item?['itemId']?.toString();
        final questionIds = item?['questionId'] as List?;
        if (id == null ||
            id.isEmpty ||
            questionIds == null ||
            questionIds.isEmpty ||
            questionIds.first.toString().isEmpty) {
          throw const FormatException('Google soru eşleştirmesi eksik.');
        }
        eslemeler[sorular[i]] = {
          'itemId': id,
          'questionId': questionIds.first.toString(),
        };
      }
      return GoogleRehberlikFormSonucu(formId, eslemeler);
    } catch (hata) {
      throw StateError(
        'Google Form oluşturuldu ancak soruların tamamlandığı doğrulanamadı. '
        'Tekrar oluşturmayın; önce Google Forms hesabınızda $formId '
        'kimlikli formu kontrol edin. Orijinal hata: $hata',
      );
    }
  }

  static Map<String, Object?> _soru(String baslik, List<String> ogrenciler) => {
    'title': baslik,
    'questionItem': {
      'question': {
        'required': baslik == ogrenciSecimSorusu,
        if (baslik == ogrenciSecimSorusu)
          'choiceQuestion': {
            'type': 'DROP_DOWN',
            'shuffle': false,
            'options': [
              for (final s in ogrenciler) {'value': s},
            ],
          }
        else
          'textQuestion': {'paragraph': true},
      },
    },
  };

  /// Öğrenci seçeneklerini günceller; tekrar sorulan dört kimlik alanını kaldırır.
  /// Diğer soruların kimlikleri ve eski davet sorusu korunur.
  Future<GoogleRehberlikFormSonucu> ogrenciListesiniGuncelle({
    required String erisimBelirteci,
    required String googleFormId,
    required List<String> secenekler,
  }) async {
    if (secenekler.isEmpty || secenekler.toSet().length != secenekler.length) {
      throw const FormatException('Öğrenci listesi boş veya çakışıyor.');
    }
    final form = await durumGetir(
      erisimBelirteci: erisimBelirteci,
      googleFormId: googleFormId,
    );
    if (form['formId'] != googleFormId) {
      throw StateError('Google Form kaydı uyuşmuyor.');
    }
    final items = List<Map<String, dynamic>>.from(form['items'] as List? ?? []);
    final indexes = [
      for (var i = 0; i < items.length; i++)
        if (items[i]['title'] == ogrenciSecimSorusu) i,
    ];
    if (indexes.length > 1) {
      throw StateError(
        'Öğrenci seçim sorusu birden fazla. Formu kontrol edin.',
      );
    }
    final requests = <Map<String, Object?>>[];
    final yeni = indexes.isEmpty;
    if (yeni) {
      requests.add({
        'createItem': {
          'item': _soru(ogrenciSecimSorusu, secenekler),
          'location': {'index': 0},
        },
      });
    } else {
      final index = indexes.single;
      final item = items[index];
      final question = (item['questionItem'] as Map?)?['question'] as Map?;
      final choice = question?['choiceQuestion'] as Map?;
      if (choice?['type'] != 'DROP_DOWN') {
        throw StateError(
          'Öğrenci seçim sorusunun türü farklı. Eski yanıtları korumak için dönüştürme durduruldu.',
        );
      }
      final onceki = (choice?['options'] as List? ?? [])
          .map((o) => o['value'])
          .toList();
      if (jsonEncode(onceki) != jsonEncode(secenekler) ||
          question?['required'] != true) {
        requests.add({
          'updateItem': {
            'item': {
              'itemId': item['itemId'],
              'questionItem': {
                'question': {
                  'questionId': question?['questionId'],
                  'required': true,
                  'choiceQuestion': {
                    'options': [
                      for (final s in secenekler) {'value': s},
                    ],
                  },
                },
              },
            },
            'location': {'index': index},
            'updateMask':
                'questionItem.question.choiceQuestion.options,questionItem.question.required',
          },
        });
      }
    }
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item['title'] != davetSorusu) {
        continue;
      }
      final q = (item['questionItem'] as Map?)?['question'] as Map?;
      if (q?['required'] != true) continue;
      requests.add({
        'updateItem': {
          'item': {
            'itemId': item['itemId'],
            'questionItem': {
              'question': {'questionId': q?['questionId'], 'required': false},
            },
          },
          'location': {'index': i + (yeni ? 1 : 0)},
          'updateMask': 'questionItem.question.required',
        },
      });
    }
    final silinecekler = [
      for (var i = 0; i < items.length; i++)
        if (googleElleKimlikSorulari.contains(items[i]['title'])) i,
    ];
    // İndeksler silme sırasında kaymasın; seçim yeni eklendiyse +1 uygula.
    for (final index in silinecekler.reversed) {
      requests.add({
        'deleteItem': {
          'location': {'index': index + (yeni ? 1 : 0)},
        },
      });
    }
    final secimIndex = yeni
        ? 0
        : indexes.single - silinecekler.where((i) => i < indexes.single).length;
    if (!yeni && secimIndex != 0) {
      requests.add({
        'moveItem': {
          'originalLocation': {'index': secimIndex},
          'newLocation': {'index': 0},
        },
      });
    }
    if (requests.isNotEmpty) {
      _oku(
        await _post(
          Uri.parse('$_kok/${Uri.encodeComponent(googleFormId)}:batchUpdate'),
          headers: {
            'Authorization': 'Bearer $erisimBelirteci',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode({
            'requests': requests,
            if (form['revisionId'] is String)
              'writeControl': {'requiredRevisionId': form['revisionId']},
          }),
        ),
      );
    }
    return mevcutFormuOku(
      erisimBelirteci: erisimBelirteci,
      googleFormId: googleFormId,
    );
  }

  /// Daha önce oluşturulan formu Google'dan sorgular. Yarım kalmış
  /// batchUpdate işlemini tahmin ederek tekrarlamaz.
  Future<GoogleRehberlikFormSonucu> mevcutFormuOku({
    required String erisimBelirteci,
    required String googleFormId,
  }) async {
    if (erisimBelirteci.trim().isEmpty || googleFormId.trim().isEmpty) {
      throw const FormatException('Google yetkisi veya form kimliği eksik.');
    }
    final yanit = await _get(
      Uri.parse('$_kok/${Uri.encodeComponent(googleFormId)}'),
      headers: {'Authorization': 'Bearer $erisimBelirteci'},
    );
    final form = _oku(yanit);
    if (form['formId'] != googleFormId) {
      throw const FormatException('Beklenen Google Form bulunamadı.');
    }
    final eslemeler = <String, Map<String, String>>{};
    for (final raw in (form['items'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final title = raw['title']?.toString() ?? '';
      final id = raw['itemId']?.toString() ?? '';
      final q = raw['questionItem'];
      if (q == null) continue; // Bölüm başlıkları cevap anahtarı değildir.
      final questionId = q is Map && q['question'] is Map
          ? (q['question'] as Map)['questionId']?.toString() ?? ''
          : '';
      if (title.isEmpty ||
          id.isEmpty ||
          questionId.isEmpty ||
          eslemeler.containsKey(title)) {
        throw const FormatException('Google Form soruları eşleştirilemiyor.');
      }
      eslemeler[title] = {'itemId': id, 'questionId': questionId};
    }
    return GoogleRehberlikFormSonucu(
      googleFormId,
      eslemeler,
      itemSayisi: (form['items'] as List? ?? const []).length,
    );
  }

  /// Sadece Google üzerinde bulunmadığı doğrulanan soruları ekler.
  /// Her çağrıdan sonra form yeniden okunur: ağ kopması sonrasında yeniden
  /// oluşturma, doğrulanmamış eksik listeye göre yapılmaz.
  Future<GoogleRehberlikFormSonucu> eksikSorulariTamamla({
    required String erisimBelirteci,
    required String googleFormId,
    required List<String> sorular,
  }) async {
    var mevcut = await mevcutFormuOku(
      erisimBelirteci: erisimBelirteci,
      googleFormId: googleFormId,
    );
    final eksik = sorular
        .where((s) => !mevcut.soruEslemeleri.containsKey(s))
        .toList();
    if (eksik.isEmpty) return mevcut;
    final request = <Map<String, Object?>>[];
    var index = mevcut.itemSayisi;
    for (final soru in eksik) {
      request.add({
        'createItem': {
          'item': {
            'title': soru,
            'questionItem': {
              'question': {
                'required': soru == davetSorusu,
                'textQuestion': {'paragraph': true},
              },
            },
          },
          'location': {'index': index++},
        },
      });
    }
    final yanit = await _post(
      Uri.parse('$_kok/${Uri.encodeComponent(googleFormId)}:batchUpdate'),
      headers: {
        'Authorization': 'Bearer $erisimBelirteci',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({'requests': request}),
    );
    _oku(yanit);
    mevcut = await mevcutFormuOku(
      erisimBelirteci: erisimBelirteci,
      googleFormId: googleFormId,
    );
    if (sorular.any((s) => !mevcut.soruEslemeleri.containsKey(s))) {
      throw StateError(
        'Google Form eksik sorularla kaldı; yeniden kontrol edin.',
      );
    }
    return mevcut;
  }

  /// Yalnız öğretmenin açık paylaşım onayından sonra çağrılır.
  /// Google Forms 2026 itibarıyla API formlarını yayınlanmamış açar.
  Future<void> formuYayinla({
    required String erisimBelirteci,
    required String googleFormId,
  }) async {
    if (erisimBelirteci.trim().isEmpty || googleFormId.trim().isEmpty) {
      throw const FormatException('Google Forms yetkisi veya kimliği eksik.');
    }
    _oku(
      await _post(
        Uri.parse(
          '$_kok/${Uri.encodeComponent(googleFormId)}:setPublishSettings',
        ),
        headers: {
          'Authorization': 'Bearer $erisimBelirteci',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'publishSettings': {
            'publishState': {'isPublished': true, 'isAcceptingResponses': true},
          },
          'updateMask': 'publishState',
        }),
      ),
    );
  }

  /// Yalnız Google'ın döndürdüğü gerçek cevaplama bağlantısını kullan.
  Future<String> cevaplamaBaglantisiGetir({
    required String erisimBelirteci,
    required String googleFormId,
  }) async {
    final yanit = _oku(
      await _get(
        Uri.parse('$_kok/${Uri.encodeComponent(googleFormId)}'),
        headers: {'Authorization': 'Bearer $erisimBelirteci'},
      ),
    );
    final adres = yanit['responderUri']?.toString() ?? '';
    if (!adres.startsWith('https://')) {
      throw StateError(
        'Form cevaplama bağlantısı henüz kullanıma hazır değil.',
      );
    }
    return adres;
  }

  /// Yanıtlar RAM'de kalır; Google cevapları ön onay olmadan SQLite'a
  /// yazılmaz. Sayfalama tüm sonuçlar bitene kadar devam eder.
  Future<List<Map<String, dynamic>>> yanitlariGetir({
    required String erisimBelirteci,
    required String googleFormId,
  }) async {
    if (erisimBelirteci.trim().isEmpty || googleFormId.trim().isEmpty) {
      throw const FormatException('Google yetkisi veya form kimliği eksik.');
    }
    final bulunan = <String, Map<String, dynamic>>{};
    String? sayfa;
    do {
      final uri =
          Uri.parse(
            '$_kok/${Uri.encodeComponent(googleFormId)}/responses',
          ).replace(
            queryParameters: {
              'pageSize': '500',
              if (sayfa != null) 'pageToken': sayfa,
            },
          );
      final yanit = _oku(
        await _get(uri, headers: {'Authorization': 'Bearer $erisimBelirteci'}),
      );
      for (final item in yanit['responses'] as List? ?? const []) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Google yanıtı biçimi geçersiz.');
        }
        final id = item['responseId']?.toString() ?? '';
        if (id.isEmpty) {
          throw const FormatException('Google yanıt kimliği eksik.');
        }
        bulunan[id] = item;
      }
      sayfa = yanit['nextPageToken']?.toString();
      if (sayfa == '') sayfa = null;
    } while (sayfa != null);
    return List.unmodifiable(bulunan.values);
  }

  /// Cevap anahtarı Google questionId; SQLite anahtarı mevcut soru metni.
  /// Çoklu değerler/yanıt türleri açık onay öncesi otomatik birleştirilmez.
  static Map<String, String> yanitiEsle(
    Map<String, dynamic> yanit,
    Map<String, Map<String, String>> soruEslemeleri,
  ) {
    final cevap = yanit['answers'];
    if (cevap is! Map) {
      throw const FormatException('Form yanıtı boş veya geçersiz.');
    }
    final sonuc = <String, String>{};
    for (final entry in soruEslemeleri.entries) {
      final id = entry.value['questionId'];
      if (id == null) continue;
      final veri = cevap[id];
      if (veri == null) continue;
      if (veri is! Map || veri['textAnswers'] is! Map) {
        throw const FormatException('Desteklenmeyen Google yanıt türü.');
      }
      final values = (veri['textAnswers'] as Map)['answers'];
      if (values is! List ||
          values.length != 1 ||
          values.single is! Map ||
          values.single['value'] is! String) {
        throw const FormatException('Bir soruya birden fazla cevap geldi.');
      }
      sonuc[entry.key] = values.single['value'] as String;
    }
    return Map.unmodifiable(sonuc);
  }

  static Map<String, dynamic> _oku(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Google Forms isteği başarısız (HTTP ${response.statusCode}). '
        'Kimlik doğrulama ve Google Forms API iznini kontrol edin.',
      );
    }
    final veri = jsonDecode(utf8.decode(response.bodyBytes));
    if (veri is! Map<String, dynamic>) {
      throw const FormatException('Google Forms yanıt biçimi geçersiz.');
    }
    return veri;
  }
}

class GoogleRehberlikFormSonucu {
  GoogleRehberlikFormSonucu(
    this.googleFormId,
    Map<String, Map<String, String>> eslemeler, {
    int? itemSayisi,
  }) : itemSayisi = itemSayisi ?? eslemeler.length,
       soruEslemeleri = Map.unmodifiable(
         eslemeler.map(
           (k, v) => MapEntry(k, Map<String, String>.unmodifiable(v)),
         ),
       );

  final String googleFormId;
  final int itemSayisi;
  final Map<String, Map<String, String>> soruEslemeleri;
}
