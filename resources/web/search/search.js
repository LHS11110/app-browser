document.addEventListener('DOMContentLoaded', () => {
  const form = document.getElementById('search-form');
  const input = document.getElementById('search-input');

  function checkIfUrl(rawText) {
    const text = rawText.trim();
    if (!text) return false;

    // Explicit protocol
    if (/^https?:\/\//i.test(text)) return true;

    // IP address or localhost
    if (/^localhost(:\d+)?(\/.*)?$/i.test(text)) return true;
    if (/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?(\/.*)?$/.test(text)) return true;

    // Domain name pattern: e.g. domain.com, sub.domain.co.kr, notion.so, etc. (no spaces)
    if (!/\s/.test(text) && /^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(:\d+)?(\/.*)?$/.test(text)) {
      return true;
    }

    return false;
  }

  function launchInChildProcess(targetUrl) {
    // Request parent ProcessManager to spawn a child browser process
    window.location.href = `action://spawn?url=${encodeURIComponent(targetUrl)}&_t=${Date.now()}`;
    input.value = '';
    input.blur();
  }

  function handleSubmit(e) {
    if (e) e.preventDefault();
    const query = input.value.trim();
    if (!query) return;

    if (checkIfUrl(query)) {
      // Direct URL navigation
      const finalUrl = /^https?:\/\//i.test(query) ? query : `https://${query}`;
      launchInChildProcess(finalUrl);
    } else {
      // Google search navigation
      const googleSearchUrl = `https://www.google.com/search?q=${encodeURIComponent(query)}`;
      launchInChildProcess(googleSearchUrl);
    }
  }

  form.addEventListener('submit', handleSubmit);

  // Global keydown: focus input on typing or press '/' or Cmd+K
  window.addEventListener('keydown', (e) => {
    if (document.activeElement !== input) {
      if (e.key === '/' || (e.metaKey && e.key === 'k') || (e.ctrlKey && e.key === 'k')) {
        e.preventDefault();
        input.focus();
        input.select();
      }
    }
  });

  // Clicking anywhere outside also focuses input
  window.addEventListener('click', () => {
    if (document.activeElement !== input) {
      input.focus();
    }
  });

  input.focus();
});
