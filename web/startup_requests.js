// Flutter のエンジン・フォントの読み込み中に、初期タブの公開データを取得する。
// 結果は Dart 側で一度だけ使い、通常の更新・再取得には使わない。
(() => {
  let tab = 'npb';
  try {
    const cookie = document.cookie.split(';').map(value => value.trim())
      .find(value => value.startsWith('koko_org='));
    tab = cookie ? decodeURIComponent(cookie.slice('koko_org='.length))
      : localStorage.getItem('koko_cookie_koko_org') || 'npb';
  } catch (_) {}
  if (tab === 'predict') return;
  const org = tab === 'mlb' ? 'mlb' : 'npb';
  const today = new Date();
  const year = today.getFullYear();
  const day = offset => {
    const date = new Date(year, today.getMonth(), today.getDate() + offset);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  };
  const requests = window.kokoStartupRequests = Object.create(null);
  for (const part of ['games', 'standings']) {
    let path = `/predictions/part?org=${org}&part=${part}&year=${year}`;
    if (part === 'games') path += `&from=${day(-3)}&to=${day(10)}`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 12000);
    requests[path] = fetch(path, {signal: controller.signal, credentials: 'same-origin'})
      .then(async response => response.ok
        ? {status: response.status, body: await response.text()} : null)
      .catch(() => null)
      .finally(() => clearTimeout(timeout));
  }
})();
