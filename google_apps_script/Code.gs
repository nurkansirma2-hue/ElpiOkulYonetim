/** API yürütülebilir dağıtım; çağıran kullanıcının Google Forms yetkisiyle çalışır. */
function okulYanitSil(formId, responseId) {
  if (typeof formId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(formId) ||
      typeof responseId !== 'string' || !/^[a-zA-Z0-9_-]{1,300}$/.test(responseId)) {
    throw new Error('Form veya yanıt kimliği geçersiz.');
  }
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
    implementation: 'exact-response-2026-11-19'};
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
