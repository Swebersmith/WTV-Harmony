import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlaybackDiagnostics } from './PlaybackDiagnostics';

export async function playbackWantAgent(context: common.UIAbilityContext): Promise<WantAgent> {
  return wantAgent.getWantAgent({wants:[{bundleName:context.abilityInfo.bundleName,abilityName:context.abilityInfo.name,
    parameters:{'wtv.openPlayer':true}}],operationType:wantAgent.OperationType.START_ABILITY,
    requestCode:1700,wantAgentFlags:[wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]});
}

// Serialize acquisition/release, including a pause while acquisition is pending.
export class BackgroundPlayback {
  private context?: common.UIAbilityContext;
  private desired: boolean = false;
  private running: boolean = false;
  private taskId: number = -1;
  private stopping: boolean = false;
  private lost?: () => void;
  private canceled: (info: backgroundTaskManager.ContinuousTaskCancelInfo) => void = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (info.id === this.taskId) PlaybackDiagnostics.record(`background task canceled id=${info.id} reason=${info.reason} detail=${info.detailedReason} ownRelease=${this.stopping}`);
    if (!this.running || this.stopping || info.id !== this.taskId) return;
    this.running = false; this.taskId = -1; this.desired = false; this.lost?.();
  };
  private queue: Promise<void> = Promise.resolve();
  open(context: common.UIAbilityContext, lost?: () => void): void {
    this.context = context; this.lost = lost;
    try { backgroundTaskManager.off('continuousTaskCancel',this.canceled); } catch {}
    try { backgroundTaskManager.on('continuousTaskCancel',this.canceled); }
    catch (error) { PlaybackDiagnostics.record(`background cancel listener error=${(error as BusinessError).code}`); }
  }
  isRunning(): boolean { return this.running; }
  sync(required: boolean): Promise<void> {
    this.desired = required;
    const task = this.queue.then(async (): Promise<void> => {
      const context = this.context;
      if (!context) return;
      if (this.desired && !this.running) {
        const agent = await playbackWantAgent(context);
        if (!this.desired) return;
        const request = new backgroundTaskManager.ContinuousTaskRequest();
        // Official mapping: the AVSession playback subtype belongs to multimedia mode (12), not audio mode (2).
        request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_AV_PLAYBACK_AND_RECORD];
        request.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_AVSESSION_AUDIO_PLAYBACK];
        request.wantAgent = agent;
        PlaybackDiagnostics.record('background task request mode=12 submode=5');
        try {
          const result = await backgroundTaskManager.startBackgroundRunning(context,request);
          this.taskId = result.continuousTaskId ?? -1; this.running = true;
          PlaybackDiagnostics.record(`background task acquired id=${this.taskId}`);
        } catch (error) {
          const failure = error as BusinessError;
          PlaybackDiagnostics.record(`background task denied code=${failure.code} message=${failure.message}`);
          throw error as Error;
        }
      }
      if (!this.desired && this.running) {
        this.stopping = true;
        PlaybackDiagnostics.record(`background task release id=${this.taskId}`);
        try {
          if (this.taskId >= 0) await backgroundTaskManager.stopBackgroundRunning(context,this.taskId);
          else await backgroundTaskManager.stopBackgroundRunning(context);
          this.running = false; this.taskId = -1;
          PlaybackDiagnostics.record('background task released');
        } finally { this.stopping = false; }
      }
    });
    this.queue = task.catch((): void => {}); return task;
  }
  async close(): Promise<void> {
    await this.sync(false);
    try { backgroundTaskManager.off('continuousTaskCancel',this.canceled); } catch {}
    this.context = undefined; this.lost = undefined;
  }
}
