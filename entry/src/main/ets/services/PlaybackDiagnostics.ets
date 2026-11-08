import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';

export class PlaybackDiagnostics {
  private static entries: string[] = [];
  static record(event: string): void {
    const line = `${new Date().toISOString()} ${event}`;
    PlaybackDiagnostics.entries.push(line);
    if (PlaybackDiagnostics.entries.length > 100) PlaybackDiagnostics.entries.shift();
    hilog.info(0x0000,'WTVPlayback','%{public}s',event);
  }
  static report(): string {
    return `WTV 1.7.2 / API ${deviceInfo.sdkApiVersion}\n${PlaybackDiagnostics.entries.join('\n')}`;
  }
}
