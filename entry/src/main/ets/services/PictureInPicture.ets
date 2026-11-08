import { PiPWindow } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

export interface PictureCommands {
  play: () => void; pause: () => void; next: () => void; previous: () => void;
  changed: (active: boolean) => void; restore: () => void; failed: () => void;
}
export class PictureInPicture {
  private controller?: PiPWindow.PiPController;
  private creating?: Promise<void>;
  private closing?: Promise<void>;
  private commands?: PictureCommands;
  private active: boolean = false;
  private restoring: boolean = false;
  private autoStart: boolean = false;
  private disposed: boolean = false;
  private eligible: boolean = false;
  private playing: boolean = false;
  private canPrevious: boolean = false;
  private canNext: boolean = false;
  private width: number = 1920;
  private height: number = 1080;
  private stateChanged: (state: PiPWindow.PiPState, reason: string) => void = (state: PiPWindow.PiPState): void => {
    if (this.disposed) return;
    if (state === PiPWindow.PiPState.ABOUT_TO_START || state === PiPWindow.PiPState.STARTED) {
      this.active = true; this.restoring = false; this.commands?.changed(true); this.updateControls();
    } else if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
      this.restoring = true; this.commands?.restore();
    } else if (state === PiPWindow.PiPState.STOPPED) {
      const restoring = this.restoring; this.active = false; this.restoring = false;
      this.commands?.changed(false); if (!restoring) this.commands?.pause();
    } else if (state === PiPWindow.PiPState.ERROR) {
      this.active = false; this.commands?.changed(false); this.commands?.failed();
    }
  };
  private controlEvent: (event: PiPWindow.ControlEventParam) => void = (event: PiPWindow.ControlEventParam): void => {
    if (!this.active || this.disposed) return;
    if (event.controlType === PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
      if (event.status === PiPWindow.PiPControlStatus.PLAY) this.commands?.play(); else this.commands?.pause();
    } else if (event.controlType === PiPWindow.PiPControlType.VIDEO_NEXT && this.canNext) this.commands?.next();
    else if (event.controlType === PiPWindow.PiPControlType.VIDEO_PREVIOUS && this.canPrevious) this.commands?.previous();
  };
  isActive(): boolean { return this.active; }
  async open(context: common.UIAbilityContext, surface: XComponentController, commands: PictureCommands): Promise<void> {
    await this.closing;
    this.commands = commands;
    if (this.controller) return;
    if (this.creating) return this.creating;
    if (!PiPWindow.isPiPEnabled()) throw new Error('当前设备暂不支持系统小窗');
    this.disposed = false;
    this.creating = this.create(context,surface);
    try { await this.creating; } finally { this.creating = undefined; }
  }
  private async create(context: common.UIAbilityContext, surface: XComponentController): Promise<void> {
    const controller = await PiPWindow.create({context,componentController:surface,navigationId:'wtv-root-navigation',
      templateType:PiPWindow.PiPTemplateType.VIDEO_PLAY,contentWidth:this.width,contentHeight:this.height,
      controlGroups:[PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT]});
    if (this.disposed) { controller.setAutoStartEnabled(false); return; }
    this.controller = controller;
    controller.on('stateChange',this.stateChanged); controller.on('controlEvent',this.controlEvent); this.updateControls();
  }
  configure(auto: boolean, eligible: boolean, playing: boolean, previous: boolean, next: boolean): void {
    this.autoStart = auto; this.eligible = eligible; this.playing = playing; this.canPrevious = previous; this.canNext = next; this.updateControls();
  }
  private updateControls(): void {
    try {
      this.controller?.setAutoStartEnabled(this.autoStart && this.eligible && this.playing);
      this.controller?.updatePiPControlStatus(PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,this.playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE);
      this.controller?.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_PREVIOUS,this.canPrevious);
      this.controller?.setPiPControlEnabled(PiPWindow.PiPControlType.VIDEO_NEXT,this.canNext);
    } catch {}
  }
  size(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return;
    this.width = Math.round(width); this.height = Math.round(height);
    try { this.controller?.updateContentSize(this.width,this.height); } catch {}
  }
  async start(): Promise<void> {
    if (!this.controller || this.disposed || !this.eligible) throw new Error('请先播放原生视频，再开启小窗');
    if (this.active) return;
    this.restoring = false; await this.controller.startPiP();
  }
  async stop(restore: boolean = true): Promise<void> {
    if (!this.controller || !this.active) return;
    this.restoring = restore; await this.controller.stopPiP();
  }
  async close(): Promise<void> {
    if (this.closing) return this.closing;
    this.closing = this.destroy();
    try { await this.closing; } finally { this.closing = undefined; }
  }
  private async destroy(): Promise<void> {
    this.disposed = true;
    await this.creating?.catch((): void => {});
    const controller = this.controller; this.controller = undefined;
    try {
      controller?.setAutoStartEnabled(false);
      if (this.active) await controller?.stopPiP();
    } finally {
      controller?.off('stateChange'); controller?.off('controlEvent',this.controlEvent);
      this.active = false; this.commands = undefined;
    }
  }
}
