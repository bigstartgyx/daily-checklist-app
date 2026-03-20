/**
 * 存储抽象层 - 当前使用 localStorage
 * 后续接入后端 API 时可在此替换实现，无需改动业务代码
 */
const Storage = {
  get(key) {
    try {
      return localStorage.getItem(key);
    } catch (e) {
      console.warn('Storage.get failed:', e);
      return null;
    }
  },

  set(key, value) {
    try {
      localStorage.setItem(key, value);
      return true;
    } catch (e) {
      console.warn('Storage.set failed:', e);
      return false;
    }
  },

  remove(key) {
    try {
      localStorage.removeItem(key);
      return true;
    } catch (e) {
      console.warn('Storage.remove failed:', e);
      return false;
    }
  }
};
