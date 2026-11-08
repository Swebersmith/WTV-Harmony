import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';

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
    if (!this.running || this.stopping || info.id !== this.taskId) return;
    this.running = false; this.taskId = -1; this.desired = false; this.lost?.();
  };
  private queue: Promise<void> = Promise.resolve();
  open(context: common.UIAbilityContext, lost?: () => void): void {
    this.context = context; this.lost = lost;
    try { backgroundTaskManager.off('continuousTaskCancel',this.canceled); backgroundTaskManager.on('continuousTaskCancel',this.canceled); } catch {}
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
        request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_AUDIO_PLAYBACK];
        request.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_AVSESSION_AUDIO_PLAYBACK];
        request.wantAgent = agent;
        const result = await backgroundTaskManager.startBackgroundRunning(context,request);
        this.taskId = result.continuousTaskId ?? -1; this.running = true;
      }
      if (!this.desired && this.running) {
        this.stopping = true;
        try {
          if (this.taskId >= 0) await backgroundTaskManager.stopBackgroundRunning(context,this.taskId);
          else await backgroundTaskManager.stopBackgroundRunning(context);
          this.running = false; this.taskId = -1;
        } finally { this.stopping = false; }
      }
    });
    this.queue = task.catch((): void => {}); return task;
  }
  async close(): Promise<void> {
    await this.sync(false);
    backgroundTaskManager.off('continuousTaskCancel',this.canceled);
    this.context = undefined; this.lost = undefined;
  }
}
