/**
 * 每日清单与备忘录 - 应用配置
 * 便于后续上线时修改存储 key、API 地址等
 */
const CONFIG = {
  STORAGE_KEYS: {
    todos: 'daily-checklist-todos',
    memos: 'daily-checklist-memos',
    tab: 'daily-checklist-tab',
    selectedDate: 'daily-checklist-selectedDate'
  },
  // API 地址：同机部署留空 ''，跨域填完整地址如 'https://yourdomain.com'
  API_BASE: '',
  // 统一数据标识（所有人读取同一份线上数据）
  DEFAULT_SYNC_CODE: 'default',
  VERSION: '1.0.0'
};
