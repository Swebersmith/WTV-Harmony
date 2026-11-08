import { avSession } from '@kit.AVSessionKit';
import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { playbackWantAgent } from './BackgroundPlayback';
import { PlaybackDiagnostics } from './PlaybackDiagnostics';

export interface MediaCommands {
  play: () => void; pause: () => void; stop: () => void;
  next: () => void; previous: () => void; seek: (seconds: number) => void;
  skip: (seconds: number) => void; rate: (value: number) => void;
}

export interface MediaCastEvents {
  started: (device: string) => void;
  stopped: (seconds: number) => void;
  state: (playing: boolean) => void;
  position: (seconds: number) => void;
  error: (message: string) => void;
}

export class MediaSession {
  private session?: avSession.AVSession;
  private opening?: Promise<void>;
  private closing?: Promise<void>;
  private queue: Promise<void> = Promise.resolve();
  private revision: number = 0;
  private background: boolean = true;
  private configuredBackground?: boolean;
  private meta: avSession.AVMetadata = {assetId:'wtv',title:'WTV'};
  private lastUpdate: number = 0;
  private lastSeconds: number = 0;
  private lastState: string = '';
  private cast?: avSession.AVCastController;
  private casting: boolean = false;
  private castPrepared: boolean = false;
  private castDeviceName: string = '';
  private castUri: string = '';
  private castAssetId: string = '';
  private castTitle: string = '';
  private castSubtitle: string = '';
  private castDurationMs: number = 0;
  private castPositionMs: number = 0;
  private castEvents?: MediaCastEvents;
  private castOpening?: Promise<void>;
  isOpen(): boolean { return this.session !== undefined; }
  isCasting(): boolean { return this.casting; }
  setCastEvents(events: MediaCastEvents): void { this.castEvents = events; }
  // The media URL is what the receiving device will pull; keep it apart from the AVSession asset id.
  setCastMedia(uri: string, seconds: number, duration: number, assetId: string, title: string, subtitle: string): void {
    this.castUri = uri; this.castAssetId = assetId; this.castTitle = title; this.castSubtitle = subtitle;
    this.castDurationMs = Number.isFinite(duration) ? Math.max(0,Math.floor(duration*1000)) : 0;
    this.castPositionMs = Number.isFinite(seconds) ? Math.max(0,Math.floor(seconds*1000)) : 0;
    this.lastSeconds = this.castPositionMs/1000;
  }
  async open(context: common.UIAbilityContext, commands: MediaCommands): Promise<void> {
    await this.closing;
    if (this.session) return;
    if (this.opening) return this.opening;
    const revision = this.revision;
    this.opening = this.create(context,commands,revision);
    try { await this.opening; } finally { this.opening = undefined; }
  }
  private async create(context: common.UIAbilityContext, commands: MediaCommands, revision: number): Promise<void> {
    const session = await avSession.createAVSession(context,'WTV','video');
    try {
      session.on('play',(): void => { if (this.casting) this.castCommand({command:'play'}).catch((): void => {}); else commands.play(); });
      session.on('pause',(): void => { if (this.casting) this.castCommand({command:'pause'}).catch((): void => {}); else commands.pause(); });
      session.on('stop',(): void => {
        if (this.casting) this.stopCast().catch((): void => {});
        commands.stop();
      });
      session.on('playNext',(): void => { if (this.casting) this.castCommand({command:'playNext'}).catch((): void => {}); else commands.next(); });
      session.on('playPrevious',(): void => { if (this.casting) this.castCommand({command:'playPrevious'}).catch((): void => {}); else commands.previous(); });
      session.on('seek',(milliseconds: number): void => {
        PlaybackDiagnostics.record(`system seek ms=${milliseconds}`);
        if (!Number.isFinite(milliseconds)) return;
        if (this.casting) { this.castCommand({command:'seek',parameter:milliseconds}).catch((): void => {}); return; }
        commands.seek(Math.max(0,milliseconds/1000));
      });
      session.on('fastForward',(milliseconds?: number): void => {
        if (this.casting) { this.castCommand({command:'fastForward',parameter:this.castSkipSeconds(milliseconds)}).catch((): void => {}); return; }
        commands.skip(Number.isFinite(milliseconds) ? Math.max(0,milliseconds as number)/1000 : 10);
      });
      session.on('rewind',(milliseconds?: number): void => {
        if (this.casting) { this.castCommand({command:'rewind',parameter:this.castSkipSeconds(milliseconds)}).catch((): void => {}); return; }
        commands.skip(-(Number.isFinite(milliseconds) ? Math.max(0,milliseconds as number)/1000 : 10));
      });
      session.on('setSpeed',(speed: number): void => {
        if (this.casting) { this.castCommand({command:'setSpeed',parameter:this.castSpeed(speed)}).catch((): void => {}); return; }
        commands.rate(speed);
      });
      // Declare URL casting so the system picker only lists receivers that can pull a media URL.
      session.on('outputDeviceChange',this.outputDeviceChanged);
      await session.setLaunchAbility(await playbackWantAgent(context));
      await session.setSupportedPlaySpeeds([0.75,1,1.25,1.5,1.75,2]);
      const background = this.background;
      if (deviceInfo.sdkApiVersion >= 24) await session.setBackgroundPlayMode(background
        ? avSession.BackgroundPlayMode.ENABLE_BACKGROUND_PLAY : avSession.BackgroundPlayMode.DISABLE_BACKGROUND_PLAY);
      this.configuredBackground = background;
      await session.setAVMetadata(this.meta); await session.activate();
      try { await session.setExtras({requireAbilityList:['url-cast']}); }
      catch (error) { PlaybackDiagnostics.record(`cast capability rejected ${String(error)}`); }
      if (revision !== this.revision) { await session.destroy(); return; }
      this.session = session; this.lastState = ''; this.lastUpdate = 0;
      PlaybackDiagnostics.record('system AVSession active');
    } catch (error) {
      PlaybackDiagnostics.record(`system AVSession create failed ${String(error)}`);
      await session.destroy().catch((): void => {}); throw error as Error;
    }
  }
  private enqueue(task: (session: avSession.AVSession) => Promise<void>): Promise<void> {
    const revision = this.revision;
    const result = this.queue.then(async (): Promise<void> => {
      await this.opening;
      if (revision === this.revision && this.session) await task(this.session);
    });
    this.queue = result.catch((): void => {}); return result;
  }
  setBackground(enabled: boolean): Promise<void> {
    this.background = enabled;
    return this.enqueue(async (session: avSession.AVSession): Promise<void> => {
      if (this.configuredBackground === enabled) return;
      if (deviceInfo.sdkApiVersion >= 24) await session.setBackgroundPlayMode(enabled
        ? avSession.BackgroundPlayMode.ENABLE_BACKGROUND_PLAY : avSession.BackgroundPlayMode.DISABLE_BACKGROUND_PLAY);
      this.configuredBackground = enabled;
    });
  }
  metadata(id: string, title: string, subtitle: string, cover: string = '', duration: number = 0): Promise<void> {
    const filter = avSession.ProtocolType.TYPE_CAST_PLUS_STREAM | avSession.ProtocolType.TYPE_DLNA;
    const value: avSession.AVMetadata = {assetId:id,title:title || 'WTV',artist:subtitle,
      subtitle,duration:Math.max(0,Math.floor(duration*1000)),skipIntervals:avSession.SkipIntervals.SECONDS_10,filter};
    if (/^https?:\/\//i.test(cover)) value.mediaImage = cover;
    this.meta = value; this.lastState = '';
    return this.enqueue(async (session: avSession.AVSession): Promise<void> => {
      try { await session.setAVMetadata(value); }
      catch (error) {
        if (!value.mediaImage) throw error as Error;
        const fallback: avSession.AVMetadata = {assetId:value.assetId,title:value.title,artist:subtitle,subtitle,duration:value.duration,filter};
        await session.setAVMetadata(fallback);
        if (this.meta === value) this.meta = fallback;
      }
    });
  }
  update(playing: boolean, seconds: number, rate: number = 1, buffering: boolean = false, force: boolean = false): Promise<void> {
    const state = playing ? (buffering ? avSession.PlaybackState.PLAYBACK_STATE_BUFFERING : avSession.PlaybackState.PLAYBACK_STATE_PLAY)
      : avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    const key = `${state}|${rate}|${buffering}`, now = Date.now();
    const position = Number.isFinite(seconds) ? Math.max(0,seconds) : 0;
    this.castPositionMs = Math.floor(position*1000);
    if (!force && key === this.lastState && now-this.lastUpdate < 1000 && Math.abs(position-this.lastSeconds) < 2) return Promise.resolve();
    this.lastState = key; this.lastUpdate = now; this.lastSeconds = position;
    const value: avSession.AVPlaybackState = {state,speed:rate,
      position:{elapsedTime:Math.floor(position*1000),updateTime:now}};
    return this.enqueue(async (session: avSession.AVSession): Promise<void> => {
      try { await session.setAVPlaybackState(value); }
      catch (error) { PlaybackDiagnostics.record('system state rejected'); this.lastState = ''; throw error as Error; }
    });
  }
  castPlay(): Promise<void> { return this.castCommand({command:'play'}); }
  castPause(): Promise<void> { return this.castCommand({command:'pause'}); }
  castSeek(seconds: number): Promise<void> {
    return this.castCommand({command:'seek',parameter:Math.max(0,Math.round(seconds*1000))});
  }
  castRate(rate: number): Promise<void> { return this.castCommand({command:'setSpeed',parameter:this.castSpeed(rate)}); }
  async stopCast(notify: boolean = true): Promise<void> {
    const wasCasting = this.casting, seconds = this.castPositionMs/1000, device = this.castDeviceName;
    await this.releaseCast();
    this.casting = false; this.castPrepared = false; this.castDeviceName = '';
    try { await this.session?.stopCasting(); } catch {}
    if (wasCasting) PlaybackDiagnostics.record(`cast stopped device=${device}`);
    if (notify && wasCasting) this.castEvents?.stopped(seconds);
  }
  private castCommand(command: avSession.AVCastControlCommand): Promise<void> {
    const controller = this.cast;
    if (!controller) return Promise.reject(new Error('投屏尚未连接'));
    return controller.sendControlCommand(command);
  }
  private castSpeed(rate: number): media.PlaybackSpeed {
    if (rate === 0.75) return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    if (rate === 1.25) return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    if (rate === 1.5) return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    if (rate === 1.75) return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    if (rate === 2) return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  }
  private castSkipSeconds(milliseconds?: number): number {
    return Number.isFinite(milliseconds) ? Math.max(1,Math.round((milliseconds as number)/1000)) : 10;
  }
  private outputDeviceChanged: (state: avSession.ConnectionState, device: avSession.OutputDeviceInfo) => void =
    (state: avSession.ConnectionState, device: avSession.OutputDeviceInfo): void => {
      const info = device.devices && device.devices.length ? device.devices[0] : undefined;
      if (!info) return;
      PlaybackDiagnostics.record(`cast output state=${state} category=${info.castCategory} name=${info.deviceName}`);
      if (info.castCategory === avSession.AVCastCategory.CATEGORY_REMOTE) {
        if (state === avSession.ConnectionState.STATE_CONNECTED) this.connectCast(info.deviceName).catch((): void => {});
        else if (state === avSession.ConnectionState.STATE_DISCONNECTED && (this.casting || this.cast)) this.stopCast().catch((): void => {});
      } else if (info.castCategory === avSession.AVCastCategory.CATEGORY_LOCAL && (this.casting || this.cast)) {
        this.stopCast().catch((): void => {});
      }
    };
  private connectCast(device: string): Promise<void> {
    if (this.casting) { this.castDeviceName = device; return Promise.resolve(); }
    if (this.castOpening) return this.castOpening;
    this.castOpening = this.startCast(device).finally((): void => { this.castOpening = undefined; });
    return this.castOpening;
  }
  private async startCast(device: string): Promise<void> {
    const session = this.session;
    if (!session) return;
    if (!this.castUri) { this.castEvents?.error('请先开始播放，再连接投屏设备'); return; }
    try {
      const controller = await session.getAVCastController();
      this.cast = controller;
      controller.on('playbackStateChange','all',this.castPlaybackChanged);
      controller.on('error',this.castError);
      const item = this.castItem();
      if (!this.castPrepared) { await controller.prepare(item); this.castPrepared = true; }
      await controller.start(item);
      this.casting = true; this.castDeviceName = device;
      PlaybackDiagnostics.record(`cast started device=${device}`);
      this.castEvents?.started(device);
    } catch (error) {
      PlaybackDiagnostics.record(`cast start failed ${String(error)}`);
      await this.releaseCast();
      this.casting = false; this.castPrepared = false;
      try { await session.stopCasting(); } catch {}
      this.castEvents?.error('投屏连接失败，请重试');
    }
  }
  private castItem(): avSession.AVQueueItem {
    const description: avSession.AVMediaDescription = {
      assetId:this.castAssetId || this.meta.assetId,
      title:this.castTitle || this.meta.title,
      subtitle:this.castSubtitle || this.meta.subtitle,
      mediaUri:this.castUri,
      mediaType:'VIDEO',
      duration:this.castDurationMs > 0 ? this.castDurationMs : (this.meta.duration || 0),
      startPosition:Math.max(0,Math.floor(this.lastSeconds*1000))
    };
    return {itemId:0,description};
  }
  private castPlaybackChanged: (state: avSession.AVPlaybackState) => void = (state: avSession.AVPlaybackState): void => {
    if (state.position && Number.isFinite(state.position.elapsedTime)) {
      const seconds = state.position.elapsedTime/1000;
      this.castPositionMs = state.position.elapsedTime; this.lastSeconds = seconds;
      this.castEvents?.position(seconds);
    }
    if (state.state !== undefined) this.castEvents?.state(state.state === avSession.PlaybackState.PLAYBACK_STATE_PLAY);
  };
  private castError: (error: BusinessError) => void = (_error: BusinessError): void => {
    PlaybackDiagnostics.record('cast controller error');
    this.castEvents?.error('投屏连接中断');
    this.stopCast().catch((): void => {});
  };
  private async releaseCast(): Promise<void> {
    const controller = this.cast; this.cast = undefined;
    if (!controller) return;
    try { controller.off('playbackStateChange'); controller.off('error'); } catch {}
    try { await controller.release(); } catch {}
  }
  async close(): Promise<void> {
    if (this.closing) return this.closing;
    this.closing = this.destroy();
    try { await this.closing; } finally { this.closing = undefined; }
  }
  private async destroy(): Promise<void> {
    ++this.revision; const session = this.session; this.session = undefined;
    try { session?.off('outputDeviceChange',this.outputDeviceChanged); } catch {}
    await this.stopCast(false);
    await this.opening?.catch((): void => {}); await this.queue;
    this.lastState = ''; this.lastUpdate = 0; this.configuredBackground = undefined;
    await session?.destroy();
  }
}
