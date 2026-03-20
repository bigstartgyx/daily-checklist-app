# 方案二：Git 拉取更新指南

## 一、本地准备（已完成）

- Git 已初始化，初始提交已创建

## 二、创建远程仓库

1. 登录 [GitHub](https://github.com) 或 [Gitee](https://gitee.com)
2. 新建仓库，例如 `daily-checklist-app`（不要勾选「初始化 README」）
3. 记下仓库地址，如：
   - GitHub: `https://github.com/你的用户名/daily-checklist-app.git`
   - Gitee: `https://gitee.com/你的用户名/daily-checklist-app.git`

## 三、关联并推送

在项目目录执行（替换为你的仓库地址）：

```bash
cd e:\bigstart-notes\daily-checklist-app
git remote add origin https://github.com/你的用户名/daily-checklist-app.git
git branch -M main
git push -u origin main
```

> 若使用 Gitee，将 `github.com` 改为 `gitee.com` 即可。

## 四、服务器首次部署

### 4.1 登录服务器

- **方式 A**：宝塔面板 → 终端（或左侧「终端」入口）
- **方式 B**：本地 PowerShell / CMD 执行：`ssh root@121.41.198.212`（替换为你的服务器 IP）

### 4.2 首次克隆并启动

在服务器终端**逐行**执行（把下面的 `bigstartgyx` 换成你的 GitHub 用户名）：

```bash
# 1. 进入父目录
cd /www/wwwroot/daily-checklist

# 2. 若已有旧目录，先备份
mv daily-checklist-app daily-checklist-app.bak 2>/dev/null || true

# 3. 克隆仓库（即 git clone，需先 yum install -y git）
git clone https://github.com/bigstartgyx/daily-checklist-app.git

# 4. 让 update.sh 可执行
chmod +x daily-checklist-app/update.sh

# 5. 进入 server 并安装依赖
cd daily-checklist-app/server
npm config set registry https://registry.npmjs.org/
npm install

# 6. 配置数据库：编辑 index.js 中的 dbConfig，或后续用 PM2 环境变量

# 7. 启动服务
./node_modules/.bin/pm2 start index.js --name daily-checklist-api
./node_modules/.bin/pm2 save
./node_modules/.bin/pm2 startup
```

---

## 五、日常更新（本地 push 后）

### 5.1 本地推送

```bash
git add .
git commit -m "更新说明"
git push
```

### 5.2 服务器拉取并重启

**方式 A：在宝塔终端执行**

1. 宝塔 → 终端
2. 输入：

```bash
cd /www/wwwroot/daily-checklist/daily-checklist-app && ./update.sh
```

**方式 B：SSH 一键执行（本地执行，需已配置免密）**

```bash
ssh root@121.41.198.212 "cd /www/wwwroot/daily-checklist/daily-checklist-app && ./update.sh"
```

**方式 C：宝塔计划任务（可选，自动定时拉取）**

1. 宝塔 → 计划任务
2. 添加任务：类型选「Shell 脚本」
3. 执行周期：如每 5 分钟
4. 脚本内容：`cd /www/wwwroot/daily-checklist/daily-checklist-app && ./update.sh`
