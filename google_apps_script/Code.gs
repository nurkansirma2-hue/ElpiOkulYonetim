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
    const exists = form.getResponses().some(r => r.getId() === responseId);
    if (exists) form.deleteResponse(responseId);
    const absent = !form.getResponses().some(r => r.getId() === responseId);
    if (!absent) throw new Error('Yanıtın silindiği doğrulanamadı.');
    return {
      protocol: 'okul-yanit-sil/v1',
      formId: formId,
      responseId: responseId,
      absent: true,
      deleted: exists
    };
  } finally {
    lock.releaseLock();
  }
}

/** Kurulum doğrulaması: hiçbir formu veya yanıtı değiştirmez. */
function okulYanitSilKurulumKontrol() {
  return {protocol: 'okul-yanit-sil/v1', ready: true};
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
