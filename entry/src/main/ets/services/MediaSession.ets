import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { systemDateTime } from '@kit.BasicServicesKit';

export class MediaSession {
  private session?: avSession.AVSession;
  async open(context: common.UIAbilityContext, play: () => void, pause: () => void,
    next: () => void, previous: () => void, seek: (seconds: number) => void): Promise<void> {
    this.session = await avSession.createAVSession(context,'WTV','video');
    this.session.on('play',play);
    this.session.on('pause',pause);
    this.session.on('playNext',next);
    this.session.on('playPrevious',previous);
    this.session.on('seek',(position: number): void => seek(position/1000));
    await this.session.activate();
  }
  async metadata(id: string, title: string, subtitle: string): Promise<void> {
    await this.session?.setAVMetadata({assetId:id,title,artist:subtitle});
  }
  async update(playing: boolean, seconds: number): Promise<void> {
    await this.session?.setAVPlaybackState({
      state:playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position:{elapsedTime:Math.floor(seconds*1000),updateTime:systemDateTime.getUptime(systemDateTime.TimeType.STARTUP)}
    });
  }
  async close(): Promise<void> { await this.session?.destroy(); this.session = undefined; }
}
