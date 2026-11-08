import { Player, PlayerConfig, Media, MpvLogLevel, EventObserver, MpvEvent } from '@mpv-ohos/mpv-arkts';

interface SourceRequest { url: string; hls: boolean; resume: number; autoplay: boolean; }
interface FileEnd { error: number; entryId: number; }
export interface PlaybackEvents {
  prepared: (duration: number) => void;
  time: (seconds: number) => void;
  playing: (value: boolean) => void;
  buffering: (value: boolean) => void;
  ended: () => void;
  failed: (code: number) => void;
}
export const NATIVE_RATES: number[] = [0.75,1,1.25,1.5,1.75,2];

// Native OHOS libmpv, FFmpeg and OHCodec. One core owns one surface at a time.
// A load is accepted only after FILE_LOADED reports the currently requested path.
export class NativePlayback extends XComponentController implements EventObserver {
  private player?: Player;
  private surface: string = '';
  private request?: SourceRequest;
  private timeout: number = -1;
  private revision: number = 0;
  private loaded: boolean = false;
  private failed: boolean = false;
  private completed: boolean = false;
  private current: number = 0;
  private desiredRate: number = 1;
  private desiredVolume: number = 1;
  private events?: PlaybackEvents;
  getRate(): number { return this.desiredRate; }
  getVolume(): number { return this.desiredVolume; }
  listen(events: PlaybackEvents): void { this.events = events; }
  onSurfaceCreated(surface: string): void { this.attach(surface); }
  onSurfaceChanged(_surface: string, rect: SurfaceRect): void { this.resize(rect.surfaceWidth,rect.surfaceHeight); }
  onSurfaceDestroyed(surface: string): void { if (surface === this.surface) this.detach(); }
  attach(surface: string): void {
    if (this.surface === surface && this.player) return;
    if (this.player) this.detach();
    this.surface = surface;
    try {
      this.player = new Player(new PlayerConfig({vo:'gpu',gpuContext:'ohos',hwdec:true,osc:false,osd:false,logLevel:MpvLogLevel.Error}));
      const p = this.player;
      p.native.addEventObserver(this);
      p.native.setProperty('demuxer-max-bytes','64MiB');
      p.native.setProperty('demuxer-max-back-bytes','16MiB');
      p.native.setProperty('network-timeout',15);
      p.onSurfaceCreated(surface);
      p.stream.position.listen((seconds: number): void => {
        if (!this.accepts(p) || !Number.isFinite(seconds) || seconds < 0) return;
        this.current = seconds; this.events?.time(seconds);
      });
      p.stream.duration.listen((seconds: number): void => {
        if (this.accepts(p) && Number.isFinite(seconds) && seconds > 0) this.events?.prepared(seconds);
      });
      p.stream.playing.listen((value: boolean): void => {
        if (this.accepts(p)) this.events?.playing(value);
      });
      p.stream.buffering.listen((value: boolean): void => {
        if (this.accepts(p)) this.events?.buffering(value);
      });
      p.stream.eof.listen((value: boolean): void => {
        if (!value || !this.accepts(p) || this.completed) return;
        this.completed = true; this.events?.playing(false); this.events?.buffering(false); this.events?.ended();
      });
      if (this.request) this.open();
    } catch { this.fail(-1); }
  }
  resize(width: number, height: number): void {
    try { this.player?.native.setProperty('ohos-surface-size',`${Math.round(width)}x${Math.round(height)}`); } catch {}
  }
  private accepts(player: Player): boolean {
    if (player !== this.player || !this.loaded || this.failed || !this.request) return false;
    try { return player.native.getPropertyString('path') === this.request.url; } catch { return false; }
  }
  detach(): void {
    if (this.request) { this.request.resume = this.current; this.request.autoplay = false; }
    ++this.revision; clearTimeout(this.timeout); this.loaded = false; this.surface = '';
    const old = this.player; this.player = undefined;
    if (old) {
      try { old.native.removeEventObserver(this); old.onSurfaceDestroyed(''); old.destroy(); } catch {}
    }
  }
  clear(): void {
    ++this.revision; clearTimeout(this.timeout); this.request = undefined; this.loaded = false; this.failed = false; this.current = 0;
    try { this.player?.stop(); } catch {}
  }
  load(url: string, hls: boolean, resume: number = 0, autoplay: boolean = true): void {
    this.request = {url,hls,resume,autoplay}; this.current = resume;
    ++this.revision; this.loaded = false; this.failed = false; this.completed = false; clearTimeout(this.timeout);
    if (this.player && this.surface) this.open();
  }
  private open(): void {
    if (!this.player || !this.request) return;
    const request = this.request, revision = this.revision;
    this.events?.buffering(true);
    this.timeout = setTimeout((): void => { if (revision === this.revision) this.fail(-2); },30000);
    try {
      this.player.open(new Media(request.url,{start:request.resume,httpHeaders:new Map<string,string>([['User-Agent','WTV-Harmony/1.5.1']])}),request.autoplay);
      this.player.setSpeed(this.desiredRate); this.player.setVolume(this.desiredVolume*100);
    } catch { this.fail(-1); }
  }
  onPropertyChanged(_property: string, _value?: string | number | boolean): void {}
  onEvent(id: number, _name: string, detail?: string): void {
    if (!this.player || !this.request || this.failed) return;
    if (id === MpvEvent.MPV_EVENT_FILE_LOADED) {
      try { if (this.player.native.getPropertyString('path') !== this.request.url) return; } catch { return; }
      clearTimeout(this.timeout); this.loaded = true;
      this.events?.prepared(Math.max(0,this.player.state.duration)); this.events?.buffering(false);
      this.player.setSpeed(this.desiredRate); this.player.setVolume(this.desiredVolume*100);
      if (this.request.autoplay) this.player.play(); else this.player.pause();
      this.events?.playing(this.request.autoplay);
    } else if (id === MpvEvent.MPV_EVENT_END_FILE && detail) {
      // Normal stop/EOF is not a decoding failure. Ignore errors for a replaced playlist item.
      try {
        const end = JSON.parse(detail) as FileEnd;
        if (Number.isFinite(end.error) && end.error < 0 && Number.isFinite(end.entryId) &&
          end.entryId === this.player.native.getProperty('playlist/0/id')) this.fail(end.error);
      } catch {}
    }
  }
  private fail(code: number): void {
    if (this.failed) return;
    this.failed = true; this.loaded = false; clearTimeout(this.timeout);
    try { this.player?.stop(); } catch {}
    this.events?.buffering(false); this.events?.playing(false); this.events?.failed(code);
  }
  start(): void {
    if (this.request) this.request.autoplay = true;
    this.completed = false;
    try {
      if (this.loaded && this.player) {
        this.player.play(); this.events?.playing(true);
      }
    } catch { this.fail(-1); }
  }
  pause(): void {
    if (this.request) this.request.autoplay = false;
    try { this.player?.pause(); this.events?.playing(false); } catch {}
  }
  setCurrentTime(seconds: number): void {
    if (!this.loaded || !Number.isFinite(seconds)) return;
    try { this.player?.seek(Math.max(0,seconds)); } catch {}
  }
  setRate(rate: number): void {
    if (!NATIVE_RATES.includes(rate)) return;
    this.desiredRate = rate;
    try { this.player?.setSpeed(rate); } catch {}
  }
  setVolume(volume: number): void {
    this.desiredVolume = Math.max(0,Math.min(1,volume));
    try { this.player?.setVolume(this.desiredVolume*100); } catch {}
  }
}
