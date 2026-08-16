# 💗 Pink Music（Flutter 版）

> 基于哔哩哔哩（B 站）公开接口的 Android 移动端音乐播放器 🎧🎶

非官方项目，与哔哩哔哩无任何官方关联或背书。本仓库为桌面版 [pink-music-app](https://github.com/Rayson-Liu/pink-music-app) 的 Flutter 迁移版本。

## ✨ 特色

- 🔐 支持登录 Bilibili（扫码登录 + 短信验证码登录），一键同步收藏夹
- 🎼 搜索 B 站音乐、音乐区推荐、播放历史
- 🎧 高品质音频播放，优先拉取更高码率音频流
- 🔥 支持音频下载（`.m4a`），下载管理、进度展示、分享文件
- 🎚️ 10 段均衡器 — 覆盖 31–16K Hz，±12dB，内置 8 种预设（默认/流行/摇滚/爵士/古典/电子/人声/低音增强）
- 🎤 智能歌词 — 网易云 / QQ 音乐双源匹配，支持手动搜索、逐行微调偏移、字号调节、翻译 / 罗马音
- 🧩 多P（分P）支持 — 分P 播放、切P、按需勾选分P 加入歌单
- 📂 本地歌单管理 — 创建 / 重命名 / 批量删除，导入 / 导出 JSON 歌单
- 🎨 6 套主题颜色（粉 / 紫 / 蓝 / 绿 / 橙 / Apple Music）+ 深色 / 浅色模式
- ✨ 液态玻璃（毛玻璃）、专辑涟漪、过渡动画等精致视觉
- 💿 适配 Android 系统播放控件（通知栏 / 锁屏 / 蓝牙耳机 / 小米超级岛）

## 🛠 技术栈

| 技术 | 用途 |
|------|------|
| Flutter / Dart | 跨平台 UI 框架 |
| just_audio | 音频播放 |
| audio_service | 系统媒体控制（MediaSession / MediaStyle 通知） |
| dio | 网络请求 |
| shared_preferences | 本地持久化 |
| pointycastle / crypto | 网易云 weapi 加密 / B 站 WBI 签名 |
| path_provider / file_picker / share_plus | 下载目录、文件选择、分享 |
| qr_flutter | 扫码登录二维码 |

## 📦 安装与运行

```bash
# 克隆项目
git clone https://github.com/Rayson-Liu/pink-music-flutter.git

# 进入目录
cd pink-music-flutter

# 安装依赖
flutter pub get

# 运行
flutter run
```

## 🔨 构建

```bash
# 构建 Android Release APK（全 ABI）
flutter build apk --release

# 只构建 arm64 瘦身包
flutter build apk --release --target-platform android-arm64
```

构建产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

> 说明：默认使用 debug 签名。上架前请在 `android/app/build.gradle.kts` 配置你自己的签名（`key.properties` + keystore）。

## 🎮 使用指南

### 搜索与播放

在「搜索」页输入关键词，点击结果即可播放。首页提供「音乐区推荐」和播放历史。

### 分P（多P）

多P 视频在播放页可打开「分P」面板切换；在「添加到歌单」时，会自动拉取分P 列表，让你勾选要加入的分P 再批量写入歌单。

### 歌词

播放页点击「歌词」进入全屏歌词：支持自动滚动居中、字号 A-/A+ 调节、翻译 / 罗马音、手动搜索、±0.5s 偏移微调。

### 歌单管理

- 创建 / 重命名 / 删除：在「我的」页操作
- 导入歌单：「我的 → 更多 → 导入歌单」，选择导出的 JSON 文件
- 导出歌单：在歌单「⋮」菜单中导出
- 批量操作：支持歌单内批量删除歌曲

### 下载

在歌曲「⋮」菜单点「下载」，音频保存为 `.m4a`（AAC），可在「下载管理」查看进度与分享文件。

## 📁 下载目录

| 平台 | 路径 |
|------|------|
| Android | `getExternalStorageDirectory()/Download`（应用专属外部存储，分享 / 导出可访问） |

## 📂 项目结构

```
lib/
├── audio/          # 播放引擎、均衡器、系统媒体控制（audio_handler）
├── models/         # 数据模型（Track / Playlist / Episode / Lyric / DownloadTask）
├── services/       # B 站 / 网易云 / QQ音乐 API、WBI 签名、HTTP 客户端
├── state/          # 状态管理（Player / Lyric / Playlist / Download / User / Settings / Theme）
├── ui/             # 页面（首页 / 搜索 / 我的 / 播放页 / 歌词 / 歌单 / 下载 / 设置 / 登录）
│   └── widgets/    # 通用组件（玻璃面板 / 封面 / 曲目项 / 弹窗）
└── main.dart
android/            # Android 原生（均衡器 DynamicsProcessing、通知权限）
```

## 📄 许可证

本项目以 **PolyForm Noncommercial License 1.0.0**（非商业许可）发布，禁止任何商业用途。

SPDX: `PolyForm-Noncommercial-1.0.0`

## ⚖️ 法律声明与使用限制

- 本项目**仅供学习与研究使用**，禁止任何形式的**商业用途**（包括但不限于销售、收费服务、广告变现、商业集成等）。
- 本项目与 **Bilibili 无任何官方关联或背书**，不使用其商标与标识；涉及的名称与商标归其权利人所有。
- 数据来源于用户调用的**公开接口**与个人账户授权；使用时需遵守 Bilibili 的《用户协议》《社区规则》及相关法律法规。
- **禁止绕过登录 / 会员权限、DRM / 加密措施，或进行批量爬取、恶意抓取等违反平台规则的行为**。
- 如需调整许可，请联系作者；如涉及权利或合规问题，请通过 Issues 反馈以便及时处理。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request，一起让 Pink Music 变得更好～

> 如果这个项目对你有帮助，欢迎点个 ⭐ 支持一下～
