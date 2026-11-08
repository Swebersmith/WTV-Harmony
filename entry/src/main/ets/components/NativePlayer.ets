import { NativePlayback, NATIVE_RATES } from '../services/NativePlayback';
import { VideoSurface } from '../services/VideoSurface';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AVVolumePanel } from '@kit.AudioKit';
import { AVCastPicker, AVCastPickerState } from '@kit.AVSessionKit';
import { SystemMediaVolume, PlayerBrightness, MediaVolume, volumeFromSwipe, brightnessFromSwipe } from '../services/PlayerDeviceControls';

const WHITE: string = '#F3F6FA';
const MINT: string = '#A1E6D0';

@Component
export struct NativePlayer {
  controller: NativePlayback = new NativePlayback();
  surface: VideoSurface = new VideoSurface(this.controller);
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop status: string = '';
  @Prop error: string = '';
  @Prop @Watch('fullscreenChanged') fullscreen: boolean = false;
  @Prop @Watch('playbackChanged') playing: boolean = false;
  @Prop buffering: boolean = false;
  @Prop elapsed: number = 0;
  @Prop duration: number = 0;
  @Prop reduceMotion: boolean = false;
  @Prop @Watch('deviceVisibilityChanged') active: boolean = true;
  @Prop episodeNames: string[] = [];
  @Prop episodeIndex: number = -1;
  @Prop @Watch('pipChanged') inPip: boolean = false;
  @Prop @Watch('syncRate') systemRate: number = 1;
  @Prop @Watch('videoAspectChanged') videoAspect: number = 16 / 9;
  @Prop castReady: boolean = false;
  @Prop @Watch('castModeChanged') casting: boolean = false;
  @Prop castDevice: string = '';
  @Prop castElapsed: number = 0;
  @Prop castPlaying: boolean = false;
  onSmallWindow: () => void = (): void => {};
  onRestoreWindow: () => void = (): void => {};
  onFullscreen: (value: boolean) => void = (): void => {};
  onEpisode: (index: number) => void = (): void => {};
  onRetry: () => void = (): void => {};
  onCastToggle: () => void = (): void => {};
  onCastStop: () => void = (): void => {};
  private hideTimer: number = -1;
  private hintTimer: number = -1;
  @State widthVp: number = 360;
  @State heightVp: number = 220;
  private startTime: number = 0;
  private startVolume: number = 0;
  private startBrightness: number = 0.5;
  private panSide: number = 0;
  private volumeService: SystemMediaVolume = new SystemMediaVolume();
  private brightnessService: PlayerBrightness = new PlayerBrightness();
  private appWindow?: window.Window;
  private deviceRevision: number = 0;
  private disposed: boolean = false;
  private volumeTimer: number = -1;
  private unmutedLevel: number = 1;
  private panAxis: number = 0;
  private panSeek: number = 0;
  private panCancelled: boolean = false;
  private oldRate: number = 1;
  @State visible: boolean = true;
  @State locked: boolean = false;
  @State panel: string = '';
  @State rate: number = 1;
  @State volumeLevel: number = 0;
  @State volumeMin: number = 0;
  @State volumeMax: number = 1;
  @State volumeReady: boolean = false;
  @State requestedVolume: number = 0;
  @State volumeCommandIssued: boolean = false;
  @State volumePanelVisible: boolean = false;
  @State screenBrightness: number = 0.5;
  @State brightnessReady: boolean = false;
  @State followsSystemBrightness: boolean = true;
  @State scrubbing: boolean = false;
  @State previewTime: number = 0;
  @State hint: string = '';
  @State holding: boolean = false;
  @StorageProp('safeLeftPx') safeLeft: number = 0;
  @StorageProp('safeRightPx') safeRight: number = 0;
  @StorageProp('safeBottomPx') safeBottom: number = 0;
  @StorageProp('inForeground') @Watch('deviceVisibilityChanged') foreground: boolean = true;

  aboutToAppear(): void { this.disposed = false; this.rate = this.controller.getRate(); this.controller.setVolume(1); this.deviceVisibilityChanged(); }
  aboutToDisappear(): void { this.disposed = true; this.closeDeviceControls(); this.endHold(); clearTimeout(this.hideTimer); clearTimeout(this.hintTimer); if (!this.controller.isRetained()) this.controller.detach(); }
  syncRate(): void { this.rate = this.systemRate; }
  pipChanged(): void { this.endHold(); this.panel = ''; this.deviceVisibilityChanged(); }
  castModeChanged(): void { this.endHold(); this.panel = ''; this.visible = true; }
  videoAspectChanged(): void { this.applyNodeSize(); }
  private nodeAspect(): number { return Number.isFinite(this.videoAspect) && this.videoAspect > 0 ? this.videoAspect : 16/9; }
  // Keep the video node itself in the media's aspect inside the page frame. The system PiP then
  // scales one uniformly proportioned node instead of stretching a wide page box into a 16:9 window.
  private nodeWidthVp(): number {
    if (this.fullscreen || this.widthVp <= 0 || this.heightVp <= 0) return this.widthVp;
    return Math.min(this.widthVp,this.heightVp*this.nodeAspect());
  }
  private nodeHeightVp(): number {
    if (this.fullscreen || this.widthVp <= 0) return this.heightVp;
    return Math.min(this.heightVp,this.nodeWidthVp()/this.nodeAspect());
  }
  private applyNodeSize(): void {
    if (this.disposed || this.inPip) return;
    const width = this.nodeWidthVp(), height = this.nodeHeightVp();
    if (width > 0 && height > 0) this.controller.resize(this.getUIContext().vp2px(width),this.getUIContext().vp2px(height));
  }
  deviceVisibilityChanged(): void {
    if (this.disposed || !this.active || !this.foreground || this.inPip) { this.endHold(); this.closeDeviceControls(); return; }
    const revision = ++this.deviceRevision;
    this.volumeReady = this.volumeService.open((value: MediaVolume): void => {
      this.volumeLevel = value.level; this.volumeMin = value.min; this.volumeMax = value.max;
      if (!this.volumeCommandIssued) this.requestedVolume = value.level;
      if (value.level > value.min) this.unmutedLevel = value.level;
      if (this.volumePanelVisible) this.showHint(`媒体音量 ${value.level} / ${value.max}`);
    });
    if (this.appWindow) { this.openBrightness(revision); return; }
    try {
      window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext).then((win: window.Window): void => {
        if (revision !== this.deviceRevision || this.disposed || !this.active || !this.foreground) return;
        this.appWindow = win; this.openBrightness(revision);
      }).catch((): void => { if (revision === this.deviceRevision) this.brightnessReady = false; });
    } catch { this.brightnessReady = false; }
  }
  openBrightness(revision: number): void {
    if (!this.appWindow) return;
    this.brightnessService.open(this.appWindow,(): void => this.showHint('亮度调整暂不可用')).then((value: number | undefined): void => {
      if (revision !== this.deviceRevision || this.disposed || !this.active || !this.foreground) return;
      if (value === undefined) { this.brightnessReady = false; return; }
      this.brightnessReady = true; this.followsSystemBrightness = value < 0;
      if (value >= 0) this.screenBrightness = value;
    }).catch((): void => { this.brightnessReady = false; });
  }
  closeDeviceControls(): void {
    ++this.deviceRevision; clearTimeout(this.volumeTimer); this.volumePanelVisible = false; this.volumeCommandIssued = false;
    this.volumeReady = false; this.brightnessReady = false;
    this.volumeService.close(); this.brightnessService.close();
  }
  requestSystemVolume(value: number): void {
    if (!this.active || !this.foreground || !this.volumeReady) { this.showHint('系统音量暂不可用，请使用音量键'); return; }
    const level = Math.round(Math.max(this.volumeMin,Math.min(this.volumeMax,value)));
    if (this.volumePanelVisible && level === this.requestedVolume) return;
    if (!this.volumePanelVisible && level === this.volumeLevel) return;
    this.requestedVolume = level; this.volumeCommandIssued = true; this.volumePanelVisible = true;
    this.showHint(`媒体音量 ${this.volumeLevel} / ${this.volumeMax}`);
    clearTimeout(this.volumeTimer);
    // Hiding the prompt must never change its command value: undefined can reset AVVolumePanel to zero.
    this.volumeTimer = setTimeout((): void => { this.volumePanelVisible = false; },1300);
  }
  setBrightness(value: number): void {
    if (this.brightnessService.set(value)) {
      this.screenBrightness = value; this.followsSystemBrightness = false; this.showHint(`亮度 ${Math.round(value*100)}%`);
    } else this.showHint('亮度调整暂不可用');
  }
  playbackChanged(): void { if (this.playing) this.armHide(); else { this.endHold(); clearTimeout(this.hideTimer); this.visible = true; } }
  fullscreenChanged(): void { this.endHold(); this.locked = false; this.panel = ''; this.activity(); }
  armHide(): void {
    clearTimeout(this.hideTimer);
    if (this.playing && !this.panel && !this.scrubbing) this.hideTimer = setTimeout((): void => { this.visible = false; },3200);
  }
  activity(): void { this.visible = true; this.armHide(); }
  showHint(value: string): void { this.hint = value; clearTimeout(this.hintTimer); this.hintTimer = setTimeout((): void => { this.hint = ''; },1300); }
  time(value: number): string {
    const t = Math.max(0,Math.floor(value));
    return t >= 3600 ? `${Math.floor(t/3600)}:${String(Math.floor(t/60)%60).padStart(2,'0')}:${String(t%60).padStart(2,'0')}`
      : `${Math.floor(t/60)}:${String(t%60).padStart(2,'0')}`;
  }
  toggle(): void { if (this.playing) this.controller.pause(); else this.controller.start(); this.activity(); }
  seek(value: number): void {
    if (this.duration <= 0) { this.showHint('当前媒体尚不可定位'); return; }
    this.controller.setCurrentTime(Math.max(0,Math.min(this.duration-0.2,value))); this.activity();
  }
  setRate(value: number): void { this.rate = value; this.controller.setRate(value); this.activity(); }
  endHold(): void { if (this.holding) { this.holding = false; this.controller.setRate(this.oldRate); this.hint = ''; } }
  doubleTap(event: GestureEvent): void {
    if (this.locked || this.inPip) return;
    const x = event.fingerList[0]?.localX || 0;
    if (x < this.widthVp/3) { this.seek(this.elapsed-10); this.showHint('快退 10 秒'); }
    else if (x > this.widthVp*2/3) { this.seek(this.elapsed+10); this.showHint('快进 10 秒'); }
    else this.toggle();
  }
  panStart(event: GestureEvent): void {
    if (this.locked || this.inPip) return;
    this.endHold(); this.panAxis = 0; this.panCancelled = false; this.startTime = this.elapsed; this.volumeService.refresh();
    this.startVolume = this.volumeLevel; this.startBrightness = this.screenBrightness;
    const startX = (event.fingerList[0]?.localX || 0)-event.offsetX;
    this.panSide = startX < this.widthVp/2 ? 1 : 2;
    this.panSeek = this.elapsed; clearTimeout(this.hideTimer);
  }
  panUpdate(event: GestureEvent): void {
    if (this.locked || this.inPip || this.panCancelled) return;
    if (this.panAxis === 0) this.panAxis = Math.abs(event.offsetX) > Math.abs(event.offsetY) ? 1 : 2;
    if (this.panAxis === 1 && this.duration > 0) {
      // A deliberate upward swipe cancels the pending seek instead of committing it.
      if (this.scrubbing && event.offsetY < -48) {
        this.panCancelled = true; this.scrubbing = false; this.previewTime = this.elapsed; this.hint = '已取消跳转';
        return;
      }
      this.scrubbing = true;
      this.panSeek = Math.max(0,Math.min(this.duration-0.2,this.startTime+event.offsetX/this.widthVp*Math.min(this.duration,300)));
      this.previewTime = this.panSeek; this.hint = `${this.time(this.panSeek)} / ${this.time(this.duration)} · 上滑取消`;
    } else if (this.panAxis === 2 && this.panSide === 2) {
      this.requestSystemVolume(volumeFromSwipe(this.startVolume,this.volumeMin,this.volumeMax,event.offsetY,this.heightVp));
    } else if (this.panAxis === 2 && this.panSide === 1) {
      this.setBrightness(brightnessFromSwipe(this.startBrightness,event.offsetY,this.heightVp));
    }
  }
  panEnd(commit: boolean): void {
    if (commit && this.scrubbing) this.seek(this.panSeek);
    this.brightnessService.flush(); this.scrubbing = false; this.panCancelled = false;
    if (this.hint) this.showHint(this.hint); this.armHide();
  }
  openPanel(name: string): void {
    this.getUIContext().animateTo({duration:this.reduceMotion ? 0 : 180,curve:Curve.EaseOut},(): void => {
      this.panel = this.panel === name ? '' : name; this.visible = true;
    });
    clearTimeout(this.hideTimer); if (!this.panel) this.armHide();
  }
  @Builder
  icon(asset: Resource, label: string, action: () => void, large: boolean = false) {
    Button({type:ButtonType.Circle}) { Image(asset).width(large ? 28 : 22).height(large ? 28 : 22).objectFit(ImageFit.Contain) }
      .width(large ? 56 : 40).height(large ? 56 : 40).backgroundColor(Color.Transparent)
      .accessibilityText(label).stateStyles({pressed:{opacity:0.6}}).onClick(action)
  }
  @Builder
  castGlyph() {
    Stack({alignContent:Alignment.Center}) {
      SymbolGlyph($r('sys.symbol.statusbar_cast')).fontSize(22).fontColor([WHITE])
    }.width('100%').height('100%')
  }
  @Builder
  castButton() {
    Stack() {
      // The official picker owns device discovery; the builder only replaces its look.
      AVCastPicker({normalColor:WHITE,activeColor:MINT,sessionType:'video',
        customPicker:(): void => this.castGlyph(),
        onStateChange:(state: AVCastPickerState): void => {
          if (state === AVCastPickerState.STATE_APPEARING) this.activity();
          else this.armHide();
        }
      }).width(40).height(40).backgroundColor(Color.Transparent)
    }.width(40).height(40).borderRadius(20).clip(true)
  }
  @Builder
  castOverlay() {
    Column() {
      Column({space:10}) {
        SymbolGlyph($r('sys.symbol.statusbar_cast')).fontSize(32).fontColor([MINT])
        Text('正在投屏').fontSize(11).fontColor(MINT)
        Text(this.castDevice || '已连接的设备').fontSize(17).fontWeight(FontWeight.Medium).fontColor(WHITE).maxLines(1)
        Text(this.duration > 0 ? `${this.time(this.castElapsed)} / ${this.time(this.duration)}` : this.time(this.castElapsed))
          .fontSize(11).fontColor('#B9C6CF')
        Row({space:10}) {
          Button(this.castPlaying ? '暂停' : '播放',{type:ButtonType.Normal}).height(34).fontSize(12).borderRadius(10)
            .backgroundColor('#20FFFFFF').fontColor(WHITE).padding({left:16,right:16})
            .onClick((): void => this.onCastToggle())
          Button('停止投屏',{type:ButtonType.Normal}).height(34).fontSize(12).borderRadius(10)
            .backgroundColor(MINT).fontColor('#132A29').padding({left:16,right:16})
            .onClick((): void => this.onCastStop())
        }
      }.padding(20).width('76%').backgroundColor('#F21B2531').border({width:1,color:'#26FFFFFF'}).borderRadius(20)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#6608111A')
  }
  @Builder
  skipButton(forward: boolean) {
    Button({type:ButtonType.Normal}) {
      Column({space:2}) {
        Image(forward ? $r('app.media.player_forward') : $r('app.media.player_rewind')).width(25).height(25).objectFit(ImageFit.Contain)
        Text('10 秒').fontSize(10).fontWeight(FontWeight.Medium).fontColor(WHITE)
      }.justifyContent(FlexAlign.Center).width('100%').height('100%')
    }.width(48).height(52).borderRadius(16).backgroundColor(Color.Transparent)
      .stateStyles({pressed:{opacity:0.55}})
      .accessibilityText(forward ? '快进十秒' : '快退十秒').onClick((): void => {
        this.seek(this.elapsed+(forward ? 10 : -10)); this.showHint(forward ? '快进 10 秒' : '快退 10 秒');
      })
  }
  @Builder
  controls() {
    Column() {
      Row({space:10}) {
        Column({space:3}) {
          Text(this.title || 'WTV PLAYER').fontSize(13).fontWeight(FontWeight.Medium).fontColor(WHITE).maxLines(1).width('100%')
          Text(this.subtitle || '原生播放').fontSize(10).fontColor('#B9C6CF').maxLines(1).width('100%')
        }.layoutWeight(1)
        if (this.fullscreen) { this.icon($r('app.media.player_lock'),'锁定播放控件',(): void => { this.locked = true; this.panel = ''; this.visible = false; }) }
        if (this.castReady) { this.castButton() }
        this.icon($r('app.media.player_pip'),'小窗播放',(): void => this.onSmallWindow())
        this.icon($r('app.media.player_settings'),'播放设置',(): void => this.openPanel('settings'))
      }.width('100%')
      Blank()
      Row({space:22}) {
        this.skipButton(false)
        // A state-dependent Resource passed by value to @Builder does not refresh its Image.
        if (this.playing) {
          this.icon($r('app.media.player_pause'),'暂停',(): void => this.toggle(),true)
        } else {
          this.icon($r('app.media.player_play'),'播放',(): void => this.toggle(),true)
        }
        this.skipButton(true)
      }.width('100%').justifyContent(FlexAlign.Center)
      Blank()
      Slider({value:this.scrubbing ? this.previewTime : this.elapsed,min:0,max:Math.max(1,this.duration),step:0.1,style:SliderStyle.OutSet})
        .blockSize({width:10,height:10}).trackThickness(3).selectedColor(MINT).trackColor('#55FFFFFF').blockColor(WHITE)
        .enabled(this.duration > 0).width('100%').height(24)
        .onChange((value: number,mode: SliderChangeMode): void => {
          this.previewTime = value; this.scrubbing = true; clearTimeout(this.hideTimer);
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.seek(value); this.scrubbing = false; this.armHide(); }
        })
      Row({space:8}) {
        Text(`${this.time(this.scrubbing ? this.previewTime : this.elapsed)} / ${this.time(this.duration)}`).fontSize(10).fontColor('#D8E2E9').layoutWeight(1)
        Button(`${this.rate}×`,{type:ButtonType.Normal}).fontSize(12).fontColor(WHITE).backgroundColor('#20FFFFFF').borderRadius(10).height(30).padding({left:10,right:10})
          .accessibilityText('切换播放倍速').onClick((): void => this.setRate(NATIVE_RATES[(NATIVE_RATES.indexOf(this.rate)+1)%NATIVE_RATES.length]))
        if (this.episodeNames.length > 0) {
          Button('选集',{type:ButtonType.Normal}).fontSize(12).fontColor(WHITE).backgroundColor('#20FFFFFF').borderRadius(10).height(30).padding({left:10,right:10})
            .onClick((): void => this.openPanel('episodes'))
        }
        if (this.fullscreen) {
          this.icon($r('app.media.player_collapse'),'退出全屏',(): void => { this.panel = ''; this.onFullscreen(false); this.activity(); })
        } else {
          this.icon($r('app.media.player_expand'),'横屏全屏',(): void => { this.panel = ''; this.onFullscreen(true); this.activity(); })
        }
      }.width('100%')
    }.padding({left:14+(this.fullscreen ? this.getUIContext().px2vp(this.safeLeft) : 0),right:14+(this.fullscreen ? this.getUIContext().px2vp(this.safeRight) : 0),top:8,
      bottom:8+(this.fullscreen ? this.getUIContext().px2vp(this.safeBottom) : 0)})
      .width('100%').height('100%').linearGradient({angle:180,colors:[['#C9000000',0],['#10000000',0.38],['#CC000000',1]]}).hitTestBehavior(HitTestMode.Transparent)
  }
  @Builder
  optionsPanel() {
    Column({space:10}) {
      Row() {
        Text(this.panel === 'settings' ? '播放设置' : '选集').fontSize(15).fontWeight(FontWeight.Medium).fontColor(WHITE).layoutWeight(1)
        Button('完成',{type:ButtonType.Normal}).fontSize(12).fontColor(MINT).backgroundColor(Color.Transparent).height(32).onClick((): void => this.openPanel(this.panel))
      }.width('100%')
      if (this.panel === 'settings') {
        Scroll() {
        Column({space:10}) {
        Row() {
          Text('倍速').fontSize(12).fontColor('#B9C6CF').layoutWeight(1)
          Select(NATIVE_RATES.map((value: number): SelectOption => ({value:`${value}×`}))).selected(NATIVE_RATES.indexOf(this.rate)).value(`${this.rate}×`)
            .fontColor(WHITE).backgroundColor('#2C3945').font({size:12}).onSelect((index: number): void => this.setRate(NATIVE_RATES[index]))
        }.width('100%')
        Row({space:8}) {
          Button(this.volumeLevel === this.volumeMin ? '恢复声音' : '静音',{type:ButtonType.Normal}).fontSize(11).fontColor(WHITE).backgroundColor('#2C3945').height(30).borderRadius(10).enabled(this.volumeReady)
            .onClick((): void => this.requestSystemVolume(this.volumeLevel === this.volumeMin ? Math.max(this.volumeMin+1,this.unmutedLevel) : this.volumeMin))
          Slider({value:this.volumeLevel,min:this.volumeMin,max:this.volumeMax,step:1}).selectedColor(MINT).layoutWeight(1).enabled(this.volumeReady)
            .onChange((value: number): void => this.requestSystemVolume(value))
        }.width('100%')
        Text(`系统媒体音量 ${this.volumeLevel} / ${this.volumeMax}`).fontSize(10).fontColor('#B9C6CF').width('100%')
        Row({space:8}) {
          Button('跟随系统',{type:ButtonType.Normal}).fontSize(11).fontColor(WHITE).backgroundColor('#2C3945').height(30).borderRadius(10).enabled(this.brightnessReady)
            .onClick((): void => { if (this.brightnessService.followSystem()) { this.followsSystemBrightness = true; this.showHint('亮度跟随系统'); } })
          Slider({value:this.screenBrightness,min:0.05,max:1,step:0.01}).selectedColor(MINT).layoutWeight(1).enabled(this.brightnessReady)
            .onChange((value: number): void => this.setBrightness(value))
        }.width('100%')
        Text(this.followsSystemBrightness ? '屏幕亮度 · 跟随系统' : `屏幕亮度 ${Math.round(this.screenBrightness*100)}%`).fontSize(10).fontColor('#B9C6CF').width('100%')
        Text(this.status || '原生 MPV').fontSize(10).fontColor(MINT).width('100%')
        Text('双击两侧快退 / 快进 10 秒 · 双击中间暂停\n左右滑动定位 · 长按 2×\n左侧上下滑调亮度 · 右侧上下滑调系统媒体音量').fontSize(10).lineHeight(16).fontColor('#B9C6CF').width('100%')
        }.width('100%')
        }.height(this.fullscreen ? 220 : 140).width('100%').scrollBar(BarState.Off)
      } else {
        Scroll() {
          Column({space:6}) {
            ForEach(this.episodeNames,(name: string,index: number) => {
              Button(name,{type:ButtonType.Normal}).fontSize(12).fontColor(index === this.episodeIndex ? MINT : WHITE).backgroundColor(index === this.episodeIndex ? '#244B43' : '#26333E')
                .borderRadius(10).width('100%').constraintSize({minHeight:36}).padding(10).onClick((): void => { this.panel = ''; this.onEpisode(index); this.armHide(); })
            })
          }.width('100%')
        }.height(this.fullscreen ? 200 : 100).width('100%')
      }
    }.padding(14).width(this.fullscreen ? 300 : '90%').backgroundColor('#F21B2531').border({width:1,color:'#26FFFFFF'}).borderRadius(18)
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({y:8})))
  }
  build() {
    Stack() {
      Stack() {
        NodeContainer(this.surface)
          .width('100%').height('100%')
      }.width(this.nodeWidthVp()).height(this.nodeHeightVp()).clip(true)
      Column().width('100%').height('100%').backgroundColor(Color.Transparent)
        .gesture(GestureGroup(GestureMode.Exclusive,
          LongPressGesture({repeat:false,duration:500}).onAction((): void => {
            if (this.locked || this.inPip || !this.playing) return;
            this.oldRate = this.rate; this.holding = true; this.controller.setRate(2); this.hint = '2× 加速中 · 松手恢复';
          }).onActionEnd((): void => this.endHold()).onActionCancel((): void => this.endHold()),
          PanGesture({direction:PanDirection.All,distance:12}).onActionStart((event: GestureEvent): void => this.panStart(event)).onActionUpdate((event: GestureEvent): void => this.panUpdate(event))
            .onActionEnd((): void => this.panEnd(true)).onActionCancel((): void => this.panEnd(false)),
          TapGesture({count:2}).onAction((event: GestureEvent): void => this.doubleTap(event)),
          TapGesture().onAction((): void => { if (!this.locked && !this.inPip && !this.casting) { this.visible = !this.visible; this.panel = ''; this.armHide(); } })
        ))
      if (this.casting && !this.locked) { this.castOverlay() }
      if (this.visible && !this.locked && !this.panel && !this.inPip && !this.casting) { this.controls() }
      if (this.buffering && !this.error) { LoadingProgress().width(34).height(34).color(MINT).hitTestBehavior(HitTestMode.None) }
      if (this.hint) { Text(this.hint).fontSize(13).fontColor(WHITE).backgroundColor('#C0192631').padding(12).borderRadius(12).hitTestBehavior(HitTestMode.None) }
      if (this.active && this.foreground && this.volumeReady && this.volumeCommandIssued) {
        AVVolumePanel({volumeLevel:this.requestedVolume}).width(10).height(1)
          .visibility(this.volumePanelVisible ? Visibility.Visible : Visibility.Hidden).hitTestBehavior(HitTestMode.None)
      }
      if (this.panel && !this.locked) {
        Column().width('100%').height('100%').backgroundColor('#4DFFFFFF')
          .onClick((): void => { this.panel = ''; this.armHide(); })
        this.optionsPanel()
      }
      if (this.inPip) {
        Column({space:12}) {
          Text('正在小窗播放').fontSize(14).fontColor(WHITE)
          Button('返回播放框',{type:ButtonType.Normal}).height(36).fontSize(12).backgroundColor(MINT).fontColor('#132A29').borderRadius(12)
            .onClick((): void => this.onRestoreWindow())
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#0D141E')
      }
      if (this.locked) {
        Row() {
          this.icon($r('app.media.player_unlock'),'解锁播放控件',(): void => { this.locked = false; this.activity(); })
          Blank()
        }.width('100%').padding(20)
      }
      if (this.error) {
        Column({space:12}) {
          Text(this.error).fontSize(12).fontColor(WHITE).lineHeight(19).textAlign(TextAlign.Center)
          Button('重新播放',{type:ButtonType.Normal}).height(36).fontSize(12).backgroundColor(MINT).fontColor('#132A29').borderRadius(12).onClick((): void => this.onRetry())
          if (this.fullscreen) {
            Button('退出全屏',{type:ButtonType.Normal}).height(32).fontSize(12).backgroundColor('#263A43').fontColor(WHITE).borderRadius(12).onClick((): void => this.onFullscreen(false))
          }
        }.padding(20).width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#DF111923')
      }
    }.width('100%').height('100%').backgroundColor('#0D141E').clip(true)
      .onAreaChange((_old: Area,next: Area): void => {
        this.widthVp = Number(next.width)||360; this.heightVp = Number(next.height)||220;
        this.applyNodeSize();
      })
  }
}
