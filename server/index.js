/**
 * 每日清单与备忘录 - 后端 API
 * Node.js + Express + MySQL
 */
const express = require('express');
const cors = require('cors');
const mysql = require('mysql2/promise');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// 数据库配置（部署时改为环境变量或宝塔配置）
const dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || 'gyx6663223',
  password: process.env.DB_PASSWORD || 'gyx6663223',
  database: process.env.DB_NAME || 'daily_checklist',
  charset: 'utf8mb4'
};

let pool;

async function initDb() {
  try {
    pool = mysql.createPool(dbConfig);
    await pool.query('SELECT 1');
    console.log('数据库连接成功');
  } catch (e) {
    console.error('数据库连接失败:', e.message);
    process.exit(1);
  }
}

app.use(cors());
app.use(express.json({ limit: '1mb' }));

// 静态文件（前端）
app.use(express.static(path.join(__dirname, '..')));

// 获取数据
app.get('/api/data', async (req, res) => {
  const syncCode = (req.query.syncCode || '').trim();
  if (!syncCode || syncCode.length < 4) {
    return res.status(400).json({ ok: false, message: '同步码无效' });
  }
  try {
    const [rows] = await pool.execute(
      'SELECT todos_json, memos_json FROM user_data WHERE sync_code = ?',
      [syncCode]
    );
    if (!rows.length) {
      return res.json({ ok: true, todos: {}, memos: [] });
    }
    const r = rows[0];
    const todos = typeof r.todos_json === 'string' ? JSON.parse(r.todos_json || '{}') : r.todos_json;
    const memos = typeof r.memos_json === 'string' ? JSON.parse(r.memos_json || '[]') : r.memos_json;
    res.json({ ok: true, todos, memos });
  } catch (e) {
    console.error(e);
    res.status(500).json({ ok: false, message: '服务器错误' });
  }
});

// 保存数据
app.post('/api/data', async (req, res) => {
  const { syncCode, todos = {}, memos = [] } = req.body;
  if (!syncCode || (typeof syncCode !== 'string') || syncCode.trim().length < 4) {
    return res.status(400).json({ ok: false, message: '同步码无效' });
  }
  const code = syncCode.trim();
  const todosStr = JSON.stringify(todos);
  const memosStr = JSON.stringify(memos);
  try {
    await pool.execute(
      `INSERT INTO user_data (sync_code, todos_json, memos_json) VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE todos_json = VALUES(todos_json), memos_json = VALUES(memos_json)`,
      [code, todosStr, memosStr]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ ok: false, message: '保存失败' });
  }
});

// 健康检查
app.get('/api/health', (req, res) => res.json({ ok: true, timestamp: Date.now() }));

app.listen(PORT, () => {
  console.log(`API 运行于 http://0.0.0.0:${PORT}`);
});

initDb();
