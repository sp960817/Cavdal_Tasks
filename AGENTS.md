# HarmonyOS NEXT / ArkTS 开发规则

本项目是 HarmonyOS NEXT 原生应用，使用 ArkTS + ArkUI 开发。

## 最高优先级

1. UI 实现必须优先使用 HarmonyOS 官方 ArkUI 组件、官方布局、官方交互能力。
2. 系统能力必须优先使用 HarmonyOS SDK 官方 API、官方 Kit、官方 @ohos / @kit 模块。
3. 不要优先引入第三方 UI 库、跨端框架、npm/ohpm 包来替代官方组件。
4. 不要把 Android、React、Vue、Flutter、Web 前端习惯直接套到 ArkUI 代码里。
5. 生成代码前，先检查项目现有 ArkTS / ArkUI 写法，保持一致。

## 组件选择规则

当需求涉及常见 UI 时，优先考虑官方组件：

- 文本：Text / Span / RichEditor 等官方文本组件
- 图片：Image
- 输入：TextInput / TextArea / Search
- 按钮：Button
- 列表：List / Grid / WaterFlow
- 布局：Column / Row / Stack / Flex / GridRow / GridCol
- 导航：Navigation / NavDestination / Tabs / TabContent
- 弹窗：AlertDialog / CustomDialog / bindSheet / bindContentCover
- 滚动：Scroll / List / Swiper
- 状态管理：@State / @Prop / @Link / @Provide / @Consume / @Observed / @ObjectLink / @Track

只有在官方组件无法满足需求时，才允许封装自定义组件。

## API 使用规则

使用 HarmonyOS API 时必须：

1. 优先查找官方 HarmonyOS 文档里的 API。
2. 确认 API 的起始版本，不要使用超出当前项目 SDK/API 版本的接口。
3. 避免使用已废弃 API。
4. 如果引入第三方库，必须先说明：
   - 官方 API 为什么不能满足；
   - 第三方库解决了什么问题；
   - 是否影响性能、体积、权限、审核和维护；
   - 是否有 HarmonyOS NEXT 兼容风险。

## 禁止行为

- 禁止默认推荐 React Native、Flutter、uni-app、Taro 等跨端方案，除非任务明确要求。
- 禁止为了省事引入 lodash、moment、axios、UI 框架等依赖，除非项目已经使用或确有必要。
- 禁止生成 Android/Kotlin/Java/iOS/Swift 风格的代码。
- 禁止使用 WebView/ArkWeb 代替原生 ArkUI 页面，除非需求明确是网页容器。
- 禁止凭记忆乱写 HarmonyOS API 名称；不确定时必须先查项目代码或官方文档。

## 输出代码要求

- 使用 ArkTS。
- 使用声明式 ArkUI 写法。
- 保持项目已有目录结构和命名风格。
- 新增组件优先放在项目现有 components/common 目录约定中。
- 修改前先说明会改哪些文件。
- 修改后给出验证方式，例如构建、预览、单元测试或手动验证步骤。
