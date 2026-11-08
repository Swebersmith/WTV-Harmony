import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { systemDateTime, deviceInfo } from '@kit.BasicServicesKit';
import { playbackWantAgent } from './BackgroundPlayback';

export interface MediaCommands {
  play: () => void; pause: () => void; stop: () => void;
  next: () => void; previous: () => void; seek: (seconds: number) => void;
  skip: (seconds: number) => void; rate: (value: number) => void;
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
  isOpen(): boolean { return this.session !== undefined; }
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
      session.on('play',commands.play); session.on('pause',commands.pause); session.on('stop',commands.stop);
      session.on('playNext',commands.next); session.on('playPrevious',commands.previous);
      session.on('seek',(milliseconds: number): void => { if (Number.isFinite(milliseconds)) commands.seek(Math.max(0,milliseconds/1000)); });
      session.on('fastForward',(milliseconds?: number): void => commands.skip(Number.isFinite(milliseconds) ? Math.max(0,milliseconds!)/1000 : 10));
      session.on('rewind',(milliseconds?: number): void => commands.skip(-(Number.isFinite(milliseconds) ? Math.max(0,milliseconds!)/1000 : 10)));
      session.on('setSpeed',(speed: number): void => commands.rate(speed));
      await session.setLaunchAbility(await playbackWantAgent(context));
      await session.setSupportedPlaySpeeds([0.75,1,1.25,1.5,1.75,2]);
      const background = this.background;
      if (deviceInfo.sdkApiVersion >= 24) await session.setBackgroundPlayMode(background
        ? avSession.BackgroundPlayMode.ENABLE_BACKGROUND_PLAY : avSession.BackgroundPlayMode.DISABLE_BACKGROUND_PLAY);
      this.configuredBackground = background;
      await session.setAVMetadata(this.meta); await session.activate();
      if (revision !== this.revision) { await session.destroy(); return; }
      this.session = session; this.lastState = ''; this.lastUpdate = 0;
    } catch (error) { await session.destroy().catch((): void => {}); throw error as Error; }
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
    const value: avSession.AVMetadata = {assetId:id,title:title || 'WTV',artist:subtitle,
      subtitle,duration:Math.max(0,Math.floor(duration*1000)),skipIntervals:avSession.SkipIntervals.SECONDS_10};
    if (/^https?:\/\//i.test(cover)) value.mediaImage = cover;
    this.meta = value; this.lastState = '';
    return this.enqueue(async (session: avSession.AVSession): Promise<void> => {
      try { await session.setAVMetadata(value); }
      catch (error) {
        if (!value.mediaImage) throw error as Error;
        const fallback: avSession.AVMetadata = {assetId:value.assetId,title:value.title,artist:subtitle,subtitle,duration:value.duration};
        await session.setAVMetadata(fallback);
        if (this.meta === value) this.meta = fallback;
      }
    });
  }
  update(playing: boolean, seconds: number, rate: number = 1, buffering: boolean = false): Promise<void> {
    const state = playing ? (buffering ? avSession.PlaybackState.PLAYBACK_STATE_BUFFERING : avSession.PlaybackState.PLAYBACK_STATE_PLAY)
      : avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    const key = `${state}|${rate}|${buffering}`, now = Date.now();
    const position = Number.isFinite(seconds) ? Math.max(0,seconds) : 0;
    if (key === this.lastState && now-this.lastUpdate < 1000 && Math.abs(position-this.lastSeconds) < 2) return Promise.resolve();
    this.lastState = key; this.lastUpdate = now; this.lastSeconds = position;
    const value: avSession.AVPlaybackState = {state,speed:rate,
      position:{elapsedTime:Math.floor(position*1000),updateTime:systemDateTime.getUptime(systemDateTime.TimeType.STARTUP)}};
    return this.enqueue((session: avSession.AVSession): Promise<void> => session.setAVPlaybackState(value));
  }
  async close(): Promise<void> {
    if (this.closing) return this.closing;
    this.closing = this.destroy();
    try { await this.closing; } finally { this.closing = undefined; }
  }
  private async destroy(): Promise<void> {
    ++this.revision; const session = this.session; this.session = undefined;
    await this.opening?.catch((): void => {}); await this.queue;
    this.lastState = ''; this.lastUpdate = 0; this.configuredBackground = undefined;
    await session?.destroy();
  }
}
