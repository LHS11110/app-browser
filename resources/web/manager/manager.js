document.addEventListener('DOMContentLoaded', () => {
  const processList = document.getElementById('process-list');
  const emptyState = document.getElementById('empty-state');
  const countBadge = document.getElementById('process-count-badge');
  const statParentPid = document.getElementById('stat-parent-pid');
  const lastSyncTime = document.getElementById('last-sync-time');
  const btnOpenSearch = document.getElementById('btn-open-search');
  const btnKillAll = document.getElementById('btn-kill-all');

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // Called by C++: window.updateProcessList(data)
  window.updateProcessList = function(data) {
    if (!data) return;

    if (data.parentPid) {
      statParentPid.textContent = data.parentPid;
    }

    const list = data.processes || [];
    countBadge.textContent = `${list.length}개 실행`;

    const now = new Date();
    lastSyncTime.textContent = `동기화: ${now.toLocaleTimeString()}`;

    if (list.length === 0) {
      processList.innerHTML = '';
      emptyState.style.display = 'flex';
      return;
    }

    emptyState.style.display = 'none';
    let html = '';

    list.forEach(item => {
      const displayTitle = item.title && item.title.trim().length > 0 ? item.title : item.url;
      html += `
        <li class="process-item" data-pid="${item.pid}">
          <!-- Top Row: Icon + Title + PID -->
          <div class="item-top">
            <div class="item-icon-title">
              <div class="item-icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <circle cx="12" cy="12" r="10"></circle>
                  <line x1="2" y1="12" x2="22" y2="12"></line>
                  <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path>
                </svg>
              </div>
              <span class="item-title" title="${escapeHtml(displayTitle)}">${escapeHtml(displayTitle)}</span>
            </div>
            <span class="item-pid">PID ${item.pid}</span>
          </div>

          <!-- Middle Row: URL -->
          <div class="item-mid">
            <span class="item-url" title="${escapeHtml(item.url)}">${escapeHtml(item.url)}</span>
          </div>

          <!-- Bottom Row: Status/Time + Action Buttons -->
          <div class="item-bot">
            <div class="item-meta">
              <span class="status-indicator"></span>
              <span class="item-time">${escapeHtml(item.startTime || '--:--:--')}</span>
            </div>
            <div class="item-actions">
              <button type="button" class="btn-item btn-focus" data-action="focus" data-pid="${item.pid}" title="앞으로 가져오기">
                <span>↗️ 활성화</span>
              </button>
              <button type="button" class="btn-item btn-kill" data-action="kill" data-pid="${item.pid}" title="프로세스 강제 종료">
                <span>✕ 종료</span>
              </button>
            </div>
          </div>
        </li>
      `;
    });

    processList.innerHTML = html;
  };

  // Event Delegation for Process List Actions
  processList.addEventListener('click', (e) => {
    const btn = e.target.closest('.btn-item');
    if (!btn) return;

    const action = btn.getAttribute('data-action');
    const pid = btn.getAttribute('data-pid');

    if (action === 'focus' && pid) {
      window.location.href = `action://focus?pid=${encodeURIComponent(pid)}`;
    } else if (action === 'kill' && pid) {
      window.location.href = `action://kill?pid=${encodeURIComponent(pid)}`;
    }
  });

  // Open Search Bar
  btnOpenSearch.addEventListener('click', () => {
    window.location.href = 'action://open-search';
  });

  // Kill All
  btnKillAll.addEventListener('click', () => {
    if (confirm('모든 자식 브라우저 프로세스를 종료하시겠습니까?')) {
      window.location.href = 'action://kill-all';
    }
  });

  // Signal ready to C++
  window.location.href = 'action://ready';
});
