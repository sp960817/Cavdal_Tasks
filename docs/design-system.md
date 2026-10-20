# 拾序 · HarmonyOS 界面

2026-10-20。与 Android 端「拾序」共用品牌和插画，交互使用 ArkUI / FormKit 原生组件。

## 视觉与布局

- 暖白底色 `#F5F3EE`、蓝灰强调色 `#4C6D8D`；深色底 `#10171D`、卡片 `#1B252E`、强调色 `#A9CAE7`。
- 深色主按钮使用深色文字 `#193244`，避免浅蓝底上的白字对比不足。
- 首页包含日期、紧凑插画总览、动态任务统计、可滚动独立任务卡和已完成入口。短窗口优先保留任务列表，搜索时收起总览。
- 新建和编辑使用统一原生半模态面板，日期、时间、提醒、重复分别操作；更改日期时间不会覆盖已选提醒。清除日期时同时清除依赖日期的提醒和重复。
- 设置分为同步账号、外观交互、数据管理；卡片材质使用可见缩略预览。
- 桌面服务卡片保留宿主配色、滚动列表和独立完成操作，支持现有 1×2、2×2、2×4、4×4 配置。2×2 上下边距各为 6vp，按列表实际高度完整显示三条待办，后续事项继续滚动；正文为 13sp，使用宿主适配的不透明深浅文字。

## 原生沉浸材质

API 26 的底部导航使用 `Tabs.barFloatingStyle` 和 `uiMaterial.ImmersiveMaterial`；新建、编辑、已完成面板使用 `SheetOptions.systemMaterial`。`colorInvert: false` 配合明确的浅深色资源。弹层不叠加不透明底色遮盖系统材质。

兼容 API 24 的导航保留 `HdsTabs` / `hdsMaterial`；弹层采用官方 blur 回退。SDK API 可用性判断与真机渲染验证分别进行。普通正文卡片使用主题色和渐变，不将这些表面称为系统气态玻璃。

- [华为沉浸光感接入指南](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-immersive-light-sense-enable)
- [官方 Spatialization 示例](https://gitcode.com/HarmonyOS_Samples/Spatialization)

## 素材来源

三个透明 PNG 复用自本项目 Android 端 2026-10-19 的原创 AI 素材。原始生成方式为内置 `image_gen`，本次保留原始透明像素，没有再次生成或修改图片。

| HarmonyOS 资源 | Android 来源 | 使用位置 |
|---|---|---|
| `brand_icon.png` | `launcher_icon_art.png` | 应用图标、启动图标、设置品牌卡 |
| `material_planner.png` | 同名文件 | 首页总览、连接引导 |
| `material_empty_tray.png` | 同名文件 | 清单空态、服务卡片空态 |

素材位于 `entry/src/main/resources/base/media/`，应用级图标同时位于 `AppScope/resources/base/media/`。源素材说明与生成提示词见 Android 仓库的 `docs/design-assets.md`。所有图片离线随 HAP 打包，无运行时图片服务。

## 验证边界

本次使用本机 DevEco 26.0.0.621 / SDK 26.0.0.32 Beta2，目标 API 26、最低兼容 API 24。官方已有 Release 工具链，本次未升级本机 SDK。

完成签名 HAP 构建，并在用户提供的鸿蒙 7 / API 26 手机覆盖安装。浅深色首页、设置、原生弹层、搜索无结果与现有 2×2 服务卡片进行了设备检查。统计在同步后刷新，提醒选项在调整日期后保留，并在未保存草稿中验证。

其他服务卡片尺寸和 API 24 回退分支完成编译与代码检查，未逐一真机验证。调试输入只触发了当前设备的输入法候选栏，不应据此宣称覆盖所有软键盘布局。验证截图与控件树保留在本地 `.work/qa/`，不纳入源码发布。

最终签名包 SHA-256：`9DB24ED2C56D9440AC6417C9095510DA04B400919F47241C18A69D666D202B73`。该包已覆盖安装；设备保持原有深色模式。

## 编辑与刷新回归

- `VTodoCodec.parse` 只读取 VTODO 直接属性。VALARM 的 DESCRIPTION 是提醒文字，不能作为任务正文；依据 [RFC 5545 的提醒组件定义](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.6.6)。旧缓存从保留的原始 ICS 重新读取真实正文，保留同步状态、时间戳及其他字段；真正与标题相同的正文不会被清空。
- 编辑标题和正文使用独立草稿状态，弹层内容保持稳定结构，避免关闭期间清空内容导致下一次打开需要点击两次。
- 非虚拟 Repeat 对相同 key 保留旧条目；依据 [OpenHarmony 实现](https://github.com/openharmony/arkui_ace_engine/blob/master/frameworks/bridge/declarative_frontend/state_mgmt/src/lib/partial_update/pu_repeat_impl.ts)。应用和服务卡片使用包含实际内容的稳定 key，排除每次导入变化的 `updatedAt`，使编辑后的文字和再次点击所读取的数据同步更新。保存编辑后主动刷新服务卡片。

新增 5 项解析回归测试，本机执行实际源码和测试体全部通过，并检查旧缓存恢复及内容 key 稳定性；未将本机逻辑测试等同于设备端 Hypium 执行。

真机使用一条临时待办完成「修改标题、填写正文、清空正文、保留提醒、保存后即时列表刷新、单击重开编辑、桌面同步更新」检查。验证后已删除该临时记录，并重启同步确认原有任务数量恢复。现有 2×2 卡片在设备实际尺寸下完整显示三条待办，最终截图为本地 `.work/qa/widget-three-rows-final.png`。

## 卡片样式切换回归

- 真机复现前台恢复触发同步期间单击新样式：桌面先收到新样式，随后被同步开始时读取的旧设置覆盖。同步结束原先保存整个设置对象，是偶发切换失效的主要原因。
- 账号、同步时间、握姿与卡片样式分别写入对应设置项；样式保存按点击顺序执行。桌面刷新依次发送并在执行时读取当前设置，避免较早的刷新最后抵达；界面只处理最后一次选择的状态与失败回退。
- 本机执行实际源码、模拟系统存储和卡片接口的 4 项并发回归全部通过，覆盖同步交错、连续选择、刷新乱序和写入失败后恢复；基线代码为 1/4 通过。该结果属于本机逻辑验证，不是设备端 Hypium 测试。
- 鸿蒙 7 / API 26 真机逐一验证通透、轻雾、磨砂、凝脂的单击选择及桌面实际背景，覆盖预览区和文字区点击；连续切换 8 次后保留最后一次选择，重启应用后设置与桌面均保持轻雾。最终截图与控件树保留于本地 `.work/qa/appearance-fixed-*`。

## 分层图标背景修正

原前景 PNG 为 1280×1280，背景 SVG 为 192×192，设备桌面将背景显示为左上角的一块浅色区域，其余外圈透明。两处 `brand_background.svg` 的画布、viewBox 和填充矩形现统一为 1280×1280，与原始前景保持一致；保留原纸片及蓝色折角素材。

签名构建及覆盖安装成功，真机在桌面和展开的文件夹中确认浅蓝灰背景完整铺满、白色角块消失。前后对照截图分别为本地 `.work/qa/icon-edge-inspection.png` 和 `.work/qa/icon-background-fixed-folder-detail.png`。
