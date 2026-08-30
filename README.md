# 橘味儿配音（Juweier Voice）

Windows / Android / iOS 三端 AI 配音与角色换声客户端。

## 当前产品方向

前期以音频处理与短剧配音为核心，优先把换声、对白分离、环境音还原、角色音色管理与成品导出做稳定、做简单。视频生成能力继续保留，但在客户端中标记为“开发测试中”，暂不作为正式生产主流程。

## 已实现 / 已验证

- AI短剧配音
- 音视频导入换声
- Seed-VC V2 角色音色转换
- Roformer 对白 / BGM / 环境声分离工作流
- 环境音保留与重新混音
- 原视频画面回写与成品 MP4 导出
- AI演员（Voice ID）设计
- AI声音文字描述设计入口
- 项目中心与批量处理界面
- NOVRIA Voice Worker 健康检测

## AI 视频（开发测试中）

本地 LTX-Video 文生视频链路已完成技术验证，当前作为实验能力保留。生成速度、画质、显存占用和长视频稳定性仍在持续优化，暂不建议作为正式生产功能使用。

客户端建议展示：

> AI 视频 · 开发测试中  
> 本地 AI 视频生成能力正在持续开发和优化。当前功能可用于体验测试，生成速度、画质与稳定性仍在改善。

## 服务端

当前 VC Worker 默认地址：`http://127.0.0.1:18110`。
移动端使用时需要在设置中填写运行 NOVRIA Voice Server 的电脑局域网/公网 API 地址。

音频主服务后续统一为同一套 API，目标包括：媒体分析、对白/环境音分离、Seed-VC 换声、混音、原视频回写、项目任务与批量处理。

## 构建

GitHub Actions 会在 main 分支更新时自动构建：

- Windows Release
- Android APK Release
- iOS unsigned Runner.app

正式 iOS IPA / TestFlight 需要后续加入 Apple Developer 签名配置。
