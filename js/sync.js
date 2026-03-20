/**
 * 云端存储模块 - 直接读写线上数据库（无同步码）
 */
const Sync = {
  getSyncCode() {
    return (typeof CONFIG !== 'undefined' && CONFIG.DEFAULT_SYNC_CODE) ? CONFIG.DEFAULT_SYNC_CODE : 'default';
  },

  async loadFromCloud() {
    const base = (typeof CONFIG !== 'undefined' && CONFIG.API_BASE) ? CONFIG.API_BASE : '';
    const code = this.getSyncCode();
    try {
      const res = await fetch(`${base}/api/data?syncCode=${encodeURIComponent(code)}`);
      const data = await res.json();
      if (data.ok && data.todos !== undefined) return { todos: data.todos || {}, memos: data.memos || [] };
      return null;
    } catch (e) {
      console.warn('Sync load failed:', e);
      return null;
    }
  },

  async saveToCloud(todos, memos) {
    const base = (typeof CONFIG !== 'undefined' && CONFIG.API_BASE) ? CONFIG.API_BASE : '';
    const code = this.getSyncCode();
    try {
      await fetch(`${base}/api/data`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ syncCode: code, todos: todos || {}, memos: memos || [] })
      });
    } catch (e) {
      console.warn('Sync save failed:', e);
    }
  }
};
