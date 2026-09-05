document.addEventListener('DOMContentLoaded', () => {
  const groupListEl = document.getElementById('group-list');
  const emptyStateEl = document.getElementById('empty-state');
  const countBadgeEl = document.getElementById('process-count-badge');
  const statTotalAppsEl = document.getElementById('stat-total-apps');
  const statTotalGroupsEl = document.getElementById('stat-total-groups');
  const lastSyncTimeEl = document.getElementById('last-sync-time');
  const btnOpenSearchEl = document.getElementById('btn-open-search');
  const btnOpenBookmarksEl = document.getElementById('btn-open-bookmarks');
  const btnAddGroupEl = document.getElementById('btn-add-group');
  const btnKillAllEl = document.getElementById('btn-kill-all');
  const toastEl = document.getElementById('toast-message');

  let currentProcesses = [];
  let editingPid = null;
  let toastTimer = null;

  // LocalStorage Keys
  const STORAGE_GROUPS = 'appbrowser_groups_v1';
  const STORAGE_PROCESS_META = 'appbrowser_process_meta_v1';

  // Load Groups
  function loadGroups() {
    try {
      const data = localStorage.getItem(STORAGE_GROUPS);
      if (data) {
        const parsed = JSON.parse(data);
        if (Array.isArray(parsed) && parsed.length > 0) {
          // Ensure default group always exists
          if (!parsed.some(g => g.id === 'default')) {
            parsed.unshift({ id: 'default', name: '기본 그룹', collapsed: false });
          }
          return parsed;
        }
      }
    } catch (e) {
      console.error('Failed to load groups:', e);
    }
    return [{ id: 'default', name: '기본 그룹', collapsed: false }];
  }

  // Save Groups
  function saveGroups(groups) {
    try {
      localStorage.setItem(STORAGE_GROUPS, JSON.stringify(groups));
    } catch (e) {
      console.error('Failed to save groups:', e);
    }
  }

  // Load Process Metadata (custom names, group assignments)
  function loadProcessMeta() {
    try {
      const data = localStorage.getItem(STORAGE_PROCESS_META);
      return data ? JSON.parse(data) : {};
    } catch (e) {
      return {};
    }
  }

  // Save Process Metadata
  function saveProcessMeta(meta) {
    try {
      localStorage.setItem(STORAGE_PROCESS_META, JSON.stringify(meta));
    } catch (e) {}
  }

  let groups = loadGroups();
  let processMeta = loadProcessMeta();

  // Friendly Toast Notification
  function showToast(message, isWarning = true) {
    if (toastTimer) clearTimeout(toastTimer);
    toastEl.textContent = message;
    toastEl.style.borderColor = isWarning ? 'rgba(245, 158, 11, 0.5)' : 'rgba(99, 102, 241, 0.5)';
    toastEl.classList.add('show');
    toastTimer = setTimeout(() => {
      toastEl.classList.remove('show');
    }, 3000);
  }

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function getDomain(urlStr) {
    try {
      const u = new URL(urlStr);
      return u.hostname.replace(/^www\./, '');
    } catch (e) {
      if (!urlStr) return '';
      return urlStr.replace(/^https?:\/\//, '').split('/')[0];
    }
  }

  // Generate a friendly initial process name based on URL/Title
  function generateFriendlyName(item, index) {
    const url = item.url || '';
    if (url) {
      try {
        const u = new URL(url);
        if (u.hostname.includes('google.') && u.pathname.includes('/search')) {
          const q = u.searchParams.get('q');
          if (q) return `Google: ${decodeURIComponent(q)}`;
        }
        if (u.hostname.includes('github.com')) return 'GitHub';
        if (u.hostname.includes('youtube.com')) return 'YouTube';
        if (u.hostname.includes('naver.com')) return 'Naver';
        if (item.title && item.title.trim().length > 0 && !item.title.startsWith('http')) {
          return item.title.trim();
        }
        return u.hostname;
      } catch (e) {}
    }
    if (item.title && item.title.trim().length > 0) {
      return item.title.trim();
    }
    return `브라우저 창 ${index + 1}`;
  }

  // Resolve process name and group
  function getProcessInfo(item, index) {
    const pidStr = String(item.pid);
    let meta = processMeta[pidStr];
    if (!meta) {
      // Create new meta entry
      meta = {
        name: generateFriendlyName(item, index),
        groupId: 'default'
      };
      processMeta[pidStr] = meta;
      saveProcessMeta(processMeta);
    }

    // Verify assigned group still exists
    if (!groups.some(g => g.id === meta.groupId)) {
      meta.groupId = 'default';
      saveProcessMeta(processMeta);
    }

    return {
      pid: item.pid,
      url: item.url || '',
      startTime: item.startTime || '--:--:--',
      name: meta.name || generateFriendlyName(item, index),
      groupId: meta.groupId || 'default'
    };
  }

  // Render entire Process Manager UI
  function render() {
    countBadgeEl.textContent = `${currentProcesses.length}개 실행`;
    statTotalAppsEl.textContent = currentProcesses.length;
    statTotalGroupsEl.textContent = groups.length;

    // Groups are ALWAYS visible regardless of whether there are running processes!
    if (emptyStateEl) {
      emptyStateEl.style.display = 'none';
    }

    // Map and categorize processes
    const resolvedItems = currentProcesses.map((p, idx) => getProcessInfo(p, idx));

    let html = '';

    // If there are 0 processes running in total, show a friendly top notice
    if (currentProcesses.length === 0) {
      html += `
        <div class="empty-process-banner">
          <div class="banner-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="10"></circle>
              <line x1="12" y1="8" x2="12" y2="12"></line>
              <line x1="12" y1="16" x2="12.01" y2="16"></line>
            </svg>
          </div>
          <div class="banner-text">
            <span>실행 중인 창이 없습니다. 상단 <strong>[검색창]</strong>을 눌러 웹 창을 열어보세요.</span>
          </div>
        </div>
      `;
    }

    groups.forEach(group => {
      const itemsInGroup = resolvedItems.filter(p => p.groupId === group.id);
      const isCollapsed = Boolean(group.collapsed);

      html += `
        <div class="group-folder ${isCollapsed ? 'collapsed' : ''}" data-group-id="${group.id}">
          <!-- Folder Tab & Header -->
          <div class="folder-header" data-action="toggle-group" data-group-id="${group.id}">
            <div class="folder-tab-badge"></div>
            <div class="folder-header-left">
              <span class="folder-collapse-arrow">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="6 9 12 15 18 9"></polyline>
                </svg>
              </span>
              <div class="folder-icon-box">
                ${isCollapsed ? `
                  <!-- Closed Folder Icon -->
                  <svg class="folder-icon closed" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M20 6h-8l-2-2H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm0 12H4V8h16v10z"/>
                  </svg>
                ` : `
                  <!-- Open Folder Icon -->
                  <svg class="folder-icon open" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M20 6h-8l-2-2H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2zm-1.04 12H5.04l2.16-7h13.76l-1.96 7z"/>
                  </svg>
                `}
              </div>
              <span class="folder-title" title="더블 클릭하여 폴더명 변경">${escapeHtml(group.name)}</span>
              <span class="folder-count-badge">${itemsInGroup.length}개</span>
            </div>
            <div class="folder-header-actions">
              <button type="button" class="btn-folder-action edit-group" data-action="rename-group" data-group-id="${group.id}" title="그룹명 변경">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
                  <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
                </svg>
              </button>
              ${group.id !== 'default' ? `
                <button type="button" class="btn-folder-action delete-group" data-action="delete-group" data-group-id="${group.id}" title="그룹 삭제 (창은 기본 그룹으로 이동)">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="3 6 5 6 21 6"></polyline>
                    <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                  </svg>
                </button>
              ` : ''}
            </div>
          </div>

          <!-- Folder Body & Process Items -->
          <div class="folder-body">
            <ul class="folder-items">
              ${itemsInGroup.length === 0 ? `
                <li class="folder-empty-hint">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path>
                  </svg>
                  <span>비어 있는 폴더</span>
                </li>
              ` : itemsInGroup.map(item => {
              const isEditingThis = (editingPid === item.pid);
              const domain = getDomain(item.url);
              const faviconUrl = domain ? `https://www.google.com/s2/favicons?domain=${encodeURIComponent(domain)}&sz=64` : '';

              return `
                <li class="process-item" data-pid="${item.pid}" data-group-id="${group.id}">
                  <!-- Top Row: Process Name (editable) + Group Move Selector -->
                  <div class="item-top">
                    ${isEditingThis ? `
                      <form class="item-name-edit-form" data-pid="${item.pid}" data-group-id="${group.id}">
                        <input type="text" class="name-edit-input" value="${escapeHtml(item.name)}" maxlength="40" required autofocus />
                        <button type="submit" class="btn-save-name" title="저장">✓</button>
                        <button type="button" class="btn-cancel-name" data-action="cancel-rename" title="취소">✕</button>
                      </form>
                    ` : `
                      <div class="item-name-box">
                        <div class="item-icon">
                          ${domain ? `
                            <img class="item-favicon" src="${faviconUrl}" alt="" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';" />
                            <svg style="display: none;" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                              <rect x="2" y="3" width="20" height="14" rx="2" ry="2"></rect>
                              <line x1="8" y1="21" x2="16" y2="21"></line>
                              <line x1="12" y1="17" x2="12" y2="21"></line>
                            </svg>
                          ` : `
                            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                              <rect x="2" y="3" width="20" height="14" rx="2" ry="2"></rect>
                              <line x1="8" y1="21" x2="16" y2="21"></line>
                              <line x1="12" y1="17" x2="12" y2="21"></line>
                            </svg>
                          `}
                        </div>
                        <span class="item-name" data-action="start-rename" data-pid="${item.pid}" title="클릭하여 프로세스명 변경">${escapeHtml(item.name)}</span>
                        <button type="button" class="btn-rename" data-action="start-rename" data-pid="${item.pid}" title="프로세스명 변경">
                          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <path d="M12 20h9"></path>
                            <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path>
                          </svg>
                        </button>
                      </div>

                      <div class="group-selector-box">
                        <select class="group-select" data-pid="${item.pid}" data-current-group="${group.id}" title="다른 그룹으로 이동">
                          ${groups.map(g => `
                            <option value="${g.id}" ${g.id === group.id ? 'selected' : ''}>
                              ${escapeHtml(g.name)}
                            </option>
                          `).join('')}
                        </select>
                      </div>
                    `}
                  </div>

                  <!-- Middle Row: URL subtitle -->
                  <div class="item-mid">
                    <span class="item-url" title="${escapeHtml(item.url)}">${escapeHtml(item.url)}</span>
                  </div>

                  <!-- Bottom Row: Time + Action Buttons -->
                  <div class="item-bot">
                    <div class="item-meta">
                      <span class="status-indicator"></span>
                      <span class="item-time">${escapeHtml(item.startTime)}</span>
                    </div>
                    <div class="item-actions">
                      <button type="button" class="btn-item btn-focus" data-action="focus" data-pid="${item.pid}" title="창 앞으로 가져오기">
                        <span>↗️ 활성화</span>
                      </button>
                      <button type="button" class="btn-item btn-kill" data-action="kill" data-pid="${item.pid}" title="창 종료">
                        <span>✕ 종료</span>
                      </button>
                    </div>
                  </div>
                </li>
              `;
            }).join('')}
            </ul>
          </div>
        </div>
      `;
    });

    groupListEl.innerHTML = html;

    // Focus edit input if currently editing
    if (editingPid) {
      const input = groupListEl.querySelector('.name-edit-input');
      if (input) {
        input.focus();
        input.select();
      }
    }
  }

  // C++ calls: window.updateProcessList(data)
  window.updateProcessList = function(data) {
    if (!data) return;

    currentProcesses = data.processes || [];

    const now = new Date();
    lastSyncTimeEl.textContent = `동기화: ${now.toLocaleTimeString()}`;

    render();
  };

  // Check if a process name already exists within a specific group
  function isNameTakenInGroup(name, targetGroupId, excludePid) {
    const cleanName = name.trim().toLowerCase();
    for (const p of currentProcesses) {
      if (p.pid === excludePid) continue;
      const meta = processMeta[String(p.pid)];
      const pGroupId = (meta && meta.groupId) ? meta.groupId : 'default';
      const pName = (meta && meta.name) ? meta.name : generateFriendlyName(p, 0);

      if (pGroupId === targetGroupId && pName.trim().toLowerCase() === cleanName) {
        return true;
      }
    }
    return false;
  }

  // Modal Elements
  const modalGroupEl = document.getElementById('modal-group');
  const modalGroupTitleEl = document.getElementById('modal-group-title');
  const modalGroupCloseEl = document.getElementById('modal-group-close');
  const modalGroupFormEl = document.getElementById('modal-group-form');
  const modalGroupInputEl = document.getElementById('modal-group-input');
  const modalGroupErrorEl = document.getElementById('modal-group-error');
  const modalGroupCancelEl = document.getElementById('modal-group-cancel');

  const modalConfirmEl = document.getElementById('modal-confirm');
  const modalConfirmTitleEl = document.getElementById('modal-confirm-title');
  const modalConfirmCloseEl = document.getElementById('modal-confirm-close');
  const modalConfirmMessageEl = document.getElementById('modal-confirm-message');
  const modalConfirmCancelEl = document.getElementById('modal-confirm-cancel');
  const modalConfirmOkEl = document.getElementById('modal-confirm-ok');

  let modalGroupState = { mode: 'create', groupId: null };
  let confirmState = { action: null, payload: null };

  function openGroupModal(mode, groupId = null) {
    modalGroupState = { mode, groupId };
    if (modalGroupErrorEl) modalGroupErrorEl.textContent = '';

    if (mode === 'create') {
      if (modalGroupTitleEl) modalGroupTitleEl.textContent = '새 그룹 추가';
      if (modalGroupInputEl) modalGroupInputEl.value = '';
    } else {
      const group = groups.find(g => g.id === groupId);
      if (!group) return;
      if (modalGroupTitleEl) modalGroupTitleEl.textContent = '그룹 이름 변경';
      if (modalGroupInputEl) modalGroupInputEl.value = group.name;
    }

    if (modalGroupEl) {
      modalGroupEl.style.display = 'flex';
      setTimeout(() => {
        if (modalGroupInputEl) {
          modalGroupInputEl.focus();
          modalGroupInputEl.select();
        }
      }, 50);
    }
  }

  function closeGroupModal() {
    if (modalGroupEl) modalGroupEl.style.display = 'none';
    if (modalGroupInputEl) modalGroupInputEl.value = '';
    if (modalGroupErrorEl) modalGroupErrorEl.textContent = '';
    modalGroupState = { mode: 'create', groupId: null };
  }

  function openConfirmDeleteModal(groupId) {
    if (groupId === 'default') return;
    const group = groups.find(g => g.id === groupId);
    if (!group) return;

    confirmState = { action: 'delete-group', payload: groupId };
    if (modalConfirmTitleEl) modalConfirmTitleEl.textContent = '그룹 삭제';
    if (modalConfirmMessageEl) {
      modalConfirmMessageEl.innerHTML = `<strong>'${escapeHtml(group.name)}'</strong> 그룹을 삭제하시겠습니까?`;
    }
    const submessage = modalConfirmEl.querySelector('.modal-submessage');
    if (submessage) {
      submessage.innerHTML = `그룹 내의 실행 창들은 <strong>기본 그룹</strong>으로 안전하게 이동됩니다.`;
    }
    if (modalConfirmEl) {
      modalConfirmEl.style.display = 'flex';
    }
  }

  function openConfirmKillAllModal() {
    confirmState = { action: 'kill-all', payload: null };
    if (modalConfirmTitleEl) modalConfirmTitleEl.textContent = '모든 창 종료';
    if (modalConfirmMessageEl) {
      modalConfirmMessageEl.innerHTML = `모든 실행 중인 창을 종료하시겠습니까?`;
    }
    const submessage = modalConfirmEl.querySelector('.modal-submessage');
    if (submessage) {
      submessage.innerHTML = `실행 중인 모든 브라우저 프로세스가 안전하게 닫힙니다.`;
    }
    if (modalConfirmEl) {
      modalConfirmEl.style.display = 'flex';
    }
  }

  function closeConfirmModal() {
    if (modalConfirmEl) modalConfirmEl.style.display = 'none';
    confirmState = { action: null, payload: null };
  }

  // Modal Event Listeners
  if (modalGroupCloseEl) modalGroupCloseEl.addEventListener('click', closeGroupModal);
  if (modalGroupCancelEl) modalGroupCancelEl.addEventListener('click', closeGroupModal);
  if (modalGroupEl) {
    modalGroupEl.addEventListener('click', (e) => {
      if (e.target === modalGroupEl) closeGroupModal();
    });
  }

  if (modalConfirmCloseEl) modalConfirmCloseEl.addEventListener('click', closeConfirmModal);
  if (modalConfirmCancelEl) modalConfirmCancelEl.addEventListener('click', closeConfirmModal);
  if (modalConfirmEl) {
    modalConfirmEl.addEventListener('click', (e) => {
      if (e.target === modalConfirmEl) closeConfirmModal();
    });
  }

  // Handle Group Modal Form Submit
  if (modalGroupFormEl) {
    modalGroupFormEl.addEventListener('submit', (e) => {
      e.preventDefault();
      const rawName = modalGroupInputEl ? modalGroupInputEl.value : '';
      const trimmed = rawName.trim();

      if (!trimmed) {
        if (modalGroupErrorEl) modalGroupErrorEl.textContent = '그룹 이름을 입력하세요.';
        if (modalGroupInputEl) modalGroupInputEl.focus();
        return;
      }

      if (modalGroupState.mode === 'create') {
        if (groups.some(g => g.name.toLowerCase() === trimmed.toLowerCase())) {
          if (modalGroupErrorEl) modalGroupErrorEl.textContent = '이미 동일한 이름의 그룹이 존재합니다.';
          if (modalGroupInputEl) modalGroupInputEl.focus();
          return;
        }

        const newGroup = {
          id: 'group_' + Date.now(),
          name: trimmed,
          collapsed: false
        };

        groups.push(newGroup);
        saveGroups(groups);
        closeGroupModal();
        render();
        showToast(`'${trimmed}' 그룹이 생성되었습니다.`, false);
      } else if (modalGroupState.mode === 'rename') {
        const targetGroupId = modalGroupState.groupId;
        if (groups.some(g => g.id !== targetGroupId && g.name.toLowerCase() === trimmed.toLowerCase())) {
          if (modalGroupErrorEl) modalGroupErrorEl.textContent = '이미 동일한 이름의 다른 그룹이 존재합니다.';
          if (modalGroupInputEl) modalGroupInputEl.focus();
          return;
        }

        const group = groups.find(g => g.id === targetGroupId);
        if (group) {
          group.name = trimmed;
          saveGroups(groups);
          closeGroupModal();
          render();
          showToast('그룹명이 변경되었습니다.', false);
        }
      }
    });
  }

  // Handle Confirm OK (Delete Group or Kill All)
  if (modalConfirmOkEl) {
    modalConfirmOkEl.addEventListener('click', () => {
      if (confirmState.action === 'delete-group') {
        const targetGroupId = confirmState.payload;
        if (!targetGroupId || targetGroupId === 'default') {
          closeConfirmModal();
          return;
        }

        const group = groups.find(g => g.id === targetGroupId);
        if (!group) {
          closeConfirmModal();
          return;
        }

        const deletedName = group.name;

        // Reassign all processes in this group to 'default'
        Object.keys(processMeta).forEach(pid => {
          if (processMeta[pid].groupId === targetGroupId) {
            processMeta[pid].groupId = 'default';
          }
        });
        saveProcessMeta(processMeta);

        groups = groups.filter(g => g.id !== targetGroupId);
        saveGroups(groups);
        closeConfirmModal();
        render();
        showToast(`'${deletedName}' 그룹이 삭제되었습니다.`, false);
      } else if (confirmState.action === 'kill-all') {
        closeConfirmModal();
        window.location.href = 'action://kill-all';
        showToast('모든 창을 종료했습니다.', false);
      }
    });
  }

  // ESC Key listener for modals
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (modalGroupEl && modalGroupEl.style.display === 'flex') {
        closeGroupModal();
      } else if (modalConfirmEl && modalConfirmEl.style.display === 'flex') {
        closeConfirmModal();
      }
    }
  });

  // Create New Group Button
  btnAddGroupEl.addEventListener('click', () => {
    openGroupModal('create');
  });

  // Group Header Interaction Delegation
  groupListEl.addEventListener('click', (e) => {
    // 1. Rename group
    const renameBtn = e.target.closest('[data-action="rename-group"]');
    if (renameBtn) {
      e.stopPropagation();
      const groupId = renameBtn.getAttribute('data-group-id');
      openGroupModal('rename', groupId);
      return;
    }

    // 2. Delete group
    const deleteBtn = e.target.closest('[data-action="delete-group"]');
    if (deleteBtn) {
      e.stopPropagation();
      const groupId = deleteBtn.getAttribute('data-group-id');
      openConfirmDeleteModal(groupId);
      return;
    }

    // 3. Toggle group collapse/expand
    const headerEl = e.target.closest('[data-action="toggle-group"]');
    if (headerEl) {
      const groupId = headerEl.getAttribute('data-group-id');
      const group = groups.find(g => g.id === groupId);
      if (group) {
        group.collapsed = !group.collapsed;
        saveGroups(groups);
        render();
      }
      return;
    }

    // 4. Start renaming process
    const startRenameBtn = e.target.closest('[data-action="start-rename"]');
    if (startRenameBtn) {
      const pid = parseInt(startRenameBtn.getAttribute('data-pid'), 10);
      editingPid = pid;
      render();
      return;
    }

    // 5. Cancel renaming process
    const cancelRenameBtn = e.target.closest('[data-action="cancel-rename"]');
    if (cancelRenameBtn) {
      editingPid = null;
      render();
      return;
    }

    // 6. Focus or Kill process
    const actionBtn = e.target.closest('.btn-item');
    if (actionBtn) {
      const action = actionBtn.getAttribute('data-action');
      const pid = actionBtn.getAttribute('data-pid');
      if (action === 'focus' && pid) {
        window.location.href = `action://focus?pid=${encodeURIComponent(pid)}`;
      } else if (action === 'kill' && pid) {
        window.location.href = `action://kill?pid=${encodeURIComponent(pid)}`;
      }
      return;
    }
  });

  // Double click group title to rename
  groupListEl.addEventListener('dblclick', (e) => {
    const titleEl = e.target.closest('.folder-title, .group-title');
    if (!titleEl) return;
    const header = titleEl.closest('.folder-header, .group-header');
    if (!header) return;
    const groupId = header.getAttribute('data-group-id');
    if (groupId) {
      openGroupModal('rename', groupId);
    }
  });

  // Handle Process Name Rename Form Submit
  groupListEl.addEventListener('submit', (e) => {
    const form = e.target.closest('.item-name-edit-form');
    if (!form) return;
    e.preventDefault();

    const pid = parseInt(form.getAttribute('data-pid'), 10);
    const groupId = form.getAttribute('data-group-id');
    const input = form.querySelector('.name-edit-input');
    if (!input) return;

    const newName = input.value.trim();
    if (!newName) {
      showToast('프로세스명을 입력해주세요.');
      return;
    }

    // Check uniqueness within the SAME group:
    if (isNameTakenInGroup(newName, groupId, pid)) {
      const group = groups.find(g => g.id === groupId);
      const groupName = group ? group.name : '해당 그룹';
      showToast(`'${groupName}'에 이미 동일한 이름 '${newName}'이(가) 있습니다.`);
      input.focus();
      input.select();
      return;
    }

    // Save custom name
    const pidStr = String(pid);
    if (!processMeta[pidStr]) {
      processMeta[pidStr] = { groupId: groupId };
    }
    processMeta[pidStr].name = newName;
    saveProcessMeta(processMeta);

    editingPid = null;
    render();
    showToast(`프로세스명이 '${newName}'(으)로 변경되었습니다.`, false);
  });

  // Handle Group Select Change (Move Process between Groups)
  groupListEl.addEventListener('change', (e) => {
    const select = e.target.closest('.group-select');
    if (!select) return;

    const pid = parseInt(select.getAttribute('data-pid'), 10);
    const currentGroupId = select.getAttribute('data-current-group');
    const newGroupId = select.value;

    if (currentGroupId === newGroupId) return;

    const pidStr = String(pid);
    const meta = processMeta[pidStr] || {};
    const processName = meta.name || generateFriendlyName(currentProcesses.find(p => p.pid === pid) || {}, 0);

    // Validate if new group already has a process with the same name
    if (isNameTakenInGroup(processName, newGroupId, pid)) {
      const targetGroup = groups.find(g => g.id === newGroupId);
      const targetGroupName = targetGroup ? targetGroup.name : '선택한 그룹';
      showToast(`'${targetGroupName}'에 이미 '${processName}' 창이 있습니다. 이동하려면 이름을 변경해주세요.`);
      select.value = currentGroupId; // Revert select
      return;
    }

    // Update group assignment
    if (!processMeta[pidStr]) {
      processMeta[pidStr] = { name: processName };
    }
    processMeta[pidStr].groupId = newGroupId;
    saveProcessMeta(processMeta);

    render();
    const targetGroup = groups.find(g => g.id === newGroupId);
    showToast(`'${processName}' 창이 '${targetGroup ? targetGroup.name : ''}'(으)로 이동되었습니다.`, false);
  });

  // Open Search Window
  btnOpenSearchEl.addEventListener('click', () => {
    window.location.href = 'action://open-search';
  });

  // Open Bookmarks Window
  if (btnOpenBookmarksEl) {
    btnOpenBookmarksEl.addEventListener('click', () => {
      window.location.href = 'action://open-bookmarks';
    });
  }

  // Kill All Processes
  btnKillAllEl.addEventListener('click', () => {
    if (currentProcesses.length === 0) {
      showToast('실행 중인 창이 없습니다.');
      return;
    }
    openConfirmKillAllModal();
  });

  // Signal ready to C++ ProcessManager
  window.location.href = 'action://ready';
});

