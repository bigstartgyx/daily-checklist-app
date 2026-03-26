/**
 * 每日清单与备忘录 - 后端 API
 * Node.js + Express + MySQL
 */
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const mysql = require('mysql2/promise');
const path = require('path');
const crypto = require('crypto');
const RPCClient = require('@alicloud/pop-core');

const app = express();
const PORT = process.env.PORT || 3000;
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }
});

const DEEPSEEK_API_BASE = (process.env.DEEPSEEK_API_BASE || 'https://api.deepseek.com').replace(/\/+$/, '');
const DEEPSEEK_API_KEY = (process.env.DEEPSEEK_API_KEY || '').trim();
const DEEPSEEK_MODEL = (process.env.DEEPSEEK_MODEL || 'deepseek-chat').trim();
const ALIYUN_AK_ID = (process.env.ALIYUN_AK_ID || '').trim();
const ALIYUN_AK_SECRET = (process.env.ALIYUN_AK_SECRET || '').trim();
const ALIYUN_ASR_APPKEY = (process.env.ALIYUN_ASR_APPKEY || '').trim();
const ALIYUN_ASR_REGION = (process.env.ALIYUN_ASR_REGION || 'cn-shanghai').trim();
const ALIYUN_ASR_GATEWAY = (process.env.ALIYUN_ASR_GATEWAY || 'https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr').trim();
const ALIYUN_ASR_TOKEN_ENDPOINT = (process.env.ALIYUN_ASR_TOKEN_ENDPOINT || 'http://nls-meta.cn-shanghai.aliyuncs.com').trim();
const ALIYUN_ASR_SAMPLE_RATE = Number(process.env.ALIYUN_ASR_SAMPLE_RATE || 16000);
const AI_ACCESS_TOKENS = new Set(
  (process.env.AI_ACCESS_TOKENS || process.env.AI_ACCESS_TOKEN || '')
    .split(',')
    .map(value => value.trim())
    .filter(Boolean)
);

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

function jsonError(res, status, message) {
  return res.status(status).json({ ok: false, message });
}

function extractBearerToken(headerValue = '') {
  if (!headerValue.startsWith('Bearer ')) return '';
  return headerValue.slice(7).trim();
}

function requireAIToken(req, res, next) {
  if (AI_ACCESS_TOKENS.size === 0) {
    return jsonError(res, 503, 'AI 服务令牌白名单未配置。');
  }

  const token = extractBearerToken(req.headers.authorization || '');
  if (!token || !AI_ACCESS_TOKENS.has(token)) {
    return jsonError(res, 401, 'AI 服务访问令牌无效。');
  }

  next();
}

function isDeepSeekConfigured() {
  return Boolean(DEEPSEEK_API_KEY);
}

function isAliyunASRConfigured() {
  return Boolean(ALIYUN_AK_ID && ALIYUN_AK_SECRET && ALIYUN_ASR_APPKEY);
}

function normalizeIntentKind(intent) {
  if (intent === 'task' || intent === 'memo' || intent === 'task_with_memo' || intent === 'unknown') {
    return intent;
  }
  return 'unknown';
}

function normalizeDateKey(value, fallback) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value || '') ? value : fallback;
}

function sanitizeIntentPayload(raw, fallbackDateKey) {
  const intent = normalizeIntentKind(raw.intent);

  const taskText = typeof raw.task?.text === 'string' ? raw.task.text.trim() : '';
  const memoTitle = typeof raw.memo?.title === 'string' ? raw.memo.title.trim() : '';
  const memoContent = typeof raw.memo?.content === 'string' ? raw.memo.content.trim() : '';

  return {
    transcript: typeof raw.transcript === 'string' ? raw.transcript.trim() : '',
    intent,
    task: taskText
      ? {
          text: taskText,
          dateKey: normalizeDateKey(raw.task?.dateKey, fallbackDateKey)
        }
      : null,
    memo: memoTitle || memoContent
      ? {
          title: memoTitle || '备忘',
          content: memoContent,
          dateKey: normalizeDateKey(raw.memo?.dateKey, fallbackDateKey)
        }
      : null,
    message: typeof raw.message === 'string' ? raw.message.trim() : ''
  };
}

function extractJSON(text = '') {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.indexOf('{');
  const end = candidate.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) {
    throw new Error('模型未返回合法 JSON。');
  }
  return JSON.parse(candidate.slice(start, end + 1));
}

function extractAssistantText(payload) {
  const content = payload?.choices?.[0]?.message?.content;
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map(item => {
        if (typeof item === 'string') return item;
        if (item && typeof item.text === 'string') return item.text;
        return '';
      })
      .join('');
  }
  return '';
}

function buildIntentMessages({ input, typeHint, referenceDate, timeZone }) {
  const systemPrompt = [
    '你是一个待办事项与备忘录解析器。',
    '你的任务是把用户输入解析成严格 JSON。',
    '不要闲聊，不要解释，不要输出 JSON 以外的内容。',
    '返回字段必须完整：transcript、intent、task、memo、message。',
    'intent 只能是 task、memo、task_with_memo、unknown。',
    'task 必须包含 text 和 dateKey。',
    'memo 必须包含 title、content、dateKey。',
    'dateKey 必须是 yyyy-MM-dd 格式。',
    '如果 typeHint=task，优先输出 task 或 task_with_memo。',
    '如果 typeHint=memo，优先输出 memo。',
    '如果无法可靠判断，返回 intent=unknown。'
  ].join('\n');

  const userPrompt = JSON.stringify({
    input,
    typeHint,
    referenceDate,
    timeZone,
    requirements: [
      '结合 referenceDate 和 timeZone 解析今天、明天、周六下午等相对时间。',
      '任务文本应尽量简洁，不要把备注塞进 task.text。',
      '当用户说“备注”、“记得”、“注意”等补充信息时，优先写入 memo.content。',
      '如果只有备忘性质内容，不要强行创建 task。'
    ],
    outputExample: {
      transcript: input,
      intent: 'task_with_memo',
      task: {
        text: '和好友聚聚',
        dateKey: referenceDate
      },
      memo: {
        title: '聚会备注',
        content: '下午见面',
        dateKey: referenceDate
      },
      message: ''
    }
  });

  return [
    { role: 'system', content: systemPrompt },
    { role: 'user', content: userPrompt }
  ];
}

async function callDeepSeekChat(messages) {
  if (!isDeepSeekConfigured()) {
    const error = new Error('DeepSeek 文本服务未配置。');
    error.statusCode = 503;
    throw error;
  }

  const response = await fetch(`${DEEPSEEK_API_BASE}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${DEEPSEEK_API_KEY}`
    },
    body: JSON.stringify({
      model: DEEPSEEK_MODEL,
      temperature: 0.1,
      messages
    })
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = data?.error?.message || data?.message || 'DeepSeek 文本请求失败。';
    const error = new Error(message);
    error.statusCode = response.status;
    throw error;
  }

  return extractAssistantText(data);
}

function buildTranscriptNormalizationMessages({ transcript, referenceDate, timeZone }) {
  const systemPrompt = [
    '你是中文语音转写纠错助手。',
    '你只能根据已有转写文本进行纠错、补标点、断句和口语整理。',
    '不要编造未说出的信息，不要扩写，不要总结。',
    '保留日期、时间、数字、金额、电话号码、地名、人名和专有名词的原始含义。',
    '输出纯文本，不要解释。'
  ].join('\n');

  const userPrompt = JSON.stringify({
    transcript,
    referenceDate,
    timeZone,
    requirements: [
      '纠正常见同音错字和明显 ASR 错词。',
      '补充中文标点并按语义断句。',
      '保留用户原本的语气和含义。',
      '如果原文本已经足够好，仅返回轻微整理后的文本。'
    ]
  });

  return [
    { role: 'system', content: systemPrompt },
    { role: 'user', content: userPrompt }
  ];
}

const DeepSeekTextIntentService = {
  async parse({ input, typeHint, referenceDate, timeZone }) {
    const assistantText = await callDeepSeekChat(
      buildIntentMessages({ input, typeHint, referenceDate, timeZone })
    );
    const parsed = extractJSON(assistantText);
    return sanitizeIntentPayload(
      {
        transcript: parsed.transcript || input,
        intent: parsed.intent,
        task: parsed.task,
        memo: parsed.memo,
        message: parsed.message
      },
      referenceDate
    );
  }
};

const TranscriptPostProcessor = {
  async normalize({ transcript, referenceDate, timeZone }) {
    const trimmed = typeof transcript === 'string' ? transcript.trim() : '';
    if (!trimmed) {
      return {
        transcript: '',
        provider: null
      };
    }

    if (!isDeepSeekConfigured()) {
      return {
        transcript: trimmed,
        provider: null
      };
    }

    const assistantText = await callDeepSeekChat(
      buildTranscriptNormalizationMessages({ transcript: trimmed, referenceDate, timeZone })
    );
    const normalized = assistantText.trim();
    return {
      transcript: normalized || trimmed,
      provider: 'deepseek'
    };
  }
};

const SpeechTranscriptionProvider = {
  async transcribe(file) {
    if (!isAliyunASRConfigured()) {
      const error = new Error('阿里云 ASR 未配置。');
      error.statusCode = 503;
      throw error;
    }

    if (!file?.buffer?.length) {
      const error = new Error('未收到有效音频数据。');
      error.statusCode = 400;
      throw error;
    }

    const tokenClient = new RPCClient({
      accessKeyId: ALIYUN_AK_ID,
      accessKeySecret: ALIYUN_AK_SECRET,
      endpoint: ALIYUN_ASR_TOKEN_ENDPOINT,
      apiVersion: '2019-02-28'
    });
    const tokenResult = await tokenClient.request('CreateToken', {}, { method: 'POST' });
    const token = tokenResult?.Token?.Id;
    const tokenExpireTime = tokenResult?.Token?.ExpireTime ?? null;
    if (!token) {
      const error = new Error('阿里云 ASR Token 获取失败。');
      error.statusCode = 502;
      throw error;
    }

    const requestURL = new URL(ALIYUN_ASR_GATEWAY);
    requestURL.searchParams.set('appkey', ALIYUN_ASR_APPKEY);
    requestURL.searchParams.set('format', 'wav');
    requestURL.searchParams.set('sample_rate', String(ALIYUN_ASR_SAMPLE_RATE));
    requestURL.searchParams.set('enable_punctuation_prediction', 'true');
    requestURL.searchParams.set('enable_inverse_text_normalization', 'true');

    const response = await fetch(requestURL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': String(file.size),
        'X-NLS-Token': token
      },
      body: file.buffer
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok || (typeof data?.status === 'number' && data.status !== 20000000)) {
      const message = data?.message || data?.Message || '阿里云语音识别失败。';
      const error = new Error(message);
      error.statusCode = response.status >= 400 ? response.status : 502;
      throw error;
    }

    const transcript = typeof data?.result === 'string' ? data.result.trim() : '';
    if (!transcript) {
      const error = new Error('阿里云语音识别未返回有效文本。');
      error.statusCode = 502;
      throw error;
    }

    return {
      transcript,
      requestId: data?.request_id || data?.RequestId || null,
      audioDuration: null,
      provider: 'aliyun',
      tokenExpireTime
    };
  }
};

app.use(cors());
app.use(express.json({ limit: '2mb' }));

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

app.get('/api/ai/health', requireAIToken, async (req, res) => {
  if (!isDeepSeekConfigured()) {
    return jsonError(res, 503, 'DeepSeek 文本服务未配置。');
  }

  res.json({
    ok: true,
    textConfigured: true,
    voiceConfigured: isAliyunASRConfigured(),
    message: isAliyunASRConfigured() ? 'AI 服务可用。' : '文本服务可用，但阿里云语音识别未配置。'
  });
});

app.post('/api/ai/text-intent', requireAIToken, async (req, res) => {
  const input = typeof req.body.input === 'string' ? req.body.input.trim() : '';
  const typeHint = ['task', 'memo', 'auto'].includes(req.body.typeHint) ? req.body.typeHint : 'auto';
  const referenceDate = /^\d{4}-\d{2}-\d{2}$/.test(req.body.referenceDate || '') ? req.body.referenceDate : new Date().toISOString().slice(0, 10);
  const timeZone = typeof req.body.timeZone === 'string' && req.body.timeZone.trim() ? req.body.timeZone.trim() : 'Asia/Shanghai';

  if (!input) {
    return jsonError(res, 400, '请输入待解析内容。');
  }

  try {
    const result = await DeepSeekTextIntentService.parse({
      input,
      typeHint,
      referenceDate,
      timeZone
    });

    res.json({ ok: true, ...result });
  } catch (error) {
    console.error(error);
    jsonError(res, error.statusCode || 500, error.message || 'AI 文本解析失败。');
  }
});

app.post('/api/ai/voice-intent', requireAIToken, upload.single('audio'), async (req, res) => {
  const referenceDate = /^\d{4}-\d{2}-\d{2}$/.test(req.body.referenceDate || '') ? req.body.referenceDate : new Date().toISOString().slice(0, 10);
  const timeZone = typeof req.body.timeZone === 'string' && req.body.timeZone.trim() ? req.body.timeZone.trim() : 'Asia/Shanghai';

  if (!req.file) {
    return jsonError(res, 400, '未收到音频文件。');
  }

  try {
    const asrStartedAt = Date.now();
    const transcription = await SpeechTranscriptionProvider.transcribe(req.file);
    const asrElapsedMs = Date.now() - asrStartedAt;
    const postProcessStartedAt = Date.now();
    const normalized = await TranscriptPostProcessor.normalize({
      transcript: transcription.transcript,
      referenceDate,
      timeZone
    });
    const postProcessElapsedMs = Date.now() - postProcessStartedAt;
    const transcriptForIntent = normalized.transcript || transcription.transcript;
    const result = await DeepSeekTextIntentService.parse({
      input: transcriptForIntent,
      typeHint: 'auto',
      referenceDate,
      timeZone
    });
    console.log('[voice-intent]', {
      audioBytes: req.file.size,
      audioDuration: transcription.audioDuration,
      asrElapsedMs,
      postProcessElapsedMs,
      transcriptLength: transcriptForIntent.length,
      asrProvider: transcription.provider,
      postProcessedBy: normalized.provider,
      requestId: transcription.requestId
    });
    res.json({
      ok: true,
      transcript: result.transcript,
      transcriptRaw: transcription.transcript,
      transcriptNormalized: transcriptForIntent,
      asrProvider: transcription.provider,
      postProcessedBy: normalized.provider,
      ...result
    });
  } catch (error) {
    console.error(error);
    jsonError(res, error.statusCode || 500, error.message || '语音解析失败。');
  }
});

// 健康检查
app.get('/api/health', (req, res) => res.json({ ok: true, timestamp: Date.now() }));

app.listen(PORT, () => {
  console.log(`API 运行于 http://0.0.0.0:${PORT}`);
});

initDb();
