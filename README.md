# WTV

![WTV 应用图标](docs/wtv-icon-128.png)

使用 ArkTS / ArkUI 构建的鸿蒙原生影视搜索与播放应用。

当前版本 **1.7.7 开发预览**：HarmonyOS API 26，最低 API 23，原生播放库支持 **ARM64**。包名为 `io.webber.wtv`。

[下载 HAP 与源码](https://github.com/Swebersmith/WTV-Harmony/releases) · [更新记录](CHANGELOG.md) · [第三方许可](THIRD_PARTY_NOTICES.md)

## 功能

- 原生搜索、影片详情、完整选集、收藏、观看记录和接口管理。设置分为接口、播放、通用、版本四个二级页；接口可折叠分组、单独启用，站点同步项也可编辑。
- 影片详情与所有二级页使用与栏目页一致的沉浸式渐变模糊标题栏；选集按钮按集名长度自适应排列。
- 播放页显示当前影片封面与简介，链接与解析区域保持紧凑；HLS 去插播放在播放设置中。
- WTV、VideoSearch、MacCMS JSON / XML 搜索接口；官方搜索支持五平台筛选。
- 鸿蒙适配的 **libmpv 0.41.0 + FFmpeg + OHCodec** 原生播放，支持媒体直链和 JSON 解析。
- 独立配置网页型解析线路，通过 ArkWeb 在播放页同一画框内播放。
- 倍速、系统媒体音量、静音、拖动定位、双击快进快退、长按加速、全屏锁定、续播和自动连播。
- 播放画面左侧上下滑动调整亮度，右侧上下滑动调整系统媒体音量；音量键变化同步到播放器设置。
- 观看记录原生左滑删除并支持 5 秒撤销；收藏以竖向封面横向排列，海报显示来源和简介，可左右滑动浏览，长按海报管理收藏；继续观看显示平台或搜索来源，续播后自动补齐全部选集。
- 系统控制中心与锁屏媒体卡片：片名、集数、封面、时长、进度，支持播放、暂停、切集、快进快退、定位、倍速及返回播放页。
- 系统投播：播放页右上角选择远端设备，由接收端拉流播放；手机显示投屏设备、远端进度，并可暂停、继续或停止投屏。
- 原生后台放音、系统媒体实况窗适配、系统画中画小窗及可选的返回桌面自动小窗；从小窗还原时直接回到播放页，不重建页面。
- 播放器控制层点击画面即隐藏，暂停状态也可以收起；操作播放、倍速、音量或亮度时重新显示。
- 系统分享、粘贴按钮、网络状态、浅色 / 深色主题。
- 左上角常驻「搜索 / 播放 / 片单 / 设置」原生标题，滚动联动沉浸式渐变模糊；56vp 纯图标悬浮底栏和原生页面转场。
- 切换栏目及打开接口编辑时不自动弹出键盘，点击输入框正常输入。
- 可选的 Crayon HLS 去插播服务接入。服务异常自动恢复直连，并提示本次未过滤。

去插播依赖远端清单服务，只处理识别出的插播分片。服务地址可在应用内修改；画面内嵌广告和网页线路由其自身处理。

音量使用官方 [AVVolumePanel](https://developer.huawei.com/consumer/en/doc/harmonyos-references/ohos-multimedia-avvolumepanel/) 修改手机媒体音量，MPV 内部增益保持 100%，不会另外衰减声音。音量范围从当前设备读取，调整时显示系统提示。亮度使用原生窗口亮度接口，切换离开播放页或进入后台时恢复原值，也可手动选择“跟随系统”。手势功能仅作用于原生播放器。

![播放器图标资源预览](docs/player-icons.png)

顶部采用官方 [HdsNavigation](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation/) 的 `ScrollEffectType.IMMERSIVE_GRADIENT_BLUR`，通过 `bindToScrollable` 绑定当前栏目滚动容器，0–56vp 滚动距离线性过渡。标题保持固定，内容可以滚至标题和状态栏下方；全屏播放时隐藏标题与底栏。底栏使用系统 Symbol，26vp 图形在四个等宽槽位内居中，并保留无障碍栏目名称。

所有搜索与文本输入框使用官方 [enableKeyboardOnFocus](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-manage-keyboard/) 属性禁止非点击获焦时自动拉起输入法。搜索页宣传卡片、各栏目旧大标题副文案及播放页两段辅助说明已经移除。

接入细节、官方依据及真机复测步骤见 [播控与画中画接入](docs/playback-integration.md)。

## 系统播控、后台和小窗

原生 MPV 线路接入官方 [AVSession 后台播放方案](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/avsession-background-scene/)，同时声明 `KEEP_BACKGROUND_RUNNING` 和 `audioPlayback` / `avPlaybackAndRecord` 后台模式。播放时按官方对照表申请 `MODE_AV_PLAYBACK_AND_RECORD`（12）与 `SUBMODE_AVSESSION_AUDIO_PLAYBACK`（5）的音视频长时任务，暂停、切源、切换网页线路或退出播放时释放；申请失败时不能保证后台续播，会给出提示。后台播放默认开启，可在设置页关闭。任务应在前台开始播放时取得，退后台后继续持有；诊断日志记录申请、返回 ID、拒绝错误码、释放以及系统取消的原因。

投播使用系统 `AVCastPicker` 投播组件和 `AVCastController`。播放时通过 AVSession 声明 `url-cast` 能力并设置 Cast+ / DLNA 协议过滤，右上角组件负责设备发现；远端连接后读取当前媒体地址，按官方 `prepare` → `start` 流程下发 `AVQueueItem`，本机暂停。投屏中系统播控中心与锁屏的播放、暂停、定位、快进快退、倍速会转投到远端；结束投屏或远端断开后，本机从远端返回的进度继续播放。网页型线路由第三方网页掌管媒体，不进入投播流程。

媒体实况窗由系统按照 AVSession 元数据、播放状态和 `setBackgroundPlayMode` 展示，不另发自定义实况窗。后台播放模式接口从 API 24 起可用；API 23 保留基础媒体卡片与后台任务接入，实况窗及具体样式由系统版本决定。点击系统卡片可返回当前播放页。

点击播放器右上角的小窗图标，进入官方 [PiPWindow 画中画](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/pipwindow-typenode/)。主页面使用 NodeContainer 挂载 typeNode XComponent；在 ABOUT_TO_START 从页面移除同一视频节点，交由系统小窗挂载，在 ABOUT_TO_STOP 恢复到页面。MPV 继续使用同一节点与表面，提供系统播放 / 暂停与快进 / 快退 10 秒控件。系统同一小窗只允许“快进快退”或“上一集 / 下一集”其中一组，本版按用户要求使用快进快退。恢复到应用时继续播放，关闭小窗时暂停。设置页可开启「退出应用时自动小窗」（默认关闭，需要开启后台播放）。

系统卡片的 position.updateTime 按官方示例使用当前系统时间的毫秒时间戳（Date.now），与 elapsedTime 播放进度区分；不使用设备开机时长。系统卡片拖动进度时向 MPV 提交精确跳转，立即上报目标位置并保持等待状态，过滤跳转前的旧时间；内核时间到达目标后恢复正常进度上报。跳转超时则恢复真实位置，返回前台时可重试。小窗启动合并并发请求，重复启动错误会先核对系统状态，遇到卡住的启动只清理重试一次。

后台仅放音时关闭视频渲染，恢复前台或进入小窗后恢复视频；表面丢失与重新绑定不销毁正在使用的内核。暂停和后台任务被系统撤销时，同步更新系统卡片。网页型线路由第三方网页掌管媒体，当前不接入本应用的 MPV 系统播控、后台及小窗流程。

设置页「错误与播放日志」支持导出 TXT、复制和清空。启动时接入官方 [HiAppEvent 崩溃订阅](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/hiappevent-watcher-crash-events-arkts/)，下次启动时接收系统提供的 ArkTS / Native 崩溃和冻屏事件，复制系统日志附件中的堆栈；同时记录上次退出原因、视频节点创建、MPV 初始化、表面绑定、打开媒体和错误级内核日志。播放关键步骤同步写入应用私有文件，重启后仍可导出。

复现方法：安装新版后播放一次；发生闪退则重新打开，进入「设置 → 错误与播放日志 → 导出错误日志 TXT」并选择保存位置。若系统尚未投递堆栈，可稍等后再次导出；即使附件不可读也会保留事件摘要与播放步骤。系统只会提供其实际保留的故障记录，本应用不能捕获进程终止后尚未生成的堆栈。

日志只保存在本机，不自动上传；遮盖 HTTP(S) 链接与常见 token / password / Authorization 字段。最多保留两个约 64 KiB 的步骤文件及两份截取到 131072 字符的故障文件，不会无限增长；清空仅删除本应用的诊断副本。系统日志可能包含设备运行信息，导出后可自行查看。1.7.3 的真机日志将启动播放时的闪退定位到 onSurfaceCreated 内的 this.attach 调用；1.7.4 将三个 Surface 生命周期回调改为捕获播放器实例的函数，避免 typeNode 桥接改变回调接收者。该调用方式已加入回归测试，实际播放仍需真机复测。

## 安装

在 [Releases](https://github.com/Swebersmith/WTV-Harmony/releases/tag/v1.7.6) 下载已发布的 1.7.6 未签名 HAP；当前源码为 1.7.7 开发预览，尚未发布安装包。

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

使用 SDK 中的 TypeScript 转译器运行 83 项协议、播放生命周期、投播、音量、亮度、后台任务、系统会话和画中画逻辑检查：

```powershell
$env:ARKTS_TYPESCRIPT = 'C:\Tools\command-line-tools\sdk\default\openharmony\ets\build-tools\ets-loader\node_modules\typescript'
node --test .\checks\native.mjs
```

也可运行 `npm ci --ignore-scripts` 与 `npm test`，使用固定版本的标准 TypeScript 转译器执行同一组逻辑检查。测试中的 HTTP、音量、窗口、AVSession、后台任务、PiP 和 MPV 运行时使用替身；页面事件处理器只验证逻辑，不模拟渲染。

**验证范围：** API 26 编译、ARM64 原生库和 HAP 结构检查已通过，83 项逻辑检查通过。1.7.7 的收藏横向海报与长按菜单、续播补齐选集、接口左侧滑出动画、二级页返回图标、播放器上滑取消进度、去按钮遮罩、系统投播与详情 / 二级页渐变模糊需要在真机上复测；投播还取决于接收端设备与局域网。逻辑替身不能验证系统 UI、系统后台调度或实际解码连续性。

## 许可与来源

应用自身代码使用 [MIT](LICENSE) 许可，第三方组件遵循各自许可。

- [mpv-arkts](https://github.com/mpv-ohos/mpv-arkts)：鸿蒙 MPV 封装。
- [libmpv-ohos-build](https://github.com/mpv-ohos/libmpv-ohos-build/tree/20260715)：固定版本的鸿蒙 ARM64 内核。
- [CrayonPlayer](https://github.com/Swebersmith/CrayonPlayer)：现有清单服务协议与播放器交互参考。

原生库哈希、上游版本及本地桥接改动记录见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
