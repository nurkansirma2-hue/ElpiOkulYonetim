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
function okulYanitKimlikTani(formId, responseId, restCreateTime) {
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
        return submitted instanceof Date && submitted.getTime() === time.getTime();
      }).length;
    }
  }
  return {
    protocol: 'okul-yanit-kimlik-tani/v1',
    formId: formId,
    scriptCount: responses.length,
    exactMatches: matches,
    timestampMatches: timestampMatches,
    mappingVerified: matches === 1
  };
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
