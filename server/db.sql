-- 每日清单与备忘录 数据库表结构
-- 在宝塔 MySQL 中执行

CREATE DATABASE IF NOT EXISTS daily_checklist DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE daily_checklist;

-- 用户数据表（按同步码区分，同一同步码多端共享数据）
CREATE TABLE IF NOT EXISTS user_data (
  id INT AUTO_INCREMENT PRIMARY KEY,
  sync_code VARCHAR(12) NOT NULL UNIQUE COMMENT '同步码，6-12位',
  todos_json LONGTEXT NOT NULL COMMENT '清单 JSON',
  memos_json LONGTEXT NOT NULL COMMENT '备忘录 JSON',
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_sync_code (sync_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户数据';
