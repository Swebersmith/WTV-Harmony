import { audio } from '@kit.AudioKit';
import { window } from '@kit.ArkUI';

export interface MediaVolume { level: number; min: number; max: number; }
export function volumeFromSwipe(start: number, min: number, max: number, offset: number, height: number): number {
  return Math.round(Math.max(min,Math.min(max,start-offset/Math.max(1,height*0.8)*(max-min))));
}
export function brightnessFromSwipe(start: number, offset: number, height: number): number {
  return Math.max(0.05,Math.min(1,start-offset/Math.max(1,height*0.8)));
}

// System volume is changed by the public AVVolumePanel component, only on user input.
// This service reads the media stream and follows hardware keys/output-device changes.
export class SystemMediaVolume {
  private manager?: audio.AudioVolumeManager;
  private changed?: (value: MediaVolume) => void;
  private listener: (event: audio.StreamVolumeEvent) => void = (): void => { this.refresh(); };
  open(changed: (value: MediaVolume) => void): boolean {
    this.close(); this.changed = changed;
    try {
      this.manager = audio.getAudioManager().getVolumeManager();
      this.manager.on('streamVolumeChange',audio.StreamUsage.STREAM_USAGE_MUSIC,this.listener);
      if (this.refresh()) return true;
      this.close(); return false;
    } catch { this.close(); return false; }
  }
  refresh(): boolean {
    if (!this.manager) return false;
    try {
      const usage = audio.StreamUsage.STREAM_USAGE_MUSIC;
      const value: MediaVolume = {level:this.manager.getVolumeByStream(usage),min:this.manager.getMinVolumeByStream(usage),max:this.manager.getMaxVolumeByStream(usage)};
      if (![value.level,value.min,value.max].every((n: number): boolean => Number.isFinite(n)) || value.max <= value.min) return false;
      this.changed?.(value); return true;
    } catch { return false; }
  }
  close(): void {
    try { this.manager?.off('streamVolumeChange',this.listener); } catch {}
    this.manager = undefined; this.changed = undefined;
  }
}

// Serialize across component instances, so a leaving player's restore runs before a new player reads the baseline.
let brightnessQueue: Promise<void> = Promise.resolve();
export class PlayerBrightness {
  private win?: window.Window;
  private original: number = -1;
  private revision: number = 0;
  private active: boolean = false;
  private ready: boolean = false;
  private timer: number = -1;
  private pending?: number;
  private failed: () => void = (): void => {};
  async open(win: window.Window, failed: () => void): Promise<number | undefined> {
    this.win = win; this.failed = failed; this.active = true; this.ready = false;
    const revision = ++this.revision;
    let baseline: number | undefined = undefined;
    brightnessQueue = brightnessQueue.then((): void => {
      if (!this.active || revision !== this.revision) return;
      const value = win.getWindowProperties().brightness;
      this.original = Number.isFinite(value) && value >= 0 && value <= 1 ? value : -1;
      baseline = this.original; this.ready = true;
    }).catch((): void => { if (revision === this.revision) this.failed(); });
    await brightnessQueue; return baseline;
  }
  set(value: number): boolean {
    if (!this.active || !this.ready || !Number.isFinite(value)) return false;
    this.pending = Math.max(0.05,Math.min(1,value));
    // Coalesce touch updates, rather than issuing one window request for every pointer sample.
    if (this.timer === -1) this.timer = setTimeout((): void => this.flush(),50);
    return true;
  }
  flush(): void {
    clearTimeout(this.timer); this.timer = -1;
    const value = this.pending, win = this.win, revision = this.revision;
    this.pending = undefined;
    if (value === undefined || !win || !this.active || !this.ready) return;
    brightnessQueue = brightnessQueue.then(async (): Promise<void> => {
      if (this.active && revision === this.revision) await win.setWindowBrightness(value);
    }).catch((): void => { if (revision === this.revision) this.failed(); });
  }
  followSystem(): boolean {
    if (!this.active || !this.ready) return false;
    this.pending = -1; this.flush(); return true;
  }
  close(): void {
    if (!this.active) return;
    this.active = false; ++this.revision; clearTimeout(this.timer); this.timer = -1; this.pending = undefined;
    const win = this.win, original = this.original, restore = this.ready;
    this.ready = false; this.win = undefined;
    if (win && restore) brightnessQueue = brightnessQueue.then((): Promise<void> => win.setWindowBrightness(original)).catch((): void => {});
  }
}
