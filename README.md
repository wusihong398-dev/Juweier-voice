# 橘味儿AI声演（Juweier Voice）

Windows / Android / iOS 三端 AI 配音与角色换声客户端。

## v0.1.0

- AI短剧配音
- 音视频导入换声
- Seed-VC V2 角色音色转换
- Roformer 对白 / BGM / 环境声分离工作流
- AI演员（Voice ID）设计
- AI声音文字描述设计入口
- 项目中心与批量处理界面
- NOVRIA Voice Worker 健康检测

## 服务端

当前 VC Worker 默认地址：`http://127.0.0.1:18110`。
移动端使用时需要在设置中填写运行 NOVRIA Voice Server 的电脑局域网/公网 API 地址。

## 构建

GitHub Actions 会在 main 分支更新时自动构建：

- Windows Release
- Android APK Release
- iOS unsigned Runner.app

正式 iOS IPA / TestFlight 需要后续加入 Apple Developer 签名配置。
