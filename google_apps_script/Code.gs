/** API yürütülebilir dağıtım; çağıran kullanıcının Google Forms yetkisiyle çalışır. */
function okulYanitSil(formId, responseId, expected) {
  if (typeof formId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(formId) ||
      typeof responseId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(responseId)) {
    throw new Error('Form veya yanıt kimliği geçersiz.');
  }
  // Yeni akış yalnız aynı servisten okunan gerçek yanıt kimliğiyle çalışır.
  // Eski iki parametreli sözleşme mevcut kullanıcılar için korunur.
  if (expected !== undefined) return okulYanitSilDogrudan_(formId, responseId, expected);
  const lock = LockService.getUserLock();
  lock.waitLock(10000);
  try {
    const form = FormApp.openById(formId);
    // Kesin yanıt kimliği kullanılır; ad, okul no veya sıra ile silme yapılmaz.
    if (form.getId() !== formId) throw new Error('Form kimliği eşleşmedi.');
    // getResponse(id) bazı Google formlarında "Invalid data updating form"
    // hatası üretebilir. Listeyi okuyup yalnız birebir kimliği eşleşeni seç.
    let responses;
    try {
      responses = form.getResponses();
    } catch (e) {
      throw new Error('Google Forms yanıt listesi okunamadı; silme yapılmadı: ' + e.message);
    }
    const matching = responses.filter(r => r.getId() === responseId);
    if (matching.length !== 1) {
      throw new Error(
        'Yanıt kimliği bu formun yanıt listesiyle birebir eşleşmedi (eşleşme: ' +
        matching.length + '); silme yapılmadı.'
      );
    }
    form.deleteResponse(responseId);
    // Silme betiği tek başına yeterli değildir; Flutter ayrıca Forms API 404 doğrular.
    const absent = !form.getResponses().some(r => r.getId() === responseId);
    if (!absent) throw new Error('Yanıtın silindiği doğrulanamadı.');
    return {
      protocol: 'okul-yanit-sil/v1',
      formId: formId,
      responseId: responseId,
      absent: true,
      deleted: true,
      implementation: 'exact-response-2026-11-19'
    };
  } finally {
    lock.releaseLock();
  }
}

/** Salt okunur, tam liste. REST kimliği tahmin edilmez veya dönüştürülmez. */
function okulYanitlariOku(formId) {
  if (typeof formId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(formId)) {
    throw new Error('Form kimliği geçersiz.');
  }
  const form = FormApp.openById(formId);
  if (form.getId() !== formId) throw new Error('Form kimliği eşleşmedi.');
  const first = okulYanitListesi_(form, formId);
  // Sayfalama yoktur: FormApp.getResponses tüm listeyi döndürür. Okuma
  // sırasında yeni yanıt veya düzenleme varsa karışık bir görüntü yayımlanmaz.
  const second = okulYanitListesi_(form, formId);
  if (okulYanitKanonik_(first) !== okulYanitKanonik_(second)) {
    throw new Error('Google yanıtları okunurken değişti. Liste tamamlanamadı.');
  }
  return {protocol: 'okul-yanitlar/v2', implementation: 'native-response-2026-11-20',
    formId: formId, complete: true, count: first.length, responses: first};
}

function okulYanitListesi_(form, formId) {
  const responses = form.getResponses();
  if (!Array.isArray(responses) || responses.length > 5000) {
    throw new Error('Tam yanıt listesi güvenli sınırda okunamadı.');
  }
  const seen = new Set();
  const snapshots = responses.map(r => {
    const snapshot = okulYanitAnlik_(r, formId);
    if (seen.has(snapshot.responseId)) throw new Error('Google yanıt kimliği tekrarlı.');
    seen.add(snapshot.responseId);
    return snapshot;
  });
  if (JSON.stringify(snapshots).length > 5000000) throw new Error('Yanıt listesi çok büyük.');
  return snapshots.sort((a, b) => a.responseId < b.responseId ? -1 : a.responseId > b.responseId ? 1 : 0);
}

function okulYanitAnlik_(response, formId) {
  const responseId = response.getId();
  const timestamp = response.getTimestamp();
  if (typeof responseId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(responseId) ||
      !timestamp || isNaN(timestamp.getTime())) throw new Error('Yanıt kimliği veya zamanı geçersiz.');
  const seen = new Set();
  const answers = response.getItemResponses().map(answer => {
    const item = answer.getItem();
    const itemId = String(item.getId());
    const title = item.getTitle();
    const raw = answer.getResponse();
    const values = Array.isArray(raw) ? raw.slice() : [raw];
    if (seen.has(itemId) || typeof title !== 'string' || title.length > 1000 ||
        values.length > 100 || values.some(v => typeof v !== 'string' || v.length > 10000)) {
      throw new Error('Yanıt soruları veya cevap türü desteklenmiyor.');
    }
    seen.add(itemId);
    return {itemId: itemId, title: title, values: values};
  });
  const snapshot = {source: 'apps-script/v2', formId: formId, responseId: responseId,
    submittedTime: timestamp.toISOString(), answers: answers};
  if (JSON.stringify(snapshot).length > 1000000) throw new Error('Yanıt boyutu çok büyük.');
  return snapshot;
}

function okulYanitKanonik_(value) {
  if (Array.isArray(value)) return '[' + value.map(okulYanitKanonik_).join(',') + ']';
  if (value !== null && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + okulYanitKanonik_(value[k])).join(',') + '}';
  }
  return JSON.stringify(value);
}

function okulYanitSilDogrudan_(formId, responseId, expected) {
  if (!expected || expected.source !== 'apps-script/v2' || expected.formId !== formId ||
      expected.responseId !== responseId || !Array.isArray(expected.answers) ||
      JSON.stringify(expected).length > 1000000) throw new Error('Okunan yanıt anlık görüntüsü geçersiz.');
  const lock = LockService.getUserLock();
  lock.waitLock(10000);
  try {
    const form = FormApp.openById(formId);
    if (form.getId() !== formId) throw new Error('Form kimliği eşleşmedi.');
    const before = okulYanitListesi_(form, formId);
    const matches = before.filter(r => r.responseId === responseId);
    if (matches.length === 1) {
      if (okulYanitKanonik_(matches[0]) !== okulYanitKanonik_(expected)) {
        throw new Error('Seçilen yanıt değişti. Silme yapılmadı.');
      }
      // Bekleme/okuma sırasında düzenlenmiş bir cevabı silmeden önce tekrar oku.
      const current = okulYanitListesi_(form, formId).filter(r => r.responseId === responseId);
      if (current.length !== 1 || okulYanitKanonik_(current[0]) !== okulYanitKanonik_(expected)) {
        throw new Error('Seçilen yanıt değişti. Silme yapılmadı.');
      }
      form.deleteResponse(responseId);
    }
    const after = okulYanitListesi_(form, formId);
    if (after.some(r => r.responseId === responseId)) throw new Error('Yanıtın silindiği doğrulanamadı.');
    return {protocol: 'okul-yanit-sil/v2', implementation: 'native-response-2026-11-20',
      formId: formId, responseId: responseId, absent: true, deleted: matches.length === 1};
  } finally {
    lock.releaseLock();
  }
}

/** Yalnız salt okunur tanı: hiçbir yanıt kimliği, cevap veya kişisel bilgi döndürmez. */
function okulYanitKimlikTani(formId, responseId, restCreateTime, restAnswerValues) {
  if (typeof formId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(formId) ||
      typeof responseId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(responseId)) {
    throw new Error('Form veya yanıt kimliği geçersiz.');
  }
  const form = FormApp.openById(formId);
  if (form.getId() !== formId) throw new Error('Form kimliği eşleşmedi.');
  const responses = form.getResponses();
  const matches = responses.filter(r => r.getId() === responseId).length;
  // Saat yalnız salt okunur aday tespiti içindir; silme hedefi olarak kullanılmaz.
  // Yanıt içeriği, öğrenci bilgisi veya alternatif kimlik dışarı verilmez.
  let timestampMatches = null;
  if (typeof restCreateTime === 'string' && restCreateTime.length <= 80) {
    const time = new Date(restCreateTime);
    if (!isNaN(time.getTime())) {
      timestampMatches = responses.filter(r => {
        const submitted = r.getTimestamp();
        return submitted && typeof submitted.getTime === 'function' && submitted.getTime() === time.getTime();
      }).length;
    }
  }
  // Soru kimliği dönüşümü henüz kanıtlanmadığından bu yalnız aday analizidir.
  // Cevaplar hiçbir zaman döndürülmez, loglanmaz veya silme hedefi yapılmaz.
  let contentMatches = null;
  let timeAndContentMatches = null;
  const expected = okulYanitDegerleri_(restAnswerValues);
  if (expected !== null) {
    let matchesByContent = 0;
    let matchesByBoth = 0;
    for (const r of responses) {
      const actual = okulYanitDegerleri_(
        r.getItemResponses().map(item => item.getResponse())
      );
      if (actual === null || JSON.stringify(actual) !== JSON.stringify(expected)) continue;
      matchesByContent++;
      if (typeof restCreateTime === 'string' && restCreateTime.length <= 80) {
        const date = new Date(restCreateTime);
        const timestamp = r.getTimestamp();
        if (!isNaN(date.getTime()) && timestamp &&
            typeof timestamp.getTime === 'function' &&
            timestamp.getTime() === date.getTime()) matchesByBoth++;
      }
    }
    contentMatches = matchesByContent;
    timeAndContentMatches = matchesByBoth;
  }
  return {
    protocol: 'okul-yanit-kimlik-tani/v1',
    formId: formId,
    scriptCount: responses.length,
    exactMatches: matches,
    timestampMatches: timestampMatches,
    contentMatches: contentMatches,
    timeAndContentMatches: timeAndContentMatches,
    // İçerik ve zaman eşleşmesi tek başına kesin kimlik kanıtı değildir.
    mappingVerified: matches === 1
  };
}

/** Sadece salt okunur aday sayımı için; hassas cevapları dışarı vermez. */
function okulYanitDegerleri_(raw) {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 100) return null;
  const values = [];
  for (const value of raw) {
    const parts = Array.isArray(value) ? value : [value];
    if (parts.length === 0 || parts.length > 100) return null;
    for (const part of parts) {
      if (typeof part !== 'string' || part.length > 5000) return null;
      values.push(part);
    }
  }
  if (values.length === 0 || values.length > 100) return null;
  return values.sort();
}

/** Kurulum doğrulaması: hiçbir formu veya yanıtı değiştirmez. */
function okulYanitSilKurulumKontrol() {
  return {protocol: 'okul-yanit-sil/v1', ready: true,
    implementation: 'exact-response-2026-11-19',
    nativeImplementation: 'native-response-2026-11-20',
    capabilities: ['native-response/v2']};
}

/** Yalnız seçilen cevabın düzenleme bağlantısı; genel form bağlantısı değildir. */
function okulYanitDuzenlemeBaglantisi(formId, responseId) {
  if (typeof formId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(formId) ||
      typeof responseId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(responseId)) {
    throw new Error('Form veya yanıt kimliği geçersiz.');
  }
  const form = FormApp.openById(formId);
  const response = form.getResponse(responseId);
  if (!response || response.getId() !== responseId) throw new Error('Yanıt bulunamadı.');
  if (!form.isAcceptingResponses()) throw new Error('Form yanıtlara kapalı.');
  form.setAllowResponseEdits(true);
  return {
    protocol: 'okul-yanit-duzelt/v1', formId: formId,
    responseId: responseId, editUrl: response.getEditResponseUrl()
  };
}
