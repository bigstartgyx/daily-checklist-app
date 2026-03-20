# 每日清单与备忘录

前端应用，支持清单、日历、备忘录及全文搜索。

## 目录结构

```
daily-checklist-app/
├── index.html      # 入口页面
├── css/
│   └── app.css    # 样式
├── js/
│   ├── config.js  # 配置（存储 key、API 等）
│   ├── storage.js # 存储抽象层（可切换为 API）
│   └── app.js     # 主逻辑
└── README.md
```

## 本地运行

直接双击 `index.html` 或使用任意静态服务器（如 `npx serve .`）打开即可。

## 上线准备

- **配置**：在 `js/config.js` 中修改 `STORAGE_KEYS`、`API_BASE` 等
- **存储**：当前使用 localStorage；后续在 `js/storage.js` 中接入后端 API 即可替换
- **构建**：纯静态资源，可部署到任意 Web 服务器或 CDN
