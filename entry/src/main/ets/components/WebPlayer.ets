import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { webNavigationAllowed } from '../model/Models';
import { applySystemBars } from '../design/WindowStyle';

export class WebPlayerHandle {
  exitFullscreen: () => boolean = (): boolean => false;
}

// The web view occupies the same playback frame as the native surface, never a new page.
@Component
export struct WebPlayer {
  handle: WebPlayerHandle = new WebPlayerHandle();
  @Prop @Watch('sourceChanged') src: string = '';
  @Prop title: string = '';
  @Prop previousEnabled: boolean = false;
  @Prop nextEnabled: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop @Watch('foregroundChanged') active: boolean = true;
  onFullscreen: (value: boolean) => void = (): void => {};
  onPrevious: () => void = (): void => {};
  onNext: () => void = (): void => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private fullScreenHandler?: FullScreenExitHandler;
  private attached: boolean = false;
  private context?: common.UIAbilityContext;
  private appWindow?: window.Window;
  private oldOrientation: window.Orientation = window.Orientation.UNSPECIFIED;
  private timeout: number = -1;
  @StorageProp('inForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State fullscreen: boolean = false;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State slow: boolean = false;

  aboutToAppear(): void {
    this.handle.exitFullscreen = (): boolean => this.exitFullscreen();
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(this.context).then((win: window.Window): void => {
      this.appWindow = win; this.oldOrientation = win.getPreferredOrientation();
    }).catch((): void => {});
    this.armTimeout();
  }
  aboutToDisappear(): void { clearTimeout(this.timeout); this.exitFullscreen(); this.restoreWindow(); this.attached = false; this.handle.exitFullscreen = (): boolean => false; }
  foregroundChanged(): void {
    // Destroy the page in the background to stop iframe audio and scripts as well as top-level video.
    if (!this.foreground || !this.active) { this.exitFullscreen(); this.attached = false; clearTimeout(this.timeout); }
    else this.armTimeout();
  }
  sourceChanged(): void {
    this.exitFullscreen(); this.loadError = ''; this.loading = true; this.armTimeout();
    if (this.attached) {
      try { this.controller.loadUrl(this.src); } catch { this.loadError = '网页播放器未就绪，请重新打开'; }
    }
  }
  armTimeout(): void {
    clearTimeout(this.timeout); this.slow = false;
    this.timeout = setTimeout((): void => { if (this.loading) this.slow = true; },15000);
  }
  reload(): void {
    if (!this.attached) return;
    this.loadError = ''; this.loading = true; this.armTimeout();
    try { this.controller.refresh(); } catch { this.loadError = '刷新未完成，请返回重试'; }
  }
  exitFullscreen(): boolean {
    if (!this.fullscreen) return false;
    try { this.fullScreenHandler?.exitFullScreen(); } catch { /* View may already have closed. */ }
    this.restoreWindow(); return true;
  }
  restoreWindow(): void {
    const wasFullscreen = this.fullscreen;
    this.fullscreen = false; this.fullScreenHandler = undefined;
    if (wasFullscreen) {
      AppStorage.setOrCreate('mediaFullscreen',false);
      this.onFullscreen(false);
      if (this.appWindow) applySystemBars(this.appWindow).catch((): void => {});
    }
    this.appWindow?.setWindowKeepScreenOn(false).catch((): void => {});
    if (wasFullscreen) this.appWindow?.setPreferredOrientation(this.oldOrientation).catch((): void => {});
  }
  build() {
    Stack({alignContent:Alignment.TopEnd}) {
        if (this.foreground && this.active) {
          Web({src:this.src,controller:this.controller})
            .javaScriptAccess(true).domStorageAccess(true).fileAccess(false)
            .mixedMode(MixedMode.Compatible).mediaPlayGestureAccess(true)
            .multiWindowAccess(false).allowWindowOpenMethod(false)
            .backgroundColor('#000000').width('100%').height('100%')
            .onControllerAttached((): void => { this.attached = true; })
            .onPageBegin((): void => { this.loading = true; this.loadError = ''; this.armTimeout(); })
            .onPageEnd((): void => { this.loading = false; this.slow = false; clearTimeout(this.timeout); })
            .onLoadIntercept((event: OnLoadInterceptEvent): boolean => !webNavigationAllowed(event.data.getRequestUrl(),event.data.isMainFrame()))
            .onErrorReceive((event: OnErrorReceiveEvent): void => {
              if (event.request.isMainFrame()) { this.loading = false; this.loadError = '网页载入失败，请刷新或返回更换线路'; }
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
              if (event.request.isMainFrame()) { this.loading = false; this.loadError = `线路返回 HTTP ${event.response.getResponseCode()}`; }
            })
            .onPermissionRequest((event: OnPermissionRequestEvent): void => event.request.deny())
            .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => { event.result.handleFileList([]); return true; })
            .onFullScreenEnter((event: FullScreenEnterEvent): void => {
              this.fullScreenHandler = event.handler; this.fullscreen = true;
              AppStorage.setOrCreate('mediaFullscreen',true);
              this.onFullscreen(true);
              if (this.appWindow) applySystemBars(this.appWindow,true).catch((): void => {});
              this.appWindow?.setWindowKeepScreenOn(true).catch((): void => {});
              if ((event.videoWidth || 0) > (event.videoHeight || 0)) {
                this.appWindow?.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE).catch((): void => {});
              }
            })
            .onFullScreenExit((): void => this.restoreWindow())
        } else { Column().width('100%').height('100%').backgroundColor('#0D141E') }
        if (!this.fullscreen) {
          Column({space:8}) {
            Button('刷新',{type:ButtonType.Normal}).fontSize(10).fontColor('#F3F6FA').backgroundColor('#BB18242D')
              .height(28).borderRadius(10).margin(10).onClick((): void => this.reload())
            Blank()
            if (this.loadError || this.error || this.slow) {
              Text(this.error || this.loadError || '线路加载较慢，可刷新或更换线路').fontSize(11).fontColor('#F3F6FA')
                .backgroundColor('#CC18242D').padding(10).width('100%')
            }
            if (this.loading) { Progress({value:30,total:100,type:ProgressType.Linear}).color('#A1E6D0').height(2).width('100%') }
          }.alignItems(HorizontalAlign.End).width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent)
        }
    }.width('100%').height('100%').backgroundColor('#000000')
  }
}
