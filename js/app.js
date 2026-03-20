    const STORAGE = CONFIG.STORAGE_KEYS;

    let todos = {}; // { "2026-03-18": [{ id, text, done }] }
    let memos = []; // [{ id, taskId, date, taskTitle, content, createdAt }]
    let selectedDate = new Date();
    let taskTargetDate = null; // 添加任务时使用的目标日期，选择后不改变页面视图
    let currentTaskForMemo = null;
    let highlightTask = null;   // { key, idx } 搜索跳转后高亮
    let highlightMemoId = null;
    let currentEditMemo = null; // 正在编辑的备忘录 { idx }
    let openSwipeKey = null;
    let openSwipeDirection = null;
    let suppressNextTaskCardClick = false;
    let moveTaskDraft = null;
    let moveDatePickerMonth = new Date();
    let viewportResizeTimer = null;
    let listSectionState = {
      pinned: true,
      active: true,
      completed: true
    };
    const SWIPE_REVEAL_WIDTH = 146;
    const SWIPE_OPEN_THRESHOLD = 88;

    function dateKey(d) {
      const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0');
      return `${y}-${m}-${day}`;
    }

    async function loadData() {
      try {
        const cloud = await Sync.loadFromCloud();
        // 优先读取云端数据库；API 失败时用 localStorage
        if (cloud !== null) {
          todos = cloud.todos || {};
          memos = cloud.memos || [];
        } else {
          const t = Storage.get(STORAGE.todos);
          todos = t ? JSON.parse(t) : {};
          const m = Storage.get(STORAGE.memos);
          memos = m ? JSON.parse(m) : [];
        }
        Object.keys(todos).forEach(k => {
          todos[k] = todos[k].map((item, i) => ({
            ...item,
            id: item.id || k + '-' + i,
            createdAt: item.createdAt || Number(item.id) || Date.now() - ((todos[k].length - i) * 1000),
            completedAt: item.done ? (item.completedAt || item.updatedAt || item.createdAt || Number(item.id) || Date.now()) : null,
            pinnedAt: item.pinnedAt || null
          }));
        });
        memos = memos.map((mo, i) => ({ ...mo, id: mo.id || 'memo-' + (mo.date || '') + '-' + (mo.createdAt || i) }));
      } catch (e) { todos = {}; memos = []; }
    }

    function saveData() {
      Storage.set(STORAGE.todos, JSON.stringify(todos));
      Storage.set(STORAGE.memos, JSON.stringify(memos));
      Storage.set(STORAGE.selectedDate, selectedDate.toISOString());
      Sync.saveToCloud(todos, memos);
    }

    function getTodosForDate(key) {
      if (!todos[key]) todos[key] = [];
      return todos[key]
        .map((t, i) => ({ ...t, _idx: i }))
        .sort((a, b) => {
          if (!!a.pinnedAt !== !!b.pinnedAt) return a.pinnedAt ? -1 : 1;
          if (a.pinnedAt && b.pinnedAt) return (b.pinnedAt || 0) - (a.pinnedAt || 0);
          if (a.done !== b.done) return a.done ? 1 : -1;
          if (!a.done) return (b.createdAt || 0) - (a.createdAt || 0);
          return (b.completedAt || 0) - (a.completedAt || 0);
        });
    }

    function groupTodosForSections(list) {
      return {
        pinned: list.filter(t => !!t.pinnedAt),
        active: list.filter(t => !t.pinnedAt && !t.done),
        completed: list.filter(t => !t.pinnedAt && t.done)
      };
    }

    function getTodayKey() {
      return dateKey(new Date());
    }

    function applyViewportHeight() {
      const viewport = window.visualViewport;
      const height = viewport ? viewport.height : window.innerHeight;
      document.documentElement.style.setProperty('--app-height', `${height}px`);
    }

    function scheduleViewportHeightUpdate() {
      if (viewportResizeTimer) clearTimeout(viewportResizeTimer);
      viewportResizeTimer = setTimeout(() => {
        applyViewportHeight();
        viewportResizeTimer = null;
      }, 40);
    }

    function closeSwipeActions() {
      openSwipeKey = null;
      openSwipeDirection = null;
      document.querySelectorAll('.task-swipe-item.swiped-left, .task-swipe-item.swiped-right').forEach(el => {
        el.classList.remove('swiped-left');
        el.classList.remove('swiped-right');
      });
      document.querySelectorAll('.task-card').forEach(el => {
        el.style.transform = '';
        el.style.transition = '';
      });
    }

    function setSwipeOpen(wrapper, card, swipeKey, direction) {
      closeSwipeActions();
      openSwipeKey = swipeKey;
      openSwipeDirection = direction;
      wrapper.classList.add(direction === 'right' ? 'swiped-right' : 'swiped-left');
      card.style.transition = 'transform 0.2s ease';
      card.style.transform = `translateX(${direction === 'right' ? SWIPE_REVEAL_WIDTH : -SWIPE_REVEAL_WIDTH}px)`;
    }

    function deleteTaskByIndex(key, idx) {
      if (!todos[key] || !todos[key][idx]) return;
      todos[key].splice(idx, 1);
      saveData();
      renderList();
      if (document.getElementById('calendar-panel').classList.contains('active')) renderCalendar();
      if (document.getElementById('memo-panel').classList.contains('active')) renderMemos();
    }

    function moveTaskToDate(fromKey, idx, targetKey) {
      if (!todos[fromKey] || !todos[fromKey][idx]) return;
      if (targetKey < getTodayKey()) return;
      const task = todos[fromKey][idx];
      todos[fromKey].splice(idx, 1);
      if (!todos[targetKey]) todos[targetKey] = [];
      todos[targetKey].push(task);
      memos.forEach(memo => {
        if (memo.taskId === task.id) memo.date = targetKey;
      });
      saveData();
      renderList();
      if (document.getElementById('calendar-panel').classList.contains('active')) renderCalendar();
      if (document.getElementById('memo-panel').classList.contains('active')) renderMemos();
    }

    function toggleTaskPin(key, idx) {
      if (!todos[key] || !todos[key][idx]) return;
      todos[key][idx].pinnedAt = todos[key][idx].pinnedAt ? null : Date.now();
      saveData();
      renderList();
      if (document.getElementById('calendar-panel').classList.contains('active')) renderCalendar();
    }

    function renderMoveDatePicker() {
      const baseDate = moveTaskDraft ? moveTaskDraft.date : new Date();
      const selectedKey = dateKey(baseDate);
      const todayKey = getTodayKey();
      const year = moveDatePickerMonth.getFullYear();
      const month = moveDatePickerMonth.getMonth();
      document.getElementById('move-date-picker-month').textContent = `${year}年${month + 1}月`;

      const first = new Date(year, month, 1);
      const startPad = first.getDay();
      const prevMonth = new Date(year, month, 0);
      const prevDays = prevMonth.getDate();
      const daysInMonth = new Date(year, month + 1, 0).getDate();

      let html = '';
      for (let i = 0; i < startPad; i++) {
        html += `<div class="move-date-picker-day other">${prevDays - startPad + i + 1}</div>`;
      }
      for (let d = 1; d <= daysInMonth; d++) {
        const key = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
        let cls = 'move-date-picker-day';
        if (key === todayKey) cls += ' today';
        if (key === selectedKey) cls += ' selected';
        if (key < todayKey) cls += ' past';
        html += `<button class="${cls}" data-date="${key}" type="button">${d}</button>`;
      }
      const rest = 42 - (startPad + daysInMonth);
      for (let i = 0; i < rest; i++) {
        html += `<div class="move-date-picker-day other">${i + 1}</div>`;
      }

      const grid = document.getElementById('move-date-picker-grid');
      grid.innerHTML = html;
      grid.querySelectorAll('.move-date-picker-day[data-date]').forEach(el => {
        el.onclick = () => {
          if (!moveTaskDraft) return;
          const targetKey = el.dataset.date;
          const draft = { ...moveTaskDraft };
          closeMoveDateModal();
          if (targetKey === draft.key) return;
          moveTaskToDate(draft.key, draft.idx, targetKey);
        };
      });
    }

    function openMoveDateModal(key, idx) {
      if (!todos[key] || !todos[key][idx]) return;
      closeSwipeActions();
      const todayKey = getTodayKey();
      const baseKey = key < todayKey ? todayKey : key;
      moveTaskDraft = {
        key,
        idx,
        taskId: todos[key][idx].id,
        date: new Date(baseKey + 'T12:00:00')
      };
      moveDatePickerMonth = new Date(moveTaskDraft.date.getFullYear(), moveTaskDraft.date.getMonth(), 1);
      document.getElementById('move-date-modal-title').textContent = `更改日期：${todos[key][idx].text}`;
      renderMoveDatePicker();
      document.getElementById('move-date-modal').classList.add('show');
    }

    function closeMoveDateModal() {
      document.getElementById('move-date-modal').classList.remove('show');
      moveTaskDraft = null;
    }

    function bindTaskSwipe(wrapper, card, swipeKey) {
      let startX = 0;
      let deltaX = 0;
      let dragging = false;
      let isPointerDown = false;
      const maxSwipe = SWIPE_REVEAL_WIDTH;

      const updateTransform = (value) => {
        card.style.transition = 'none';
        card.style.transform = `translateX(${value}px)`;
      };

      card.addEventListener('pointerdown', (e) => {
        if (e.pointerType === 'mouse' && e.button !== 0) return;
        if (e.target.closest('.checkbox, .task-edit-input, button')) return;
        e.stopPropagation();
        if (openSwipeKey && openSwipeKey !== swipeKey) {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
        }
        isPointerDown = true;
        dragging = false;
        card.dataset.suppressClick = '0';
        startX = e.clientX;
        deltaX = 0;
        card.style.transition = 'none';
        if (typeof card.setPointerCapture === 'function') {
          try { card.setPointerCapture(e.pointerId); } catch (_) {}
        }
      });

      card.addEventListener('pointermove', (e) => {
        if (!isPointerDown) return;
        deltaX = e.clientX - startX;
        if (!dragging && Math.abs(deltaX) < 8) return;
        dragging = true;
        e.preventDefault();
        e.stopPropagation();
        const base = wrapper.classList.contains('swiped-right') ? maxSwipe : (wrapper.classList.contains('swiped-left') ? -maxSwipe : 0);
        let next = base + deltaX;
        next = Math.max(-maxSwipe, Math.min(maxSwipe, next));
        card.dataset.suppressClick = '1';
        updateTransform(next);
      });

      const finishGesture = () => {
        if (!isPointerDown) return;
        isPointerDown = false;
        if (!dragging) return;
        dragging = false;
        const base = wrapper.classList.contains('swiped-right') ? maxSwipe : (wrapper.classList.contains('swiped-left') ? -maxSwipe : 0);
        const finalX = Math.max(-maxSwipe, Math.min(maxSwipe, base + deltaX));
        card.style.transition = 'transform 0.2s ease';
        if (finalX <= -SWIPE_OPEN_THRESHOLD) setSwipeOpen(wrapper, card, swipeKey, 'left');
        else if (finalX >= SWIPE_OPEN_THRESHOLD) setSwipeOpen(wrapper, card, swipeKey, 'right');
        else {
          wrapper.classList.remove('swiped-left');
          wrapper.classList.remove('swiped-right');
          if (openSwipeKey === swipeKey) {
            openSwipeKey = null;
            openSwipeDirection = null;
          }
          card.style.transform = 'translateX(0)';
        }
        if (typeof card.releasePointerCapture === 'function' && e && e.pointerId !== undefined) {
          try { card.releasePointerCapture(e.pointerId); } catch (_) {}
        }
      };

      card.addEventListener('pointerup', finishGesture);
      card.addEventListener('pointercancel', finishGesture);
      card.addEventListener('lostpointercapture', finishGesture);
      card.addEventListener('click', () => {
        if (card.dataset.suppressClick === '1') {
          setTimeout(() => { card.dataset.suppressClick = '0'; }, 0);
        }
      });
    }

    function formatDateLong(d) {
      const week = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
      return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日${week[d.getDay()]}`;
    }

    function formatDateShort(d) {
      return `${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    }

    function formatMemoTitle(d, taskTitle) {
      return `${d.getMonth() + 1}月${d.getDate()}日 - ${taskTitle}`;
    }

    function hasMemoForTask(task, key) {
      if (!task) return false;
      return memos.some(memo => {
        if (task.id && memo.taskId === task.id) return true;
        return memo.date === key && memo.taskTitle === task.text;
      });
    }

    function hasMemoForDate(key) {
      return memos.some(memo => memo.date === key);
    }

    function renderTaskMemoIndicator(task, key) {
      if (!hasMemoForTask(task, key)) return '';
      return `
        <span class="task-memo-indicator" title="已添加备忘录" aria-label="已添加备忘录">
          <span class="task-memo-indicator-corner"></span>
        </span>
      `;
    }

    function buildCalendarMarks(key, done, undone) {
      const hasMemo = hasMemoForDate(key);
      if (done === 0 && undone === 0 && !hasMemo) return '';
      let html = '<div class="calendar-badges">';
      if (done > 0) html += `<span class="calendar-badge badge-done" title="已完成">${done}</span>`;
      if (undone > 0) html += `<span class="calendar-badge badge-undone" title="未完成">${undone}</span>`;
      if (hasMemo) html += '<span class="calendar-memo-dot" title="当天有备忘录" aria-label="当天有备忘录"></span>';
      html += '</div>';
      return html;
    }

    function startTaskInlineEdit(textEl, initialValue, onSave) {
      if (!textEl || textEl.dataset.editing === '1') return;
      textEl.dataset.editing = '1';
      const input = document.createElement('input');
      input.type = 'text';
      input.className = 'task-edit-input';
      input.value = initialValue;
      input.onblur = () => {
        const val = input.value.trim();
        if (val) onSave(val);
      };
      input.onkeydown = (ev) => {
        if (ev.key === 'Enter') input.blur();
        if (ev.key === 'Escape') {
          input.value = initialValue;
          input.blur();
        }
      };
      input.addEventListener('blur', () => {
        delete textEl.dataset.editing;
      }, { once: true });
      textEl.replaceWith(input);
      input.focus();
      input.select();
    }

    function deleteMemoByIndex(idx) {
      if (idx < 0 || idx >= memos.length) return;
      memos.splice(idx, 1);
      saveData();
      renderMemos();
      if (document.getElementById('calendar-panel').classList.contains('active')) renderCalendar();
    }

    function findMemoIndexForTask(task, key) {
      if (!task) return -1;
      return memos.findIndex(memo => {
        if (task.id && memo.taskId === task.id) return true;
        return memo.date === key && memo.taskTitle === task.text;
      });
    }

    function openMemoModalForTask(key, idx, task) {
      const existingMemoIdx = findMemoIndexForTask(task, key);
      currentEditMemo = existingMemoIdx >= 0 ? { idx: existingMemoIdx } : null;
      currentTaskForMemo = { key, idx, task };
      const isFromTask = task.id && task.id !== 'new';
      const editingExisting = existingMemoIdx >= 0;
      const existingMemo = editingExisting ? memos[existingMemoIdx] : null;
      document.getElementById('memo-modal-title').textContent = editingExisting
        ? '编辑备忘录'
        : (isFromTask ? `添加备忘：${task.text}` : '新建备忘录');
      const titleInput = document.getElementById('memo-modal-title-input');
      titleInput.style.display = 'block';
      titleInput.value = editingExisting ? (existingMemo.taskTitle || '') : (isFromTask ? task.text : '');
      titleInput.placeholder = '备忘标题';
      document.getElementById('memo-modal-input').value = editingExisting ? (existingMemo.content || '') : '';
      document.getElementById('memo-modal').classList.add('show');
      titleInput.focus();
      titleInput.select();
    }

    function bindSwipeActionButton(button, handler) {
      if (!button) return;
      const run = (e) => {
        if (e) {
          e.preventDefault();
          e.stopPropagation();
        }
        handler();
      };
      button.onclick = run;
      button.onpointerup = run;
    }

    function bindMemoSwipe(wrapper, card, swipeKey) {
      let startX = 0;
      let deltaX = 0;
      let dragging = false;
      let isPointerDown = false;
      const maxSwipe = SWIPE_REVEAL_WIDTH;

      const updateTransform = (value) => {
        card.style.transition = 'none';
        card.style.transform = `translateX(${value}px)`;
      };

      card.addEventListener('pointerdown', (e) => {
        if (e.pointerType === 'mouse' && e.button !== 0) return;
        if (e.target.closest('button')) return;
        e.stopPropagation();
        if (openSwipeKey && openSwipeKey !== swipeKey) {
          closeSwipeActions();
        }
        isPointerDown = true;
        dragging = false;
        card.dataset.suppressClick = '0';
        startX = e.clientX;
        deltaX = 0;
        card.style.transition = 'none';
        if (typeof card.setPointerCapture === 'function') {
          try { card.setPointerCapture(e.pointerId); } catch (_) {}
        }
      });

      card.addEventListener('pointermove', (e) => {
        if (!isPointerDown) return;
        deltaX = e.clientX - startX;
        if (!dragging && Math.abs(deltaX) < 8) return;
        dragging = true;
        e.preventDefault();
        e.stopPropagation();
        let next = deltaX;
        next = Math.max(-maxSwipe, Math.min(0, next));
        card.dataset.suppressClick = '1';
        updateTransform(next);
      });

      const finishGesture = (e) => {
        if (!isPointerDown) return;
        isPointerDown = false;
        if (!dragging) return;
        dragging = false;
        const finalX = Math.max(-maxSwipe, Math.min(0, deltaX));
        card.style.transition = 'transform 0.2s ease';
        if (finalX <= -SWIPE_OPEN_THRESHOLD) setSwipeOpen(wrapper, card, swipeKey, 'left');
        else {
          wrapper.classList.remove('swiped-left');
          if (openSwipeKey === swipeKey) {
            openSwipeKey = null;
            openSwipeDirection = null;
          }
          card.style.transform = 'translateX(0)';
        }
        if (typeof card.releasePointerCapture === 'function' && e && e.pointerId !== undefined) {
          try { card.releasePointerCapture(e.pointerId); } catch (_) {}
        }
      };

      card.addEventListener('pointerup', finishGesture);
      card.addEventListener('pointercancel', finishGesture);
      card.addEventListener('lostpointercapture', finishGesture);
      card.addEventListener('click', () => {
        if (card.dataset.suppressClick === '1') {
          setTimeout(() => { card.dataset.suppressClick = '0'; }, 0);
        }
      });
    }

    function escapeHtml(s) {
      const d = document.createElement('div');
      d.textContent = s || '';
      return d.innerHTML;
    }

    function formatDateForSearch(key) {
      const [y, m, d] = key.split('-').map(Number);
      const date = new Date(y, m - 1, d);
      const today = dateKey(new Date());
      if (key === today) return '今天';
      return `${m}月${d}日`;
    }

    function performSearch(q) {
      const qLower = (q || '').trim().toLowerCase();
      if (!qLower) return { todos: [], memos: [] };

      const todoResults = [];
      Object.keys(todos).sort().reverse().forEach(key => {
        (todos[key] || []).forEach((t, i) => {
          if (t.text && t.text.toLowerCase().includes(qLower)) {
            todoResults.push({ type: 'todo', key, text: t.text, done: t.done, idx: i });
          }
        });
      });

      const memoResults = memos.filter(m => {
        const matchTitle = m.taskTitle && m.taskTitle.toLowerCase().includes(qLower);
        const matchContent = m.content && m.content.toLowerCase().includes(qLower);
        return matchTitle || matchContent;
      });

      return { todos: todoResults, memos: memoResults };
    }

    function openSearchModal() {
      document.getElementById('search-overlay').classList.add('show');
      document.getElementById('search-input').value = '';
      document.getElementById('search-input').focus();
      renderSearchResults('');
    }

    function closeSearchModal() {
      document.getElementById('search-overlay').classList.remove('show');
    }

    function renderSearchResults(query) {
      const { todos: todoResults, memos: memoResults } = performSearch(query);
      const container = document.getElementById('search-results');

      if (!query.trim()) {
        container.innerHTML = '<div class="search-empty">输入关键词搜索清单和备忘录</div>';
        return;
      }

      if (todoResults.length === 0 && memoResults.length === 0) {
        container.innerHTML = '<div class="search-empty">未找到相关内容</div>';
        return;
      }

      let html = '';
      if (todoResults.length > 0) {
        html += '<div class="search-section-title">清单</div>';
        todoResults.slice(0, 8).forEach((r, i) => {
          html += `
            <button class="search-item" data-type="todo" data-key="${escapeHtml(r.key)}" data-idx="${r.idx}">
              <span class="search-item-icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg>
              </span>
              <div class="search-item-content">
                <div class="search-item-title">${escapeHtml(r.text)}</div>
                <div class="search-item-meta">${formatDateForSearch(r.key)}${r.done ? ' · 已完成' : ''}</div>
              </div>
            </button>
          `;
        });
      }
      if (memoResults.length > 0) {
        html += '<div class="search-section-title">备忘录</div>';
        memoResults.slice(0, 8).forEach(m => {
          const [y, mo, d] = m.date.split('-').map(Number);
          const dateStr = `${mo}月${d}日`;
          const title = (m.taskTitle || '备忘').slice(0, 40);
          html += `
            <button class="search-item" data-type="memo" data-date="${escapeHtml(m.date)}" data-memo-id="${escapeHtml(m.id || '')}">
              <span class="search-item-icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>
              </span>
              <div class="search-item-content">
                <div class="search-item-title">${escapeHtml(title)}</div>
                <div class="search-item-meta">${dateStr}${m.content ? ' · ' + escapeHtml((m.content || '').slice(0, 28)) + ((m.content || '').length > 28 ? '...' : '') : ''}</div>
              </div>
            </button>
          `;
        });
      }
      container.innerHTML = html;

      container.querySelectorAll('.search-item').forEach((el, i) => {
        el.classList.toggle('active', i === 0);
        el.onclick = () => {
          if (el.dataset.type === 'todo') {
            highlightTask = { key: el.dataset.key, idx: +el.dataset.idx };
            highlightMemoId = null;
            selectedDate = new Date(el.dataset.key + 'T12:00:00');
            saveData();
            switchTab('list');
          } else {
            highlightTask = null;
            highlightMemoId = el.dataset.memoId || null;
            const [y, mo, d] = el.dataset.date.split('-').map(Number);
            selectedDate = new Date(y, mo - 1, d);
            saveData();
            switchTab('memo');
          }
          closeSearchModal();
        };
      });
    }

    function switchTab(tab) {
      document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
      document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
      document.querySelectorAll('.nav-center-btn').forEach(n => n.classList.remove('active'));
      const panel = document.getElementById(tab + '-panel');
      if (panel) panel.classList.add('active');
      const navEl = document.querySelector(`.nav-item[data-tab="${tab}"]`);
      const centerBtn = document.querySelector(`.nav-center-btn[data-tab="${tab}"]`);
      if (navEl) navEl.classList.add('active');
      if (centerBtn) centerBtn.classList.add('active');
      Storage.set(STORAGE.tab, tab);
      if (tab === 'list') renderList();
      if (tab === 'calendar') renderCalendar();
      if (tab === 'memo') renderMemos();
    }

    function renderTaskRow(task, key, scopePrefix) {
      const pinTitle = task.pinnedAt ? '取消置顶' : '置顶';
      const rowClass = scopePrefix === 'calendar' ? ' summary-task-wrap' : '';
      const cardClass = scopePrefix === 'calendar' ? ' summary-task' : '';
      return `
        <div class="task-swipe-item${rowClass}" data-swipe-key="${scopePrefix}-${key}-${task.id || task._idx}">
          <div class="task-swipe-actions task-swipe-actions-left">
            <button class="task-swipe-action memo" type="button" data-action="memo" title="添加备忘">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
                <polyline points="14 2 14 8 20 8"/>
                <line x1="12" y1="18" x2="12" y2="12"/>
                <line x1="9" y1="15" x2="15" y2="15"/>
              </svg>
            </button>
            <button class="task-swipe-action pin" type="button" data-action="pin" title="${pinTitle}">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 17v5"/>
                <path d="M8 3h8l-1 5 3 3v2H6v-2l3-3-1-5z"/>
              </svg>
            </button>
          </div>
          <div class="task-swipe-actions task-swipe-actions-right">
            <button class="task-swipe-action move" type="button" data-action="move" title="更改日期">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
                <line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/>
                <line x1="3" y1="10" x2="21" y2="10"/>
              </svg>
            </button>
            <button class="task-swipe-action delete" type="button" data-action="delete" title="删除">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="3 6 5 6 21 6"/>
                <path d="M19 6l-1 14H6L5 6"/>
                <path d="M10 11v6"/>
                <path d="M14 11v6"/>
                <path d="M9 6V4h6v2"/>
              </svg>
            </button>
          </div>
          <div class="task-card${cardClass} ${task.done ? 'done' : ''} ${task.pinnedAt ? 'pinned' : ''}" data-idx="${task._idx}" data-id="${task.id || ''}">
            ${renderTaskMemoIndicator(task, key)}
            <div class="checkbox"></div>
            <span class="task-text">${escapeHtml(task.text)}</span>
          </div>
        </div>
      `;
    }

    function renderTaskSection(id, title, items, emptyText, key, scopePrefix) {
      const expanded = listSectionState[id];
      const body = items.length
        ? items.map(item => renderTaskRow(item, key, scopePrefix)).join('')
        : `<div class="task-section-empty">${emptyText}</div>`;
      return `
        <section class="task-section task-section-${id} ${expanded ? 'expanded' : 'collapsed'}" data-section="${id}">
          <button class="task-section-header" type="button" data-section-toggle="${id}">
            <span class="task-section-title">${title}</span>
            <span class="task-section-meta">
              <span class="task-section-count">${items.length}</span>
              <span class="task-section-chevron">${expanded ? '▾' : '▸'}</span>
            </span>
          </button>
          <div class="task-section-body">${expanded ? body : ''}</div>
        </section>
      `;
    }

    function buildVisibleTaskSections(sections, scope) {
      const activeTitle = scope === 'calendar' ? '未完成' : '今天';
      return [
        { id: 'pinned', title: '置顶', items: sections.pinned },
        { id: 'active', title: activeTitle, items: sections.active },
        { id: 'completed', title: '已完成', items: sections.completed }
      ].filter(section => section.items.length > 0);
    }

    function renderTaskSectionsMarkup(sections, key, scopePrefix) {
      return buildVisibleTaskSections(sections, scopePrefix)
        .map(section => renderTaskSection(section.id, section.title, section.items, '', key, scopePrefix))
        .join('');
    }

    function renderList() {
      const key = dateKey(selectedDate);
      const list = getTodosForDate(key);
      const sections = groupTodosForSections(list);
      const isToday = dateKey(new Date()) === key;

      document.getElementById('list-title').textContent = isToday ? '今天' : formatDateLong(selectedDate);

      const done = list.filter(t => t.done).length;
      const total = list.length;
      const pct = total ? (done / total * 100) : 0;
      document.getElementById('progress-fill').style.width = pct + '%';
      document.getElementById('progress-text').textContent = `${done} / ${total} 已完成`;

      const container = document.getElementById('todo-list');
      if (list.length === 0) openSwipeKey = null;

      container.innerHTML = renderTaskSectionsMarkup(sections, key, 'list');

      container.querySelectorAll('[data-section-toggle]').forEach(btn => {
        btn.onclick = () => {
          const id = btn.dataset.sectionToggle;
          listSectionState[id] = !listSectionState[id];
          renderList();
        };
      });

      container.querySelectorAll('.task-swipe-item').forEach(wrapper => {
        const card = wrapper.querySelector('.task-card');
        const idx = +card.dataset.idx;
        const swipeKey = wrapper.dataset.swipeKey;
        if (openSwipeKey === swipeKey) setSwipeOpen(wrapper, card, swipeKey, openSwipeDirection || 'left');
        bindTaskSwipe(wrapper, card, swipeKey);
        card.querySelector('.checkbox').onclick = () => {
          closeSwipeActions();
          todos[key][idx].done = !todos[key][idx].done;
          todos[key][idx].completedAt = todos[key][idx].done ? Date.now() : null;
          saveData();
          renderList();
        };
        const deleteBtn = wrapper.querySelector('[data-action="delete"]');
        const moveBtn = wrapper.querySelector('[data-action="move"]');
        const pinBtn = wrapper.querySelector('[data-action="pin"]');
        const memoBtn = wrapper.querySelector('[data-action="memo"]');
        bindSwipeActionButton(deleteBtn, () => {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
          deleteTaskByIndex(key, idx);
        });
        bindSwipeActionButton(moveBtn, () => {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
          openMoveDateModal(key, idx);
        });
        bindSwipeActionButton(pinBtn, () => {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
          toggleTaskPin(key, idx);
        });
        bindSwipeActionButton(memoBtn, () => {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
          openMemoModalForTask(key, idx, todos[key][idx]);
        });
        const textEl = card.querySelector('.task-text');
        if (!todos[key][idx].done && textEl) {
          card.onclick = (e) => {
            if (e.target.closest('.checkbox, button, .task-edit-input')) return;
            if (suppressNextTaskCardClick) {
              suppressNextTaskCardClick = false;
              return;
            }
            if (card.dataset.suppressClick === '1') return;
            if (wrapper.classList.contains('swiped-left') || wrapper.classList.contains('swiped-right')) return;
            e.stopPropagation();
            closeSwipeActions();
            startTaskInlineEdit(textEl, todos[key][idx].text, (val) => {
              todos[key][idx].text = val;
              saveData();
              renderList();
            });
          };
        }
        card.oncontextmenu = (e) => {
          e.preventDefault();
          closeSwipeActions();
          currentTaskForMemo = { key, idx, task: todos[key][idx] };
          document.getElementById('context-menu').classList.add('show');
          document.getElementById('context-menu').style.left = e.clientX + 'px';
          document.getElementById('context-menu').style.top = e.clientY + 'px';
        };
      });

      if (highlightTask && highlightTask.key === key) {
        const card = container.querySelector(`.task-card[data-idx="${highlightTask.idx}"]`);
        if (card) {
          card.classList.add('highlight');
          card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          setTimeout(() => card.classList.remove('highlight'), 1500);
        }
        highlightTask = null;
      }
    }

    document.addEventListener('click', (e) => {
      document.getElementById('context-menu').classList.remove('show');
      if (!e.target.closest('.task-swipe-item')) closeSwipeActions();
    });

    document.getElementById('context-add-memo').onclick = () => {
      document.getElementById('context-menu').classList.remove('show');
      if (!currentTaskForMemo) return;
      openMemoModalForTask(currentTaskForMemo.key, currentTaskForMemo.idx, currentTaskForMemo.task);
    };

    document.getElementById('memo-modal-cancel').onclick = () => {
      document.getElementById('memo-modal').classList.remove('show');
      currentTaskForMemo = null;
      currentEditMemo = null;
    };

    document.getElementById('move-date-modal-cancel').onclick = () => closeMoveDateModal();
    document.getElementById('move-date-modal').onclick = (e) => {
      if (e.target.id === 'move-date-modal') closeMoveDateModal();
    };
    document.getElementById('move-date-picker-prev').onclick = () => {
      moveDatePickerMonth.setMonth(moveDatePickerMonth.getMonth() - 1);
      renderMoveDatePicker();
    };
    document.getElementById('move-date-picker-next').onclick = () => {
      moveDatePickerMonth.setMonth(moveDatePickerMonth.getMonth() + 1);
      renderMoveDatePicker();
    };

    document.getElementById('memo-modal-confirm').onclick = () => {
      const content = document.getElementById('memo-modal-input').value.trim();
      const titleInput = document.getElementById('memo-modal-title-input');
      const customTitle = titleInput.value.trim();

      if (currentEditMemo) {
        memos[currentEditMemo.idx].taskTitle = customTitle || '备忘';
        memos[currentEditMemo.idx].content = content;
        saveData();
        document.getElementById('memo-modal').classList.remove('show');
        currentEditMemo = null;
        renderMemos();
        renderList();
        if (document.getElementById('calendar-panel').classList.contains('active')) renderCalendar();
        return;
      }

      if (!currentTaskForMemo) return;
      const { key, task } = currentTaskForMemo;
      const taskTitle = task.id === 'new' ? (customTitle || '新建备忘') : task.text;
      const [y, m, day] = key.split('-').map(Number);
      const d = new Date(y, m - 1, day);
      memos.unshift({
        id: Date.now().toString(),
        taskId: task.id || key + '-' + currentTaskForMemo.idx,
        date: key,
        taskTitle,
        content,
        createdAt: Date.now()
      });
      saveData();
      document.getElementById('memo-modal').classList.remove('show');
      currentTaskForMemo = null;
      renderMemos();
      renderList();
      if (document.getElementById('calendar-panel').classList.contains('active')) renderCalendar();
    };

    function updateSummaryTasks(key) {
      const list = getTodosForDate(key);
      const done = list.filter(t => t.done).length;
      const total = list.length;
      document.getElementById('summary-progress-fill').style.width = (total ? done / total * 100 : 0) + '%';
      document.getElementById('summary-progress-text').textContent = `${done}/${total}`;
      document.getElementById('summary-date').textContent = formatDateLong(selectedDate);
      const container = document.getElementById('summary-tasks');
      if (list.length === 0) {
        openSwipeKey = null;
        container.innerHTML = '';
        return;
      }
      const sections = groupTodosForSections(list);
      container.innerHTML = renderTaskSectionsMarkup(sections, key, 'calendar');
      container.querySelectorAll('[data-section-toggle]').forEach(btn => {
        btn.onclick = () => {
          const id = btn.dataset.sectionToggle;
          listSectionState[id] = !listSectionState[id];
          updateSummaryTasks(key);
        };
      });
      container.querySelectorAll('.task-swipe-item').forEach(wrapper => {
        const card = wrapper.querySelector('.task-card');
        if (!card) return;
        const idx = +card.dataset.idx;
        const swipeKey = wrapper.dataset.swipeKey;
        if (openSwipeKey === swipeKey) setSwipeOpen(wrapper, card, swipeKey, openSwipeDirection || 'left');
        bindTaskSwipe(wrapper, card, swipeKey);
        card.querySelector('.checkbox').onclick = () => {
          closeSwipeActions();
          if (!todos[key]) todos[key] = [];
          todos[key][idx].done = !todos[key][idx].done;
          todos[key][idx].completedAt = todos[key][idx].done ? Date.now() : null;
          saveData();
          updateSummaryTasks(key);
          refreshCalendarBadges();
        };
        const deleteBtn = wrapper.querySelector('[data-action="delete"]');
        const moveBtn = wrapper.querySelector('[data-action="move"]');
        const pinBtn = wrapper.querySelector('[data-action="pin"]');
        const memoBtn = wrapper.querySelector('[data-action="memo"]');
        bindSwipeActionButton(deleteBtn, () => {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
          deleteTaskByIndex(key, idx);
        });
        bindSwipeActionButton(moveBtn, () => {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
          openMoveDateModal(key, idx);
        });
        bindSwipeActionButton(pinBtn, () => {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
          toggleTaskPin(key, idx);
        });
        bindSwipeActionButton(memoBtn, () => {
          suppressNextTaskCardClick = true;
          closeSwipeActions();
          openMemoModalForTask(key, idx, todos[key][idx]);
        });
        const textEl = card.querySelector('.task-text');
        if (!todos[key][idx].done && textEl) {
          card.onclick = (e) => {
            if (e.target.closest('.checkbox, button, .task-edit-input')) return;
            if (suppressNextTaskCardClick) {
              suppressNextTaskCardClick = false;
              return;
            }
            if (card.dataset.suppressClick === '1') return;
            if (wrapper.classList.contains('swiped-left') || wrapper.classList.contains('swiped-right')) return;
            e.stopPropagation();
            closeSwipeActions();
            startTaskInlineEdit(textEl, todos[key][idx].text, (val) => {
              todos[key][idx].text = val;
              saveData();
              updateSummaryTasks(key);
              refreshCalendarBadges();
            });
          };
        }
        card.oncontextmenu = (e) => {
          e.preventDefault();
          closeSwipeActions();
          currentTaskForMemo = { key, idx, task: todos[key][idx] };
          document.getElementById('context-menu').classList.add('show');
          document.getElementById('context-menu').style.left = e.clientX + 'px';
          document.getElementById('context-menu').style.top = e.clientY + 'px';
        };
      });
    }

    function refreshCalendarBadges() {
      document.getElementById('calendar-grid').querySelectorAll('.calendar-day[data-date]').forEach(el => {
        const key = el.dataset.date;
        const list = getTodosForDate(key);
        const done = list.filter(t => t.done).length;
        const undone = list.length - done;
        const badges = buildCalendarMarks(key, done, undone);
        const dayNum = el.dataset.day || el.textContent.replace(/\D/g, '') || '';
        el.innerHTML = dayNum + badges;
      });
    }

    function renderCalendar() {
      const year = selectedDate.getFullYear();
      const month = selectedDate.getMonth();
      document.getElementById('calendar-month').textContent = `${year}年${month + 1}月`;

      const first = new Date(year, month, 1);
      const last = new Date(year, month + 1, 0);
      const startPad = first.getDay();
      const daysInMonth = last.getDate();

      let html = '日一二三四五六'.split('').map(d => `<div class="calendar-weekday">${d}</div>`).join('');
      const prevMonth = new Date(year, month, 0);
      const prevDays = prevMonth.getDate();
      for (let i = 0; i < startPad; i++) {
        html += `<div class="calendar-day other">${prevDays - startPad + i + 1}</div>`;
      }
      const todayKey = dateKey(new Date());
      const selKey = dateKey(selectedDate);
      for (let d = 1; d <= daysInMonth; d++) {
        const date = new Date(year, month, d);
        const key = dateKey(date);
        let cls = 'calendar-day';
        if (key === todayKey) cls += ' today';
        if (key === selKey) cls += ' selected';
        const list = getTodosForDate(key);
        const done = list.filter(t => t.done).length;
        const undone = list.length - done;
        const badges = buildCalendarMarks(key, done, undone);
        html += `<div class="calendar-day ${cls}" data-date="${key}" data-day="${d}">${d}${badges}</div>`;
      }
      const rest = 42 - (startPad + daysInMonth);
      for (let i = 0; i < rest; i++) {
        html += `<div class="calendar-day other">${i + 1}</div>`;
      }
      document.getElementById('calendar-grid').innerHTML = html;

      document.getElementById('calendar-grid').querySelectorAll('.calendar-day[data-date]').forEach(el => {
        el.onclick = () => {
          selectedDate = new Date(el.dataset.date + 'T12:00:00');
          saveData();
          renderCalendar();
          updateSummaryTasks(el.dataset.date);
        };
      });

      updateSummaryTasks(dateKey(selectedDate));
    }

    document.getElementById('prev-month').onclick = () => {
      selectedDate.setMonth(selectedDate.getMonth() - 1);
      saveData();
      renderCalendar();
    };

    document.getElementById('next-month').onclick = () => {
      selectedDate.setMonth(selectedDate.getMonth() + 1);
      saveData();
      renderCalendar();
    };

    document.getElementById('view-detail-btn').onclick = () => {
      switchTab('list');
    };

    function formatInputDateShort(d) {
      return `${d.getMonth() + 1}/${d.getDate()}`;
    }

    function updateInputDateBtnState() {
      const input = document.getElementById('todo-input');
      const btn = document.getElementById('input-date-btn');
      const hasContent = (input.value || '').trim().length > 0;
      btn.disabled = !hasContent;
      updateInputDateBtnDisplay();
    }

    function updateInputDateBtnDisplay() {
      const textEl = document.getElementById('input-date-btn-text');
      const d = taskTargetDate || selectedDate;
      textEl.textContent = formatInputDateShort(d);
    }

    let inputDatePickerMonth = new Date();

    function renderInputDatePicker() {
      const year = inputDatePickerMonth.getFullYear();
      const month = inputDatePickerMonth.getMonth();
      document.getElementById('input-date-picker-month').textContent = `${year}年${month + 1}月`;

      const first = new Date(year, month, 1);
      const startPad = first.getDay();
      const prevMonth = new Date(year, month, 0);
      const prevDays = prevMonth.getDate();
      const daysInMonth = new Date(year, month + 1, 0).getDate();
      const todayKey = dateKey(new Date());
      const targetKey = taskTargetDate ? dateKey(taskTargetDate) : todayKey;

      let html = '';
      for (let i = 0; i < startPad; i++) {
        html += `<div class="input-date-picker-day other">${prevDays - startPad + i + 1}</div>`;
      }
      for (let d = 1; d <= daysInMonth; d++) {
        const key = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
        let cls = 'input-date-picker-day';
        if (key === todayKey) cls += ' today';
        if (key === targetKey) cls += ' selected';
        if (key < todayKey) cls += ' past';
        html += `<div class="${cls}" data-date="${key}">${d}</div>`;
      }
      const rest = 42 - (startPad + daysInMonth);
      for (let i = 0; i < rest; i++) {
        html += `<div class="input-date-picker-day other">${i + 1}</div>`;
      }
      document.getElementById('input-date-picker-grid').innerHTML = html;

      document.getElementById('input-date-picker-grid').querySelectorAll('.input-date-picker-day[data-date]').forEach(el => {
        el.onclick = () => {
          if (el.classList.contains('past')) return;
          taskTargetDate = new Date(el.dataset.date + 'T12:00:00');
          closeInputDatePicker();
          updateInputDateBtnDisplay();
        };
      });
    }

    function openInputDatePicker() {
      const base = taskTargetDate || selectedDate;
      inputDatePickerMonth = new Date(base.getFullYear(), base.getMonth(), 1);
      renderInputDatePicker();
      document.getElementById('input-date-picker').classList.add('show');
    }

    function closeInputDatePicker() {
      document.getElementById('input-date-picker').classList.remove('show');
    }

    document.getElementById('open-calendar-btn').onclick = () => switchTab('calendar');
    document.getElementById('input-date-btn').onclick = (e) => {
      e.stopPropagation();
      if (document.getElementById('input-date-picker').classList.contains('show')) {
        closeInputDatePicker();
      } else {
        openInputDatePicker();
      }
    };
    document.getElementById('input-date-picker-prev').onclick = (e) => {
      e.stopPropagation();
      inputDatePickerMonth.setMonth(inputDatePickerMonth.getMonth() - 1);
      renderInputDatePicker();
    };
    document.getElementById('input-date-picker-next').onclick = (e) => {
      e.stopPropagation();
      inputDatePickerMonth.setMonth(inputDatePickerMonth.getMonth() + 1);
      renderInputDatePicker();
    };
    document.getElementById('todo-input').oninput = updateInputDateBtnState;
    document.getElementById('todo-input').addEventListener('focus', () => {
      setTimeout(() => document.getElementById('todo-input').scrollIntoView({ block: 'center', behavior: 'smooth' }), 120);
    });

    document.addEventListener('click', (e) => {
      const picker = document.getElementById('input-date-picker');
      const wrap = document.querySelector('.input-wrap');
      if (picker.classList.contains('show') && wrap && !wrap.contains(e.target)) {
        closeInputDatePicker();
      }
    });

    document.getElementById('open-search-btn').onclick = () => openSearchModal();
    document.getElementById('search-input').oninput = () => renderSearchResults(document.getElementById('search-input').value);
    document.getElementById('search-input').addEventListener('focus', () => {
      setTimeout(() => document.getElementById('search-modal').scrollIntoView({ block: 'start', behavior: 'smooth' }), 120);
    });
    document.getElementById('search-overlay').onclick = e => {
      if (e.target.id === 'search-overlay') closeSearchModal();
    };
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && document.getElementById('search-overlay').classList.contains('show')) {
        closeSearchModal();
      }
      if (e.key === 'Escape' && document.getElementById('move-date-modal').classList.contains('show')) {
        closeMoveDateModal();
      }
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        if (document.getElementById('search-overlay').classList.contains('show')) closeSearchModal();
        else openSearchModal();
      }
    });

    function renderMemos() {
      document.getElementById('memo-count').textContent = `${memos.length} 条记录`;
      const list = document.getElementById('memo-list');
      if (memos.length === 0) {
        list.innerHTML = '<div class="empty-state">暂无备忘录，在清单项上右键可添加备忘</div>';
        return;
      }
      list.innerHTML = memos.map((m, i) => {
        const [y, mo, d] = m.date.split('-').map(Number);
        const dateObj = new Date(y, mo - 1, d);
        return `
          <div class="memo-swipe-item" data-swipe-key="memo-${m.id || i}">
            <div class="memo-swipe-actions">
              <button class="task-swipe-action delete" type="button" data-action="delete-memo" title="删除">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="3 6 5 6 21 6"/>
                  <path d="M19 6l-1 14H6L5 6"/>
                  <path d="M10 11v6"/>
                  <path d="M14 11v6"/>
                  <path d="M9 6V4h6v2"/>
                </svg>
              </button>
            </div>
            <div class="memo-card" data-memo-id="${escapeHtml(m.id || '')}" data-memo-idx="${i}">
              <div class="memo-title">${escapeHtml(formatMemoTitle(dateObj, m.taskTitle))}</div>
              <div class="memo-body">${escapeHtml(m.content)}</div>
              <div class="memo-meta">• ${formatDateShort(new Date(m.createdAt))}</div>
            </div>
          </div>
        `;
      }).join('');

      list.querySelectorAll('.memo-swipe-item').forEach(wrapper => {
        const card = wrapper.querySelector('.memo-card');
        const idx = +card.dataset.memoIdx;
        const swipeKey = wrapper.dataset.swipeKey;
        if (openSwipeKey === swipeKey) setSwipeOpen(wrapper, card, swipeKey, 'left');
        bindMemoSwipe(wrapper, card, swipeKey);
        const deleteBtn = wrapper.querySelector('[data-action="delete-memo"]');
        if (deleteBtn) {
          deleteBtn.onclick = (e) => {
            e.stopPropagation();
            closeSwipeActions();
            deleteMemoByIndex(idx);
          };
        }
        card.onclick = () => {
          if (card.dataset.suppressClick === '1' || wrapper.classList.contains('swiped-left')) return;
          currentEditMemo = { idx };
          currentTaskForMemo = null;
          const m = memos[idx];
          document.getElementById('memo-modal-title').textContent = '编辑备忘录';
          const titleInput = document.getElementById('memo-modal-title-input');
          titleInput.style.display = 'block';
          titleInput.value = m.taskTitle || '';
          titleInput.placeholder = '备忘标题';
          document.getElementById('memo-modal-input').value = m.content || '';
          document.getElementById('memo-modal').classList.add('show');
          titleInput.focus();
        };
      });

      if (highlightMemoId) {
        const card = list.querySelector(`.memo-card[data-memo-id="${highlightMemoId}"]`);
        if (card) {
          card.classList.add('highlight');
          card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          setTimeout(() => card.classList.remove('highlight'), 1500);
        }
        highlightMemoId = null;
      }
    }

    document.getElementById('btn-new-memo').onclick = () => {
      currentEditMemo = null;
      currentTaskForMemo = { key: dateKey(selectedDate), idx: -1, task: { text: '新建备忘', id: 'new' } };
      document.getElementById('memo-modal-title').textContent = '新建备忘录';
      const titleInput = document.getElementById('memo-modal-title-input');
      titleInput.style.display = 'block';
      titleInput.value = '';
      titleInput.placeholder = '备忘标题';
      document.getElementById('memo-modal-input').value = '';
      document.getElementById('memo-modal').classList.add('show');
      titleInput.focus();
    };

    document.getElementById('memo-modal-input').addEventListener('focus', () => {
      setTimeout(() => document.getElementById('memo-modal-input').scrollIntoView({ block: 'center', behavior: 'smooth' }), 120);
    });

    document.getElementById('memo-modal-title-input').addEventListener('focus', () => {
      setTimeout(() => document.getElementById('memo-modal-title-input').scrollIntoView({ block: 'center', behavior: 'smooth' }), 120);
    });

    document.getElementById('todo-add').onclick = () => {
      const input = document.getElementById('todo-input');
      const text = input.value.trim();
      if (!text) return;
      const target = taskTargetDate || selectedDate;
      const key = dateKey(target);
      if (!todos[key]) todos[key] = [];
      todos[key].push({ id: Date.now().toString(), text, done: false, createdAt: Date.now(), completedAt: null, pinnedAt: null });
      input.value = '';
      taskTargetDate = null;
      updateInputDateBtnState();
      saveData();
      renderList();
    };

    document.getElementById('todo-input').onkeydown = e => {
      if (e.key === 'Enter') document.getElementById('todo-add').click();
    };

    document.querySelectorAll('.nav-item').forEach(n => {
      n.onclick = () => switchTab(n.dataset.tab);
    });
    document.getElementById('nav-ai-btn').onclick = () => switchTab('ai');

    (async function init() {
      applyViewportHeight();
      window.addEventListener('resize', scheduleViewportHeightUpdate);
      if (window.visualViewport) {
        window.visualViewport.addEventListener('resize', scheduleViewportHeightUpdate);
        window.visualViewport.addEventListener('scroll', scheduleViewportHeightUpdate);
      }
      await loadData();
      renderList();
      updateInputDateBtnState();
      updateInputDateBtnDisplay();
      const savedTab = Storage.get(STORAGE.tab) || 'list';
      const validTabs = ['list', 'calendar', 'memo', 'ai', 'me'];
      switchTab(validTabs.includes(savedTab) ? savedTab : 'list');
    })();
