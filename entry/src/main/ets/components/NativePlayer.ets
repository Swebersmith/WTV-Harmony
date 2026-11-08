import { NativePlayback, NATIVE_RATES } from '../services/NativePlayback';

const WHITE: string = '#F3F6FA';
const MINT: string = '#A1E6D0';

@Component
export struct NativePlayer {
  controller: NativePlayback = new NativePlayback();
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
  @Prop episodeNames: string[] = [];
  @Prop episodeIndex: number = -1;
  onFullscreen: (value: boolean) => void = (): void => {};
  onEpisode: (index: number) => void = (): void => {};
  onRetry: () => void = (): void => {};
  private hideTimer: number = -1;
  private hintTimer: number = -1;
  private widthVp: number = 360;
  private heightVp: number = 220;
  private startTime: number = 0;
  private startVolume: number = 0.7;
  private panAxis: number = 0;
  private panSeek: number = 0;
  private oldRate: number = 1;
  @State visible: boolean = true;
  @State locked: boolean = false;
  @State panel: string = '';
  @State rate: number = 1;
  @State volume: number = 0.7;
  @State scrubbing: boolean = false;
  @State previewTime: number = 0;
  @State hint: string = '';
  @State holding: boolean = false;
  @StorageProp('safeLeftPx') safeLeft: number = 0;
  @StorageProp('safeRightPx') safeRight: number = 0;
  @StorageProp('safeBottomPx') safeBottom: number = 0;

  aboutToAppear(): void { this.rate = this.controller.getRate(); this.volume = this.controller.getVolume(); }
  aboutToDisappear(): void { this.endHold(); clearTimeout(this.hideTimer); clearTimeout(this.hintTimer); this.controller.detach(); }
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
    if (this.locked) return;
    const x = event.fingerList[0]?.localX || 0;
    if (x < this.widthVp/3) { this.seek(this.elapsed-10); this.showHint('快退 10 秒'); }
    else if (x > this.widthVp*2/3) { this.seek(this.elapsed+10); this.showHint('快进 10 秒'); }
    else this.toggle();
  }
  panStart(): void { this.endHold(); this.panAxis = 0; this.startTime = this.elapsed; this.startVolume = this.volume; this.panSeek = this.elapsed; clearTimeout(this.hideTimer); }
  panUpdate(event: GestureEvent): void {
    if (this.locked) return;
    if (this.panAxis === 0) this.panAxis = Math.abs(event.offsetX) > Math.abs(event.offsetY) ? 1 : 2;
    if (this.panAxis === 1 && this.duration > 0) {
      this.scrubbing = true;
      this.panSeek = Math.max(0,Math.min(this.duration-0.2,this.startTime+event.offsetX/this.widthVp*Math.min(this.duration,300)));
      this.previewTime = this.panSeek; this.hint = `${this.time(this.panSeek)} / ${this.time(this.duration)}`;
    } else if (this.panAxis === 2 && (event.fingerList[0]?.localX || 0) > this.widthVp*0.6) {
      this.volume = Math.max(0,Math.min(1,this.startVolume-event.offsetY/(this.heightVp*0.8)));
      this.controller.setVolume(this.volume); this.hint = `音量 ${Math.round(this.volume*100)}%`;
    }
  }
  panEnd(commit: boolean): void {
    if (commit && this.scrubbing) this.seek(this.panSeek);
    this.scrubbing = false; this.hint = ''; this.armHide();
  }
  openPanel(name: string): void {
    this.getUIContext().animateTo({duration:this.reduceMotion ? 0 : 180,curve:Curve.EaseOut},(): void => {
      this.panel = this.panel === name ? '' : name; this.visible = true;
    });
    clearTimeout(this.hideTimer); if (!this.panel) this.armHide();
  }
  @Builder
  icon(asset: Resource, label: string, action: () => void, large: boolean = false) {
    Button({type:ButtonType.Circle}) { Image(asset).width(large ? 26 : 21).height(large ? 26 : 21).fillColor(WHITE) }
      .width(large ? 54 : 40).height(large ? 54 : 40).backgroundColor(large ? '#33A1E6D0' : '#08000000')
      .accessibilityText(label).stateStyles({pressed:{backgroundColor:'#40A1E6D0'}}).onClick(action)
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
        this.icon($r('app.media.player_settings'),'播放设置',(): void => this.openPanel('settings'))
      }.width('100%')
      Blank()
      Row({space:22}) {
        this.icon($r('app.media.player_rewind'),'快退十秒',(): void => { this.seek(this.elapsed-10); this.showHint('快退 10 秒'); })
        this.icon(this.playing ? $r('app.media.player_pause') : $r('app.media.player_play'),this.playing ? '暂停' : '播放',(): void => this.toggle(),true)
        this.icon($r('app.media.player_forward'),'快进十秒',(): void => { this.seek(this.elapsed+10); this.showHint('快进 10 秒'); })
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
        this.icon(this.fullscreen ? $r('app.media.player_collapse') : $r('app.media.player_expand'),this.fullscreen ? '退出全屏' : '横屏全屏',(): void => { this.panel = ''; this.onFullscreen(!this.fullscreen); this.activity(); })
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
        Row() {
          Text('倍速').fontSize(12).fontColor('#B9C6CF').layoutWeight(1)
          Select(NATIVE_RATES.map((value: number): SelectOption => ({value:`${value}×`}))).selected(NATIVE_RATES.indexOf(this.rate)).value(`${this.rate}×`)
            .fontColor(WHITE).backgroundColor('#2C3945').font({size:12}).onSelect((index: number): void => this.setRate(NATIVE_RATES[index]))
        }.width('100%')
        Row({space:8}) {
          Button(this.volume === 0 ? '取消静音' : '静音',{type:ButtonType.Normal}).fontSize(11).fontColor(WHITE).backgroundColor('#2C3945').height(30).borderRadius(10)
            .onClick((): void => { this.volume = this.volume === 0 ? 0.7 : 0; this.controller.setVolume(this.volume); })
          Slider({value:this.volume,min:0,max:1,step:0.01}).selectedColor(MINT).layoutWeight(1).onChange((value: number): void => { this.volume = value; this.controller.setVolume(value); })
        }.width('100%')
        Text(this.status || '原生 MPV').fontSize(10).fontColor(MINT).width('100%')
        Text('双击两侧快退 / 快进 10 秒 · 双击中间暂停\n左右滑动定位 · 长按 2× · 右侧上下滑调音量').fontSize(10).lineHeight(16).fontColor('#B9C6CF').width('100%')
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
      XComponent({id:'wtv-native-surface',type:XComponentType.SURFACE,controller:this.controller})
        .width('100%').height('100%')
      Column().width('100%').height('100%').backgroundColor(Color.Transparent)
        .gesture(GestureGroup(GestureMode.Exclusive,
          LongPressGesture({repeat:false,duration:500}).onAction((): void => {
            if (this.locked || !this.playing) return;
            this.oldRate = this.rate; this.holding = true; this.controller.setRate(2); this.hint = '2× 加速中 · 松手恢复';
          }).onActionEnd((): void => this.endHold()).onActionCancel((): void => this.endHold()),
          PanGesture({direction:PanDirection.All,distance:12}).onActionStart((): void => this.panStart()).onActionUpdate((event: GestureEvent): void => this.panUpdate(event))
            .onActionEnd((): void => this.panEnd(true)).onActionCancel((): void => this.panEnd(false)),
          TapGesture({count:2}).onAction((event: GestureEvent): void => this.doubleTap(event)),
          TapGesture().onAction((): void => { if (!this.locked) { this.visible = !this.visible; this.panel = ''; this.armHide(); } })
        ))
      if ((this.visible || !this.playing) && !this.locked && !this.panel) { this.controls() }
      if (this.buffering && !this.error) { LoadingProgress().width(34).height(34).color(MINT).hitTestBehavior(HitTestMode.None) }
      if (this.hint) { Text(this.hint).fontSize(13).fontColor(WHITE).backgroundColor('#C0192631').padding(12).borderRadius(12).hitTestBehavior(HitTestMode.None) }
      if (this.panel && !this.locked) { this.optionsPanel() }
      if (this.locked) {
        Row() {
          this.icon($r('app.media.player_lock'),'解锁播放控件',(): void => { this.locked = false; this.activity(); })
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
        this.controller.resize(this.getUIContext().vp2px(this.widthVp),this.getUIContext().vp2px(this.heightVp));
      })
  }
}
