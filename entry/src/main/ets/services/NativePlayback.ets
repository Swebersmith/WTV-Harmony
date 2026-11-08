import { Player, PlayerConfig, Media, MpvLogLevel, EventObserver, LogObserver, MpvEvent } from '@mpv-ohos/mpv-arkts';
import { PlaybackDiagnostics } from './PlaybackDiagnostics';

interface SourceRequest { url: string; hls: boolean; resume: number; autoplay: boolean; }
interface FileEnd { error: number; entryId: number; }
export interface PlaybackEvents {
  rate?: (value: number) => void;
  seekFailed?: () => void;
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
export class NativePlayback extends XComponentController implements EventObserver, LogObserver {
  private player?: Player;
  private surface: string = '';
  private seekTarget?: number;
  private seekTimer: number = -1;
  private coreBuffering: boolean = false;
  private request?: SourceRequest;
  private timeout: number = -1;
  private revision: number = 0;
  private loaded: boolean = false;
  private failed: boolean = false;
  private completed: boolean = false;
  private current: number = 0;
  private desiredRate: number = 1;
  private desiredVolume: number = 1;
  private keepAlive: boolean = false;
  private audioOnly: boolean = false;
  private audioOnlySeek: boolean = false;
  private events?: PlaybackEvents;
  getRate(): number { return this.desiredRate; }
  getVolume(): number { return this.desiredVolume; }
  position(): number {
    try {
      const value = this.player?.state.position;
      if (typeof value === 'number' && Number.isFinite(value) && value >= 0) return value;
    } catch {}
    return this.current;
  }
  listen(events: PlaybackEvents): void { this.events = events; }
  // The typeNode bridge can invoke these functions with its own receiver. Capture our playback instance.
  onSurfaceCreated: (surface: string) => void = (surface: string): void => {
    PlaybackDiagnostics.record(`surface created id=${surface}`); this.attach(surface);
  };
  onSurfaceChanged: (surface: string, rect: SurfaceRect) => void = (surface: string, rect: SurfaceRect): void => {
    if (surface === this.surface) this.resizeSurface(rect.surfaceWidth,rect.surfaceHeight);
  };
  onSurfaceDestroyed: (surface: string) => void = (surface: string): void => {
    PlaybackDiagnostics.record(`surface destroyed id=${surface}`);
    if (surface !== this.surface) return;
    if (this.keepAlive && this.player && this.request) {
      this.surface = '';
      try { this.player.native.setProperty('vid','no'); this.player.onSurfaceDestroyed(''); } catch {}
    } else this.detach();
  };
  setKeepAlive(value: boolean): void { this.keepAlive = value; }
  isRetained(): boolean { return this.keepAlive; }
  setAudioOnly(value: boolean): void {
    if (this.audioOnly === value) return;
    const wasAudioOnly = this.audioOnly;
    this.audioOnly = value;
    this.applyVideoMode();
    // Seeking while the video track is disabled can leave the decoder on its old frame.
    // Re-apply the target once video is enabled so picture and audio resume together.
    if (wasAudioOnly && !value && this.audioOnlySeek) {
      this.audioOnlySeek = false;
      const target = this.seekTarget !== undefined ? this.seekTarget : this.current;
      PlaybackDiagnostics.record(`video resync after audio-only seek=${target.toFixed(3)}`);
      this.setCurrentTime(target);
    }
  }
  private applyVideoMode(): void {
    try { this.player?.native.setProperty('vid',this.audioOnly || !this.surface ? 'no' : 'auto'); } catch {}
  }
  getVideoSize(): number[] {
    try {
      const width = this.player?.native.getProperty('width'), height = this.player?.native.getProperty('height');
      if (typeof width === 'number' && typeof height === 'number' && width > 0 && height > 0) return [width,height];
    } catch {}
    return [1920,1080];
  }
  attach(surface: string): void {
    PlaybackDiagnostics.record(`MPV attach begin surface=${surface} retained=${this.keepAlive}`);
    if (this.surface === surface && this.player) return;
    if (this.player && this.keepAlive && this.request && !this.failed) {
      this.surface = surface;
      try {
        // OHOS creates its EGL surface when video output starts. Retire that output before changing wid.
        this.player.native.setProperty('vid','no');
        this.player.onSurfaceCreated(surface);
        this.applyVideoMode();
      } catch { this.fail(-1); }
      return;
    }
    if (this.player) this.detach();
    this.surface = surface;
    try {
      PlaybackDiagnostics.record('MPV constructor begin');
      this.player = new Player(new PlayerConfig({vo:'gpu',gpuContext:'ohos',hwdec:true,osc:false,osd:false,logLevel:MpvLogLevel.Error}));
      PlaybackDiagnostics.record('MPV constructor complete');
      const p = this.player;
      p.native.addEventObserver(this); p.native.addLogObserver(this);
      p.native.setProperty('demuxer-max-bytes','64MiB');
      p.native.setProperty('demuxer-max-back-bytes','16MiB');
      p.native.setProperty('network-timeout',15);
      PlaybackDiagnostics.record('MPV native surface bind begin');
      p.onSurfaceCreated(surface);
      PlaybackDiagnostics.record('MPV native surface bind complete');
      this.applyVideoMode();
      p.stream.position.listen((seconds: number): void => {
        if (!this.accepts(p) || !Number.isFinite(seconds) || seconds < 0) return;
        if (this.seekTarget !== undefined) {
          if (Math.abs(seconds-this.seekTarget) > 1.5) return;
          PlaybackDiagnostics.record(`seek confirmed ${seconds.toFixed(3)}`);
          this.clearSeek(); this.current = seconds; this.events?.time(seconds); this.events?.buffering(this.coreBuffering); return;
        }
        this.current = seconds; this.events?.time(seconds);
      });
      p.stream.duration.listen((seconds: number): void => {
        if (this.accepts(p) && Number.isFinite(seconds) && seconds > 0) this.events?.prepared(seconds);
      });
      p.stream.playing.listen((value: boolean): void => {
        if (this.accepts(p)) this.events?.playing(value);
      });
      p.stream.buffering.listen((value: boolean): void => {
        if (this.accepts(p)) { this.coreBuffering = value; if (value || this.seekTarget === undefined) this.events?.buffering(value); }
      });
      p.stream.eof.listen((value: boolean): void => {
        if (!value || !this.accepts(p) || this.completed) return;
        this.completed = true; this.events?.playing(false); this.events?.buffering(false); this.events?.ended();
      });
      if (this.request) this.open();
    } catch (error) { PlaybackDiagnostics.record(`MPV attach exception ${String(error)}`); this.fail(-1); }
  }
  resize(width: number, height: number): void {
    this.resizeSurface(width,height);
  }
  private resizeSurface(width: number, height: number): void {
    if (width <= 0 || height <= 0) return;
    try { this.player?.native.setProperty('ohos-surface-size',`${Math.round(width)}x${Math.round(height)}`); } catch {}
  }
  private accepts(player: Player): boolean {
    if (player !== this.player || !this.loaded || this.failed || !this.request) return false;
    try { return player.native.getPropertyString('path') === this.request.url; } catch { return false; }
  }
  detach(): void {
    this.clearSeek();
    if (this.request) { this.request.resume = this.current; this.request.autoplay = false; }
    ++this.revision; clearTimeout(this.timeout); this.loaded = false; this.surface = '';
    const old = this.player; this.player = undefined;
    if (old) {
      try { old.native.removeEventObserver(this); old.native.removeLogObserver(this); old.onSurfaceDestroyed(''); old.destroy(); } catch {}
    }
  }
  clear(): void {
    this.clearSeek(); this.coreBuffering = false;
    ++this.revision; clearTimeout(this.timeout); this.request = undefined; this.loaded = false; this.failed = false; this.current = 0;
    try { this.player?.stop(); } catch {}
  }
  load(url: string, hls: boolean, resume: number = 0, autoplay: boolean = true): void {
    PlaybackDiagnostics.record(`media load hls=${hls} resume=${resume} autoplay=${autoplay}`);
    this.clearSeek(); this.coreBuffering = false;
    this.request = {url,hls,resume,autoplay}; this.current = resume;
    ++this.revision; this.loaded = false; this.failed = false; this.completed = false; clearTimeout(this.timeout);
    if (this.player && (this.surface || this.keepAlive)) this.open();
  }
  private open(): void {
    if (!this.player || !this.request) return;
    const request = this.request, revision = this.revision;
    this.events?.buffering(true);
    this.timeout = setTimeout((): void => { if (revision === this.revision) this.fail(-2); },30000);
    try {
      PlaybackDiagnostics.record('MPV open begin');
      this.player.open(new Media(request.url,{start:request.resume,httpHeaders:new Map<string,string>([['User-Agent','WTV-Harmony/1.7.6']])}),request.autoplay);
      PlaybackDiagnostics.record('MPV open returned');
      this.player.setSpeed(this.desiredRate); this.player.setVolume(this.desiredVolume*100);
    } catch { this.fail(-1); }
  }
  onPropertyChanged(_property: string, _value?: string | number | boolean): void {}
  onLogMessage(prefix: string, level: string, message: string): void {
    if (level === 'error' || level === 'fatal') PlaybackDiagnostics.record(`MPV ${level} ${prefix}: ${message}`);
  }
  onEvent(id: number, _name: string, detail?: string): void {
    if (!this.player || !this.request || this.failed) return;
    if (id === MpvEvent.MPV_EVENT_FILE_LOADED) {
      PlaybackDiagnostics.record('MPV file loaded event');
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
    PlaybackDiagnostics.record(`MPV failed code=${code}`);
    if (this.failed) return;
    this.clearSeek();
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
  private clearSeek(): void { clearTimeout(this.seekTimer); this.seekTimer = -1; this.seekTarget = undefined; }
  setCurrentTime(seconds: number): boolean {
    const player = this.player;
    if (!this.loaded || !player || !Number.isFinite(seconds)) return false;
    const duration = player.state.duration;
    const target = Math.max(0,duration > 0 ? Math.min(duration-0.2,seconds) : seconds);
    this.clearSeek(); this.seekTarget = target;
    try {
      const result = player.native.command(['seek',target.toFixed(3),'absolute+exact']);
      PlaybackDiagnostics.record(`seek target=${target.toFixed(3)} result=${result}`);
      if (result < 0) { this.clearSeek(); this.events?.seekFailed?.(); return false; }
      if (this.audioOnly) this.audioOnlySeek = true;
      player.state.eof = false; player.stream.eof.add(false); this.completed = false;
      this.current = target; this.events?.buffering(true); this.events?.time(target);
      this.seekTimer = setTimeout((): void => {
        if (!this.accepts(player) || this.seekTarget !== target) return;
        this.clearSeek();
        const actual = player.state.position;
        PlaybackDiagnostics.record(`seek timeout actual=${actual}`);
        if (Number.isFinite(actual) && actual >= 0) { this.current = actual; this.events?.time(actual); }
        this.events?.buffering(this.coreBuffering); this.events?.seekFailed?.();
      },10000);
      return true;
    } catch { this.clearSeek(); this.events?.seekFailed?.(); return false; }
  }
  setRate(rate: number): void {
    if (!NATIVE_RATES.includes(rate)) return;
    this.desiredRate = rate;
    try { this.player?.setSpeed(rate); this.events?.rate?.(rate); } catch {}
  }
  setVolume(volume: number): void {
    this.desiredVolume = Math.max(0,Math.min(1,volume));
    try { this.player?.setVolume(this.desiredVolume*100); } catch {}
  }
}
