# Cavdal Tasks 项目交接说明

这个项目是一个 HarmonyOS 原生 HAP 待办应用，目录位于：

`/Users/siiloo/DevEcoStudioProjects/Cavdal_Tasks`

当前目标是做一个兼容 CalDAV Tasks / iCalendar VTODO 的待办软件，支持本地优先、CalDAV 同步、桌面小组件快速完成待办。

## 当前状态

已经在现有 `entry` Stage 模块中完成主要功能雏形：

- 首页待办列表 UI 已重做，参考滴答清单风格。
- 首页显示进行中待办卡片、已完成卡片、右下角添加按钮。
- 添加待办是两级交互：
  - 一级页面只填写待办标题和备注。
  - 默认不添加时间。
  - 点击日历图标后进入二级日期时间面板。
  - 二级面板可选择日期、具体时间、提醒、重复。
- CalDAV / VTODO 基础同步逻辑已实现。
- 本地任务、日历、同步队列使用关系型存储。
- 桌面小组件已注册，支持展示待办并点击完成。
- 时间显示已按北京时间格式化：
  - 昨天、今天、明天显示 `今天 HH:mm` 这种格式。
  - 其他日期显示 `M月D日`。

## 关键文件

### 页面和 UI

- `entry/src/main/ets/pages/Index.ets`
  - 主页面、设置页、添加待办一级弹窗、日期时间二级弹窗、首页任务卡片 UI。

- `entry/src/main/ets/widget/WidgetCard.ets`
  - 桌面小组件 UI。

- `entry/src/main/ets/entryformability/EntryFormAbility.ets`
  - FormExtensionAbility，小组件生命周期和点击完成任务处理。

- `entry/src/main/resources/base/profile/form_config.json`
  - 小组件配置，支持 `2*2` 和 `2*4`。

### 数据和同步

- `entry/src/main/ets/model/TaskModels.ts`
  - 核心数据模型。

- `entry/src/main/ets/data/TaskRepository.ts`
  - 本地数据库、任务 CRUD、日历、同步队列、小组件 payload。

- `entry/src/main/ets/sync/SyncService.ts`
  - 账号设置、添加任务、完成任务、同步、队列 flush。

### CalDAV / VTODO

- `entry/src/main/ets/caldav/CalDavClient.ts`
  - HTTPS Basic Auth、CalDAV discovery、PROPFIND、REPORT、GET/PUT。

- `entry/src/main/ets/caldav/VTodoCodec.ts`
  - iCalendar VTODO 解析和序列化。
  - 已支持 `DUE`、`VALARM`、`RRULE`、完成状态 mutation。

- `entry/src/main/ets/caldav/XmlHelpers.ts`
  - CalDAV XML 请求构造和响应解析。

- `entry/src/main/ets/formatters/DueTimeFormatter.ts`
  - 北京时间显示格式化。

### 测试

- `entry/src/test/LocalUnit.test.ets`
  - VTODO、CalDAV XML、提醒/重复序列化等单测。

## 构建和测试命令

本机系统 Java 不一定可用，需要使用 DevEco Studio 自带 JBR。

### 打包 HAP

```bash
PATH=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH \
JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p module=entry@default -p product=default assembleHap
```

### 跑单测

```bash
PATH=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH \
JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p module=entry@default -p product=default test
```

注意：不要并发跑 `test` 和 `assembleHap`，hvigor daemon 会提示 busy。

## 最近一次验证结果

最近已验证：

- `assembleHap` 成功
- `test` 成功

仍然会有一些 ArkTS warning，主要包括：

- `TaskRepository.ts` 中数据库 API 可能抛异常。
- `Index.ets` 中 `getContext` 和 `promptAction.showToast` deprecated。

这些目前不影响打包和测试。

## 当前已实现的功能细节

### 添加待办

在 `Index.ets` 中：

- `openAddSheet()` 初始化一级添加弹窗。
- `hasDue=false` 表示默认不设置截止时间。
- `addTask()` 中如果 `hasDue=false`，会传空字符串作为 due。
- 如果用户进入二级时间面板并点击确认，则 `hasDue=true`。

### 提醒和重复

UI 选项在 `Index.ets`：

- 提醒：`无`、`当天`、`提前一天`、`提前一周`
- 重复：`无`、`每天`、`每周`、`每月`

序列化在 `VTodoCodec.ts`：

- 提醒写入 `VALARM`
  - `当天` -> `TRIGGER:PT0S`
  - `提前一天` -> `TRIGGER:-P1D`
  - `提前一周` -> `TRIGGER:-P1W`
- 重复写入 `RRULE`
  - `每天` -> `FREQ=DAILY`
  - `每周` -> `FREQ=WEEKLY`
  - `每月` -> `FREQ=MONTHLY`

### 完成待办

App 和小组件都会调用 `SyncService.setTaskCompleted()`。

完成时会修改 VTODO：

- `STATUS:COMPLETED`
- `PERCENT-COMPLETE:100`
- `COMPLETED:<UTC timestamp>`
- `LAST-MODIFIED:<UTC timestamp>`

未完成恢复时会移除 `COMPLETED`，改回：

- `STATUS:NEEDS-ACTION`
- `PERCENT-COMPLETE:0`

### 小组件

小组件当前已做：

- `EntryFormAbility` 注册为 `ohos.extension.form`。
- `form_config.json` 支持 `2*2`、`2*4`。
- `WidgetCard.ets` 显示待办、待同步状态、最后同步时间。
- 点击小组件任务圆形勾选按钮会 `postCardAction` 到 `onFormEvent()`，然后本地完成任务并更新小组件。

## 已知问题和后续建议

### 1. 账号密码存储

计划里要求密码使用 Asset Store Kit。

目前 `CredentialStore` 逻辑需要继续确认是否已经完全符合 Asset Store Kit 的最佳实践。接手者应重点检查：

- `entry/src/main/ets/data/TaskRepository.ts`
- `CredentialStore`

### 2. CalDAV 兼容性需要真机/真实服务验证

目前实现偏基础：

- HTTPS + Basic Auth
- `.well-known/caldav` discovery
- calendar home set
- VTODO calendar discovery
- REPORT active tasks
- PUT task resources

建议用真实服务验证：

- Nextcloud Tasks
- Radicale
- Baikal
- Fastmail 或其他支持 VTODO 的 CalDAV 服务

重点测：

- discovery 路径是否兼容
- ETag / If-Match 行为
- 新建任务 PUT 的资源路径策略
- `VALARM` 和 `RRULE` 被服务端接受情况

### 3. 首页 UI 还可继续精修

用户最近要求首页参考截图：

- 不抄底部底栏
- 不抄左上/右上元素
- 主要抄中间显示内容

当前已做：

- 大标题 `待办事项`
- 白色进行中卡片
- 白色已完成卡片
- 灰色完成态
- 蓝色时间
- 右下角加号

后续可继续根据真机截图微调：

- 卡片高度
- 字号
- 已完成区域折叠/展开
- `查看更多` 行为
- 设置入口是否隐藏到其他地方

### 4. 小组件白屏问题

之前用户反馈小组件纯白。已经做过这些处理：

- `form_config.json` 加 `renderingMode: fullColor`
- 加 `enableBlurBackground`
- 小组件 UI 改成更保守的 ArkTS 结构
- 空状态也会渲染内容

如果仍白屏，建议：

- 删除桌面旧小组件后重新添加。
- 检查设备日志中的 FormExtensionAbility 和 WidgetCard 编译/运行报错。
- 临时把 `WidgetCard.ets` 简化到纯静态 Text，确认是不是数据绑定导致。

### 5. 测试 warning

`hvigor test` 会输出大量 warning，但目前最终是 `BUILD SUCCESSFUL`。

如果要清理 warning，优先处理：

- `TaskRepository.ts` 中数据库调用的异常处理。
- `Index.ets` deprecated API。

## 当前用户偏好

用户希望：

- UI 参考滴答清单/截图风格。
- 首页要简洁。
- 添加待办一级页面只填标题和备注。
- 时间选择作为二级菜单。
- 默认不设置时间。
- 桌面小组件要能快速完成待办。
- 继续增强鸿蒙原生感、圆角、气态/半透明风格。

## 给接手者的建议

接手后建议先做三件事：

1. 运行 `assembleHap` 和 `test`，确认环境一致。
2. 打开 `Index.ets`，从 `MainView()`、`ActiveTasksCard()`、`CompletedTasksCard()` 理解首页。
3. 如果继续做 UI，优先真机截图对比，因为 ArkUI 在预览、模拟器、真机上的视觉差异可能比较明显。

