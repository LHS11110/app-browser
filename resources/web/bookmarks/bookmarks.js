/**
 * App Browser - Bookmarks Window Logic
 * Strictly handles:
 *  - Icon-based access to URLs
 *  - Add bookmark
 *  - Edit bookmark
 *  - Delete bookmark
 */

(function () {
  'use strict';

  const STORAGE_KEY = 'appbrowser_bookmarks_v1';

  // Default seed bookmarks
  const DEFAULT_BOOKMARKS = [
    { id: 'bm_google', name: 'Google', url: 'https://www.google.com' },
    { id: 'bm_naver', name: 'Naver', url: 'https://www.naver.com' },
    { id: 'bm_github', name: 'GitHub', url: 'https://github.com' },
    { id: 'bm_youtube', name: 'YouTube', url: 'https://www.youtube.com' }
  ];

  // Gradients for icon backgrounds
  const PALETTES = [
    'linear-gradient(135deg, #4f46e5, #06b6d4)',
    'linear-gradient(135deg, #059669, #10b981)',
    'linear-gradient(135deg, #e11d48, #f43f5e)',
    'linear-gradient(135deg, #d97706, #fbbf24)',
    'linear-gradient(135deg, #7c3aed, #c084fc)',
    'linear-gradient(135deg, #2563eb, #38bdf8)',
    'linear-gradient(135deg, #dc2626, #f97316)'
  ];

  function getPalette(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      hash = str.charCodeAt(i) + ((hash << 5) - hash);
    }
    return PALETTES[Math.abs(hash) % PALETTES.length];
  }

  // State
  let bookmarks = [];
  let editingId = null;
  let deletingId = null;

  // DOM Elements
  const gridEl = document.getElementById('bookmark-grid');
  const btnAdd = document.getElementById('btn-add-bookmark');
  const btnClose = document.getElementById('btn-close-window');

  // Bookmark Modal
  const modalBookmark = document.getElementById('modal-bookmark');
  const modalTitle = document.getElementById('modal-bookmark-title');
  const modalForm = document.getElementById('modal-bookmark-form');
  const nameInput = document.getElementById('bm-name-input');
  const urlInput = document.getElementById('bm-url-input');
  const errorEl = document.getElementById('modal-bookmark-error');
  const btnCancelBookmark = document.getElementById('modal-bookmark-cancel');
  const btnCloseModalBookmark = document.getElementById('modal-bookmark-close');

  // Confirm Modal
  const modalConfirm = document.getElementById('modal-confirm');
  const confirmMsg = document.getElementById('modal-confirm-msg');
  const btnConfirmOk = document.getElementById('modal-confirm-ok');
  const btnConfirmCancel = document.getElementById('modal-confirm-cancel');
  const btnConfirmClose = document.getElementById('modal-confirm-close');

  // Toast
  const toastEl = document.getElementById('toast');

  // Load from Storage
  function loadBookmarks() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed) && parsed.length > 0) {
          bookmarks = parsed;
          return;
        }
      }
    } catch (e) {
      console.error('Failed to parse bookmarks:', e);
    }
    bookmarks = [...DEFAULT_BOOKMARKS];
    saveBookmarks();
  }

  function saveBookmarks() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(bookmarks));
    } catch (e) {
      console.error('Failed to save bookmarks:', e);
    }
  }

  function showToast(msg) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.classList.add('show');
    setTimeout(() => {
      toastEl.classList.remove('show');
    }, 2000);
  }

  function getDomain(urlStr) {
    try {
      const u = new URL(urlStr);
      return u.hostname.replace(/^www\./, '');
    } catch (e) {
      return urlStr.replace(/^https?:\/\//, '').split('/')[0];
    }
  }

  function normalizeUrl(rawUrl) {
    let url = (rawUrl || '').trim();
    if (!url) return '';
    if (!/^https?:\/\//i.test(url)) {
      url = 'https://' + url;
    }
    return url;
  }

  // Render Grid
  function renderBookmarks() {
    gridEl.innerHTML = '';

    if (bookmarks.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.innerHTML = `
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
          <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"></polygon>
        </svg>
        <p>등록된 즐겨찾기가 없습니다.</p>
      `;
      gridEl.appendChild(empty);
      return;
    }

    bookmarks.forEach((bm) => {
      const card = document.createElement('div');
      card.className = 'bookmark-card';
      card.title = `${bm.name}\n${bm.url}`;

      const domain = getDomain(bm.url);
      const bgGradient = getPalette(bm.name + domain);
      const initial = (bm.name.trim()[0] || '★').toUpperCase();

      // Card action buttons (Edit, Delete)
      card.innerHTML = `
        <div class="card-actions">
          <button type="button" class="btn-card-action action-edit" title="수정" data-id="${bm.id}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
              <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
            </svg>
          </button>
          <button type="button" class="btn-card-action action-delete" title="삭제" data-id="${bm.id}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="3 6 5 6 21 6"></polyline>
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
            </svg>
          </button>
        </div>
        <div class="bookmark-icon-box" style="background: ${bgGradient};">
          <span>${initial}</span>
        </div>
        <div class="bookmark-name">${escapeHtml(bm.name)}</div>
        <div class="bookmark-url">${escapeHtml(domain)}</div>
      `;

      // Click on Card -> Spawn Child Browser with preset URL
      card.addEventListener('click', (e) => {
        // Prevent trigger if clicking edit/delete buttons
        if (e.target.closest('.btn-card-action')) return;
        launchBookmark(bm.url);
      });

      // Edit Button
      const editBtn = card.querySelector('.action-edit');
      editBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        openEditModal(bm.id);
      });

      // Delete Button
      const deleteBtn = card.querySelector('.action-delete');
      deleteBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        openDeleteModal(bm.id);
      });

      gridEl.appendChild(card);
    });
  }

  function escapeHtml(str) {
    return (str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // Launch Bookmark via action://spawn
  function launchBookmark(url) {
    const targetUrl = normalizeUrl(url);
    if (!targetUrl) return;
    window.location.href = `action://spawn?url=${encodeURIComponent(targetUrl)}&_t=${Date.now()}`;
  }

  // Modal: Add Bookmark
  function openAddModal() {
    editingId = null;
    modalTitle.textContent = '즐겨찾기 추가';
    nameInput.value = '';
    urlInput.value = '';
    errorEl.textContent = '';
    modalBookmark.style.display = 'flex';
    nameInput.focus();
  }

  // Modal: Edit Bookmark
  function openEditModal(id) {
    const item = bookmarks.find((b) => b.id === id);
    if (!item) return;

    editingId = id;
    modalTitle.textContent = '즐겨찾기 수정';
    nameInput.value = item.name;
    urlInput.value = item.url;
    errorEl.textContent = '';
    modalBookmark.style.display = 'flex';
    nameInput.focus();
  }

  function closeBookmarkModal() {
    modalBookmark.style.display = 'none';
    editingId = null;
  }

  // Handle Add/Edit Form Submit
  modalForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const name = nameInput.value.trim();
    const rawUrl = urlInput.value.trim();

    if (!name) {
      errorEl.textContent = '이름을 입력해주세요.';
      nameInput.focus();
      return;
    }

    const url = normalizeUrl(rawUrl);
    if (!url) {
      errorEl.textContent = '유효한 주소를 입력해주세요.';
      urlInput.focus();
      return;
    }

    if (editingId) {
      // Edit existing
      const idx = bookmarks.findIndex((b) => b.id === editingId);
      if (idx !== -1) {
        bookmarks[idx].name = name;
        bookmarks[idx].url = url;
        saveBookmarks();
        renderBookmarks();
        showToast('즐겨찾기가 수정되었습니다.');
      }
    } else {
      // Add new
      const newBm = {
        id: 'bm_' + Date.now() + '_' + Math.floor(Math.random() * 1000),
        name: name,
        url: url
      };
      bookmarks.push(newBm);
      saveBookmarks();
      renderBookmarks();
      showToast('즐겨찾기가 추가되었습니다.');
    }

    closeBookmarkModal();
  });

  // Modal: Delete Confirm
  function openDeleteModal(id) {
    const item = bookmarks.find((b) => b.id === id);
    if (!item) return;

    deletingId = id;
    confirmMsg.textContent = `'${item.name}' 즐겨찾기를 삭제하시겠습니까?`;
    modalConfirm.style.display = 'flex';
  }

  function closeConfirmModal() {
    modalConfirm.style.display = 'none';
    deletingId = null;
  }

  btnConfirmOk.addEventListener('click', () => {
    if (!deletingId) return;
    bookmarks = bookmarks.filter((b) => b.id !== deletingId);
    saveBookmarks();
    renderBookmarks();
    closeConfirmModal();
    showToast('즐겨찾기가 삭제되었습니다.');
  });

  // Close Window Action
  function closeBookmarksWindow() {
    window.location.href = 'action://close-bookmarks';
  }

  // Event Listeners
  btnAdd.addEventListener('click', openAddModal);
  btnClose.addEventListener('click', closeBookmarksWindow);

  btnCancelBookmark.addEventListener('click', closeBookmarkModal);
  btnCloseModalBookmark.addEventListener('click', closeBookmarkModal);

  btnConfirmCancel.addEventListener('click', closeConfirmModal);
  btnConfirmClose.addEventListener('click', closeConfirmModal);

  // Close Modals on click outside
  modalBookmark.addEventListener('click', (e) => {
    if (e.target === modalBookmark) closeBookmarkModal();
  });
  modalConfirm.addEventListener('click', (e) => {
    if (e.target === modalConfirm) closeConfirmModal();
  });

  // Global Keyboard Shortcuts (Esc to close modals or window)
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (modalBookmark.style.display !== 'none') {
        closeBookmarkModal();
      } else if (modalConfirm.style.display !== 'none') {
        closeConfirmModal();
      } else {
        closeBookmarksWindow();
      }
    }
  });

  // Initialize
  loadBookmarks();
  renderBookmarks();
})();
