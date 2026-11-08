import { PiPWindow, UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VideoSurface } from './VideoSurface';
import { PlaybackDiagnostics } from './PlaybackDiagnostics';

export interface PictureCommands {
  play: () => void; pause: () => void; next: () => void; previous: () => void;
  skip?: (seconds: number) => void;
  changed: (active: boolean) => void; restore: () => void; failed: () => void;
}
// The official preview/PiP pattern moves the same typeNode between its two parents.
export class PictureInPicture {
  private controller?: PiPWindow.PiPController;
  private surface?: VideoSurface;
  private creating?: Promise<void>;
  private starting?: Promise<void>;
  private closing?: Promise<void>;
  private commands?: PictureCommands;
  private active: boolean = false;
  private restoring: boolean = false;
  private repairing: boolean = false;
  private autoStart: boolean = false;
  private appliedAuto?: boolean;
  private disposed: boolean = false;
  private eligible: boolean = false;
  private playing: boolean = false;
  private canPrevious: boolean = false;
  private canNext: boolean = false;
  private width: number = 1920;
  private height: number = 1080;
  private setActive(value: boolean): void {
    this.surface?.setInPip(value);
    if (this.active === value) return;
    this.active = value; this.commands?.changed(value);
  }
  private stateChanged: (state: PiPWindow.PiPState, reason: string) => void = (state: PiPWindow.PiPState, reason: string): void => {
    PlaybackDiagnostics.record(`PiP state=${state} reason=${reason}`);
    if (this.disposed) return;
    if (state === PiPWindow.PiPState.ABOUT_TO_START || state === PiPWindow.PiPState.STARTED) {
      this.restoring = false; this.setActive(true); this.updateControls();
    } else if (state === PiPWindow.PiPState.ABOUT_TO_STOP) {
      this.surface?.setInPip(false);
    } else if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
      this.restoring = true; this.commands?.restore();
    } else if (state === PiPWindow.PiPState.STOPPED) {
      const restoring = this.restoring || this.repairing; this.restoring = false;
      this.setActive(false); if (!restoring) this.commands?.pause();
    } else if (state === PiPWindow.PiPState.ERROR) {
      this.setActive(false); if (!this.repairing) this.commands?.failed();
    }
  };
  private controlEvent: (event: PiPWindow.ControlEventParam) => void = (event: PiPWindow.ControlEventParam): void => {
    if (!this.active || this.disposed) return;
    if (event.controlType === PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE) {
      if (event.status === PiPWindow.PiPControlStatus.PLAY) this.commands?.play(); else this.commands?.pause();
    } else if (event.controlType === PiPWindow.PiPControlType.VIDEO_NEXT && this.canNext) this.commands?.next();
    else if (event.controlType === PiPWindow.PiPControlType.VIDEO_PREVIOUS && this.canPrevious) this.commands?.previous();
    else if (event.controlType === PiPWindow.PiPControlType.FAST_FORWARD) this.commands?.skip?.(10);
    else if (event.controlType === PiPWindow.PiPControlType.FAST_BACKWARD) this.commands?.skip?.(-10);
  };
  isActive(): boolean { return this.active; }
  async open(context: common.UIAbilityContext, surface: VideoSurface, commands: PictureCommands, uiContext: UIContext): Promise<void> {
    await this.closing;
    this.commands = commands; this.surface = surface;
    if (this.controller) return;
    if (this.creating) return this.creating;
    if (!PiPWindow.isPiPEnabled()) throw new Error('当前设备暂不支持系统小窗');
    this.disposed = false;
    this.creating = this.create(context,surface,uiContext);
    try { await this.creating; } finally { this.creating = undefined; }
  }
  private async create(context: common.UIAbilityContext, surface: VideoSurface, uiContext: UIContext): Promise<void> {
    const node = surface.getContent(uiContext);
    try {
      const controller = await PiPWindow.create({context,componentController:surface.controller,
        templateType:PiPWindow.PiPTemplateType.VIDEO_PLAY,contentWidth:this.width,contentHeight:this.height,
        controlGroups:[PiPWindow.VideoPlayControlGroup.FAST_FORWARD_BACKWARD]},node);
      if (this.disposed) { controller.setAutoStartEnabled(false); return; }
      this.controller = controller; this.appliedAuto = undefined;
      controller.on('stateChange',this.stateChanged); controller.on('controlEvent',this.controlEvent); this.updateControls();
    } catch (error) { PlaybackDiagnostics.record(`PiP create error=${(error as BusinessError).code}`); throw error as Error; }
  }
  configure(auto: boolean, eligible: boolean, playing: boolean, previous: boolean, next: boolean): void {
    this.autoStart = auto; this.eligible = eligible; this.playing = playing; this.canPrevious = previous; this.canNext = next; this.updateControls();
  }
  private updateControls(): void {
    const controller = this.controller; if (!controller) return;
    const auto = this.autoStart && this.eligible && this.playing;
    if (this.appliedAuto !== auto) {
      try { controller.setAutoStartEnabled(auto); this.appliedAuto = auto; PlaybackDiagnostics.record(`PiP auto=${auto}`); }
      catch (error) { PlaybackDiagnostics.record(`PiP auto error=${(error as BusinessError).code}`); }
    }
    try { controller.updatePiPControlStatus(PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,this.playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE); } catch {}
    try { controller.setPiPControlEnabled(PiPWindow.PiPControlType.FAST_FORWARD,true); } catch {}
    try { controller.setPiPControlEnabled(PiPWindow.PiPControlType.FAST_BACKWARD,true); } catch {}
  }
  size(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return;
    const w = Math.round(width), h = Math.round(height);
    if (w === this.width && h === this.height) return;
    this.width = w; this.height = h;
    try { this.controller?.updateContentSize(w,h); } catch {}
  }
  async start(): Promise<void> {
    if (!this.controller || this.disposed || !this.eligible) throw new Error('请先播放原生视频，再开启小窗');
    if (this.starting) return this.starting;
    if (this.active) return;
    this.starting = this.startOnce();
    try { await this.starting; } finally { this.starting = undefined; }
  }
  private async startOnce(): Promise<void> {
    const controller = this.controller; if (!controller) return;
    if (await controller.isPiPActive()) { this.setActive(true); return; }
    if (this.active || this.disposed) return;
    this.restoring = false;
    try { await controller.startPiP(); }
    catch (error) {
      PlaybackDiagnostics.record(`PiP start error=${(error as BusinessError).code}`);
      if ((error as BusinessError).code !== 1300012 && (error as BusinessError).code !== 1300015) throw new Error(`小窗启动失败（${(error as BusinessError).code || '未知错误'}）`);
      if (this.active || await controller.isPiPActive()) { this.setActive(true); return; }
      // A previous native startup is stuck. Retire it once before retrying; never loop starts.
      this.repairing = true;
      try { await controller.stopPiP(); if (!this.disposed) await controller.startPiP(); }
      finally { this.repairing = false; }
    }
    if (!this.disposed && await controller.isPiPActive()) this.setActive(true);
  }
  async stop(restore: boolean = true): Promise<void> {
    await this.starting?.catch((): void => {});
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
    await this.creating?.catch((): void => {}); await this.starting?.catch((): void => {});
    const controller = this.controller; this.controller = undefined;
    try { controller?.setAutoStartEnabled(false); if (this.active) await controller?.stopPiP(); }
    finally {
      controller?.off('stateChange'); controller?.off('controlEvent',this.controlEvent);
      this.surface?.setInPip(false);
      this.active = false; this.appliedAuto = undefined; this.commands = undefined; this.surface = undefined;
    }
  }
}
