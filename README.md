# WTV

![WTV 应用图标](docs/wtv-icon-128.png)

使用 ArkTS / ArkUI 构建的鸿蒙原生影视搜索与播放应用。

当前版本 **1.5.1 开发预览**：HarmonyOS API 26，最低 API 23，原生播放库支持 **ARM64**。包名为 `io.webber.wtv`。

[下载 HAP 与源码](https://github.com/Swebersmith/WTV-Harmony/releases) · [更新记录](CHANGELOG.md) · [第三方许可](THIRD_PARTY_NOTICES.md)

## 功能

- 原生搜索、影片详情、完整选集、收藏、观看记录和接口管理。
- WTV、VideoSearch、MacCMS JSON / XML 搜索接口；官方搜索支持五平台筛选。
- 鸿蒙适配的 **libmpv 0.41.0 + FFmpeg + OHCodec** 原生播放，支持媒体直链和 JSON 解析。
- 独立配置网页型解析线路，通过 ArkWeb 在播放页同一画框内播放。
- 倍速、系统媒体音量、静音、拖动定位、双击快进快退、长按加速、全屏锁定、续播和自动连播。
- 播放画面左侧上下滑动调整亮度，右侧上下滑动调整系统媒体音量；音量键变化同步到播放器设置。
- 观看记录原生左滑删除，提供 5 秒撤销。
- 原生媒体会话、系统分享、粘贴按钮、网络状态、浅色 / 深色主题。
- 无整页顶底蒙层的沉浸滚动、悬浮导航栏和原生页面转场。
- 可选的 Crayon HLS 去插播服务接入。服务异常自动恢复直连，并提示本次未过滤。

去插播依赖远端清单服务，只处理识别出的插播分片。服务地址可在应用内修改；画面内嵌广告和网页线路由其自身处理。

音量使用官方 [AVVolumePanel](https://developer.huawei.com/consumer/en/doc/harmonyos-references/ohos-multimedia-avvolumepanel/) 修改手机媒体音量，MPV 内部增益保持 100%，不会另外衰减声音。音量范围从当前设备读取，调整时显示系统提示。亮度使用原生窗口亮度接口，切换离开播放页或进入后台时恢复原值，也可手动选择“跟随系统”。手势功能仅作用于原生播放器。

![播放器图标资源预览](docs/player-icons.png)

## 安装

在 [Releases](https://github.com/Swebersmith/WTV-Harmony/releases) 下载 `WTV-Harmony-1.5.1-unsigned.hap`。

发布附件为**未签名调试包**，需要使用自己的有效鸿蒙签名身份签名后安装。升级时保持相同包名与签名身份，以便覆盖安装并保留本地数据。

## 构建

本版本使用官方 **Command Line Tools 26.0.0.865 / SDK 26.0.0.105 Release** 和 **JDK 21** 编译。请从[华为下载中心](https://developer.huawei.com/consumer/cn/download/)取得相应工具。

Windows PowerShell 示例，建议将工具与构建目录放在英文路径：

```powershell
.\build.ps1 `
  -ToolHome 'C:\Tools\command-line-tools' `
  -JdkHome 'C:\Tools\jdk-21' `
  -BuildRoot 'C:\Build\wtv-harmony' `
  -RequireApi26
```

构建脚本安装本地 HAR 依赖、编译 C++ 桥接并在 `dist/` 生成 HAP；完成后打印输出路径和 SHA-256。默认交付未签名包。可通过 `-SigningConfigPath` 指向工程外的私有签名 material JSON；签名文件不应提交到仓库。

`mpv/` 包含上游 ArkTS / C++ 封装、已校验的 ARM64 共享库及固定发布版本的构建资料。SDK、JDK 和签名材料由使用者提供。

## 检查

使用 SDK 中的 TypeScript 转译器运行 42 项协议、播放生命周期、媒体音量监听、提示收起、播放切换和窗口亮度逻辑检查：

```powershell
$env:ARKTS_TYPESCRIPT = 'C:\Tools\command-line-tools\sdk\default\openharmony\ets\build-tools\ets-loader\node_modules\typescript'
node --test .\checks\native.mjs
```

也可运行 `npm ci --ignore-scripts` 与 `npm test`，使用固定版本的标准 TypeScript 转译器执行同一组逻辑检查。测试中的 HTTP、音量、窗口和 MPV 运行时使用替身。

**验证范围：** API 26 编译、ARM64 原生库和 HAP 结构检查已通过；图标资源经过栅格化检查。1.5.1 的系统音量调节、窗口亮度、左滑删除、横屏和实际 UI 尚未完成本机连接真机验证，因此当前发布标记为开发预览。自动逻辑检查不能代替手机上的音量和亮度验证。

## 许可与来源

应用自身代码使用 [MIT](LICENSE) 许可，第三方组件遵循各自许可。

- [mpv-arkts](https://github.com/mpv-ohos/mpv-arkts)：鸿蒙 MPV 封装。
- [libmpv-ohos-build](https://github.com/mpv-ohos/libmpv-ohos-build/tree/20260715)：固定版本的鸿蒙 ARM64 内核。
- [CrayonPlayer](https://github.com/Swebersmith/CrayonPlayer)：现有清单服务协议与播放器交互参考。

原生库哈希、上游版本及本地桥接改动记录见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
