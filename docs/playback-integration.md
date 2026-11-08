# 系统播控与画中画接入依据

WTV 1.7.2 采用下列华为官方指导，后续修改相关能力时应先核对当前官方文档和 SDK 声明，再验证真机行为。

- [画中画开发概述](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/pipwindow-overview)
- [typeNode 画中画开发](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/pipwindow-typenode/)
- [AVSession 接入场景](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avsession-access-scene)
- [AVSession 进度与控制示例](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avsession-access-scene/)
- [后台播放](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/avsession-background-scene/)
- [画中画接口](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-pipwindow/)
- [窗口错误码](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/errorcode-window/)

## 播控时间与跳转

AVMetadata.duration 与 AVPlaybackPosition.elapsedTime 使用毫秒。position.updateTime 是上报该播放位置时的当前系统时间戳，遵循官方示例的 Date.now() / new Date().getTime()，不是设备开机时长。

AVSession 的 seek 回调位置由毫秒转为 MPV 的秒，提交 absolute+exact。C++ 桥接将 mpv_command 的返回码传回 ArkTS；返回负值时不提交虚假目标位置。命令被接受后，立即上报目标位置与等待状态，忽略旧时间，收到接近目标的实际播放时间后恢复正常状态。10 秒内未确认则恢复真实内核时间。

## 一个视频节点的迁移

VideoSurface 作为 NodeController，创建 typeNode XComponent；主页面通过 NodeContainer 展示。PiPWindow.create 接收同一个 typeNode 和关联的 NativePlayback 控制器。

1. ABOUT_TO_START：只从页面父节点移除视频节点，由系统挂载到画中画。
2. STARTED：更新播控状态，重复回调不能再次移除系统已挂载的节点。
3. ABOUT_TO_RESTORE：标记还原并通知页面恢复播放栏目。
4. ABOUT_TO_STOP：把视频节点移回页面。
5. STOPPED：结束小窗占用；用户关闭则暂停，还原则继续播放。
6. 退出整个应用组件时，在关闭小窗后统一释放视频节点。

这条路径迁移节点，不主动创建第二个 MPV 渲染表面；若系统确实销毁和重建表面，原生控制器仍保留音频内核并处理 surface 回调。画面尺寸从 XComponent 的真实 surface 尺寸回调更新。

自动小窗通过 setAutoStartEnabled 配置，由系统在主窗口退后台时触发；不在 onBackground 内手动调用 startPiP。用户手动打开时应用应位于前台。

## 真机复测

逻辑测试只验证节点归属、事件路由、状态与单位转换，不能证明系统窗口已显示。

- 原生视频播放后点击小窗，确认持续有画面、有声音，拖动和缩放正常。
- 连续点击小窗只启动一次；关闭后暂停，还原后继续播放。
- 开启后台播放与自动小窗，返回桌面确认系统启动小窗；检查系统画中画开关。
- 控制中心、锁屏卡片分别验证暂停/播放、快进/快退和进度拖动；返回页面确认画面实际位于新位置。
- 连续拖动、暂停后拖动、切集、网页线路切换和全屏还原分别复测。
- 若失败，在设置点击「复制播放诊断」，查看 PiP 状态、错误码、system seek、MPV result 与 seek confirmed / timeout。日志只留在本次进程内，不含媒体地址和接口凭据。

截至本版本构建，开发环境没有可用的 HDC 真机连接。API 编译和逻辑检查已完成，以上系统 UI 与解码连续性仍需连接设备验证。
