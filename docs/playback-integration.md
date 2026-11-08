# 系统播控与画中画接入依据

WTV 1.7.6 采用下列华为官方指导，后续修改相关能力时应先核对当前官方文档和 SDK 声明，再验证真机行为。

- [画中画开发概述](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/pipwindow-overview)
- [typeNode 画中画开发](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/pipwindow-typenode/)
- [AVSession 接入场景](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avsession-access-scene)
- [AVSession 进度与控制示例](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avsession-access-scene/)
- [后台播放](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/avsession-background-scene/)
- [投播开发指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/distributed-playback-guide)
- [AVCastPicker 投播组件](https://developer.huawei.com/consumer/cn/doc/harmonyOS-references/ohos-multimedia-avcastpicker)
- [画中画接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-pipwindow/)
- [窗口错误码](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/errorcode-window/)

## 播控时间与跳转

AVMetadata.duration 与 AVPlaybackPosition.elapsedTime 使用毫秒。position.updateTime 是上报该播放位置时的当前系统时间戳，遵循官方示例的 Date.now() / new Date().getTime()，不是设备开机时长。

AVSession 的 seek 回调位置由毫秒转为 MPV 的秒，提交 absolute+exact。C++ 桥接将 mpv_command 的返回码传回 ArkTS；返回负值时不提交虚假目标位置。命令被接受后，立即上报目标位置与等待状态，忽略旧时间，收到接近目标的实际播放时间后恢复正常状态。10 秒内未确认则恢复真实内核时间。

## 一个视频节点的迁移

VideoSurface 作为 NodeController，创建 typeNode XComponent；主页面通过 NodeContainer 展示。PiPWindow.create 接收同一个 typeNode 和关联的 NativePlayback 控制器。

1. ABOUT_TO_START：只从页面父节点移除视频节点，由系统挂载到画中画。
2. STARTED：更新播控状态，重复回调不能再次移除系统已挂载的节点。
3. ABOUT_TO_RESTORE：标记还原并通知页面恢复播放栏目；这里只切回播放页，不清空导航栈、不重复打开页面，避免还原时整页刷新。
4. ABOUT_TO_STOP：把视频节点移回页面。
5. STOPPED：结束小窗占用；用户关闭则暂停，还原则继续播放。
6. 退出整个应用组件时，在关闭小窗后统一释放视频节点。

页面的视频节点不再铺满整个 224vp 画框，而是按片源宽高比内嵌并居中，控件层仍覆盖整个画框。这样页面节点与系统小窗使用相同比例，切换时系统按节点迁移，不会把宽画框横向拉伸成小窗比例。节点尺寸变化时通过 `ohos-surface-size` 同步给 MPV，避免缓冲区与控件尺寸不一致产生额外缩放。

小窗控制组使用 `FAST_FORWARD_BACKWARD`（快进 / 快退 10 秒）。官方限制该组与 `VIDEO_PREVIOUS_NEXT` 互斥，同一小窗只能显示其中一组，因此本版小窗不再显示上下集按钮。

后台仅放音时视频轨会被关闭；此时若从实况窗 / 控制中心执行跳转，回到前台重新启用视频后会对当前目标再执行一次精确 seek，让视频解码器追上音频位置，避免画面停在旧进度。实况窗的快进 / 快退回调按文档为毫秒，但部分系统界面会传秒，代码对两者都做兼容，并以 MPV 当前真实位置为基准计算相对跳转。

这条路径迁移节点，不主动创建第二个 MPV 渲染表面；若系统确实销毁和重建表面，原生控制器仍保留音频内核并处理 surface 回调。画面尺寸从 XComponent 的真实 surface 尺寸回调更新。

自动小窗通过 setAutoStartEnabled 配置，由系统在主窗口退后台时触发；不在 onBackground 内手动调用 startPiP。用户手动打开时应用应位于前台。

## 投播

1.7.6 使用系统 `AVCastPicker` 作为设备发现入口。播放页右上角只在原生 AVSession 就绪后显示该组件，本机不在 onBackground 等位置自行扫描设备。

1. AVSession 创建后调用 `setExtras({requireAbilityList:['url-cast']})`，并在 AVMetadata 中设置 `filter` 为 Cast+ Stream 与 DLNA 的组合，交给系统投播框架发现设备。
2. `outputDeviceChange` 收到 `CATEGORY_REMOTE` + `STATE_CONNECTED` 后调用 `getAVCastController()`；`prepare` 只在首次投播时调用，随后 `start`。`AVQueueItem.description` 使用当前媒体地址、assetId、标题、时长和毫秒级 `startPosition`，由接收端拉流。
3. 投播开始后本机 MPV 暂停，画面内显示设备、远端进度与停止入口。系统播控中心 / 锁屏的播放、暂停、seek、快进快退、倍速统一转为 `sendControlCommand`。
4. 收到 `CATEGORY_LOCAL` 或远端断开时，释放 AVCastController 并 `stopCasting()`，本机按远端最后进度续播。
5. 网页型线路由第三方网页掌管媒体，不进入本应用的投播流程。

设备发现、协议与接收端解码能力由系统投播框架和远端设备决定；无接收端的模拟器不能验证实际投屏画面。

## 后台长时任务的类型映射

按[官方长时任务接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-resourceschedule-backgroundtaskmanager/)的主 / 子类型对照表，已接入 AVSession 的播放使用 MODE_AV_PLAYBACK_AND_RECORD（12）与 SUBMODE_AVSESSION_AUDIO_PLAYBACK（5），对应 UIAbility backgroundModes 中的 avPlaybackAndRecord。MODE_AUDIO_PLAYBACK（2）对应 SUBMODE_NORMAL_NOTIFICATION（2），不能与子类型 5 混用。

1.7.5 修正该配置并保留 KEEP_BACKGROUND_RUNNING 权限。任务在前台播放时申请，后台继续持有；暂停或服务结束后释放。通过 background task request / acquired / denied / canceled 日志可核对系统实际受理结果。

## Surface 回调接收者

1.7.3 真机日志显示 typeNode 的 onSurfaceCreated 回调在 this.attach 处抛出 TypeError，最后一条记录是 surface created，未进入 MPV attach。三个生命周期回调必须捕获 NativePlayback 实例，不能依赖桥接调用时的动态 this。1.7.4 使用箭头函数，并通过 Reflect.apply 将回调接收者替换为无原型对象，验证创建、尺寸更新和销毁均作用于原播放器。

## 真机复测

逻辑测试只验证节点归属、事件路由、状态与单位转换，不能证明系统窗口已显示。

- 原生视频播放后点击小窗，确认持续有画面、有声音，拖动和缩放正常。
- 连续点击小窗只启动一次；关闭后暂停，还原后继续播放。
- 从小窗还原回应用，确认停留在播放页、页面不重新加载，视频继续而不是回到搜索页。
- 播放后点击右上角投屏，选择同一局域网设备，确认远端出现画面、手机暂停并显示投屏设备与远端进度。
- 投屏中从手机控制中心暂停 / 继续 / 拖动进度，确认远端同步；结束投屏或关闭远端后确认手机从上次进度续播。
- 开启后台播放与自动小窗，返回桌面确认系统启动小窗；检查系统画中画开关。
- 控制中心、锁屏卡片分别验证暂停/播放、快进/快退和进度拖动；返回页面确认画面实际位于新位置。
- 连续拖动、暂停后拖动、切集、网页线路切换和全屏还原分别复测。
- 若失败，在设置点击「错误与播放日志」中的复制或导出，查看 PiP 状态、错误码、system seek、MPV result 与 seek confirmed / timeout。日志写入应用私有文件并轮换，重启后仍可导出，遮盖 HTTP(S) 链接及常见凭据。HiAppEvent 提供的崩溃堆栈会在系统投递后保存。

截至本版本构建，开发环境没有可用的 HDC 真机连接。API 编译和逻辑检查已完成，以上系统 UI 与解码连续性仍需连接设备验证。
