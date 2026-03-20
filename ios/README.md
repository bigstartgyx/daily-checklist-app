# BigStartNote iPhone App

这个目录现在是原生 iPhone 应用，不再通过 `WKWebView` 加载 H5。

## 当前实现

- 技术栈：`SwiftUI`
- 数据来源：直接请求同一套后端接口
  - `GET /api/data?syncCode=...`
  - `POST /api/data`
- 本地持久化：
  - 任务和备忘录快照保存在 `Application Support`
  - 当前选中日期和 Tab 保存在 `UserDefaults`
- 已原生实现：
  - 清单新增、编辑、完成、删除、置顶、改日期
  - 日历视图和按日摘要
  - 备忘录新增、编辑、删除
  - 搜索清单和备忘录
  - 云端加载与保存

## 运行

1. 打开 [project.pbxproj](/Users/daxing/code/bigstart-note/ios/BigStartNote.xcodeproj/project.pbxproj)
2. 在 Xcode 中选择 `BigStartNote` scheme
3. 选择一个 iPhone 模拟器或真机
4. 按 `Cmd + R`

## 配置

当前 Debug 和 Release 默认都使用：

- `https://121.41.198.212/`

如果后续切域名，只需要修改：

- [Debug-Info.plist](/Users/daxing/code/bigstart-note/ios/Config/Debug-Info.plist)
- [Release-Info.plist](/Users/daxing/code/bigstart-note/ios/Config/Release-Info.plist)

可选配置：

- `BaseURL`: 服务地址
- `SyncCode`: 同步标识，默认 `default`

## 说明

- 项目里保留了早期的文件名，例如 [WebViewModel.swift](/Users/daxing/code/bigstart-note/ios/BigStartNote/WebViewModel.swift) 和 [WebViewContainer.swift](/Users/daxing/code/bigstart-note/ios/BigStartNote/WebViewContainer.swift)，但它们现在承载的是原生状态与原生视图，不再包含 WebView 运行逻辑。
