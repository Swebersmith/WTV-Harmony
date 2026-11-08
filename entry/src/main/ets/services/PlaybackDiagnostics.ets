import { hilog, hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common, AbilityConstant } from '@kit.AbilityKit';

export class PlaybackDiagnostics {
  private static entries: string[] = [];
  private static directory: string = '';
  private static storageError: string = '';
  private static watcher?: hiAppEvent.Watcher;
  static redact(value: string): string {
    return value.replace(/https?:\/\/[^\s"'<>]+/gi,'[链接已隐藏]')
      .replace(/(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,}\r\n]+/gi,'$1[已隐藏]')
      .replace(/((?:password|token|api[_-]?key|secret)\s*["']?\s*[:=]\s*["']?)[^\s,"'}]+/gi,'$1[已隐藏]');
  }
  static start(context: common.UIAbilityContext, launch: AbilityConstant.LaunchParam): void {
    if (PlaybackDiagnostics.directory) return;
    PlaybackDiagnostics.directory = `${context.filesDir}/diagnostics`;
    try {
      if (!fs.accessSync(PlaybackDiagnostics.directory)) fs.mkdirSync(PlaybackDiagnostics.directory);
      const current = `${PlaybackDiagnostics.directory}/current.log`;
      if (fs.accessSync(current) && fs.statSync(current).size > 0) fs.renameSync(current,`${PlaybackDiagnostics.directory}/previous.log`);
    } catch (error) { PlaybackDiagnostics.storageError = `日志文件初始化失败，当前仅保留内存记录：${String(error)}`; }
    PlaybackDiagnostics.record(`session start WTV=1.7.3 API=${deviceInfo.sdkApiVersion}`);
    PlaybackDiagnostics.record(`last exit reason=${launch.lastExitReason} message=${launch.lastExitMessage || '无'} detail=${JSON.stringify(launch.lastExitDetailInfo || {})}`);
    PlaybackDiagnostics.watcher = {name:'WTVFaultWatcher',appEventFilters:[{
      domain:hiAppEvent.domain.OS,names:[hiAppEvent.event.APP_CRASH,hiAppEvent.event.APP_FREEZE]
    }],onReceive:(_domain: string, groups: hiAppEvent.AppEventGroup[]): void => {
      for (const group of groups) for (const event of group.appEventInfos) PlaybackDiagnostics.receiveFault(event);
    }};
    try {
      const holder = hiAppEvent.addWatcher(PlaybackDiagnostics.watcher);
      PlaybackDiagnostics.record(holder ? 'system crash watcher ready' : 'system crash watcher unavailable');
    } catch { PlaybackDiagnostics.record('system crash watcher registration failed'); }
  }
  private static receiveFault(event: hiAppEvent.AppEventInfo): void {
    try {
      let detail = `${new Date().toISOString()} ${event.name}\n${JSON.stringify(event.params)}\n`;
      const paths: string[] = event.params['external_log'] as string[];
      if (Array.isArray(paths)) {
        for (const path of paths) {
          if (typeof path !== 'string' || !path.startsWith('/data/storage/el2/log/hiappevent/') ||
            path.includes('..') || path.includes('\\')) continue;
          try {
            detail += `\n--- 系统故障日志 ---\n${fs.readTextSync(path,{length:131072})}\n`;
          } catch { detail += '\n系统故障文件暂不可读，保留事件摘要。\n'; }
          if (detail.length >= 131072) break;
        }
      }
      detail = PlaybackDiagnostics.redact(detail).slice(0,131072);
      const file = `${PlaybackDiagnostics.directory}/fault.log`;
      if (fs.accessSync(file)) fs.renameSync(file,`${PlaybackDiagnostics.directory}/fault-previous.log`);
      PlaybackDiagnostics.write(file,detail,false);
      PlaybackDiagnostics.record(`system fault saved: ${event.name}`);
    } catch { PlaybackDiagnostics.record(`system fault capture failed: ${event.name}`); }
  }
  private static write(path: string, content: string, append: boolean): void {
    const file = fs.openSync(path,fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | (append ? fs.OpenMode.APPEND : fs.OpenMode.TRUNC));
    try { fs.writeSync(file.fd,content); } finally { fs.closeSync(file); }
  }
  static record(event: string): void {
    const safe = PlaybackDiagnostics.redact(event).slice(0,4096);
    const line = `${new Date().toISOString()} ${safe}`;
    PlaybackDiagnostics.entries.push(line);
    if (PlaybackDiagnostics.entries.length > 100) PlaybackDiagnostics.entries.shift();
    try { hilog.info(0x0000,'WTVPlayback','%{public}s',safe); } catch {}
    if (!PlaybackDiagnostics.directory) return;
    try {
      const file = `${PlaybackDiagnostics.directory}/current.log`;
      if (fs.accessSync(file) && fs.statSync(file).size >= 65536) fs.renameSync(file,`${PlaybackDiagnostics.directory}/previous.log`);
      PlaybackDiagnostics.write(file,`${line}\n`,true);
    } catch (error) { PlaybackDiagnostics.storageError = `日志文件写入失败，部分事件仅保留在内存中：${String(error)}`; }
  }
  static report(): string {
    let report = `WTV 1.7.3 / API ${deviceInfo.sdkApiVersion}\n导出时间：${new Date().toISOString()}\n${PlaybackDiagnostics.storageError}\n`;
    for (const name of ['fault.log','fault-previous.log','previous.log','current.log']) {
      try {
        const path = `${PlaybackDiagnostics.directory}/${name}`;
        if (PlaybackDiagnostics.directory && fs.accessSync(path)) report += `\n===== ${name} =====\n${fs.readTextSync(path,{length:524288})}\n`;
      } catch { report += `\n${name} 读取失败\n`; }
    }
    report += `\n===== 最近内存记录 =====\n${PlaybackDiagnostics.entries.join('\n')}`;
    return PlaybackDiagnostics.redact(report);
  }
  static async exportFile(context: common.UIAbilityContext): Promise<boolean> {
    const paths = await new picker.DocumentViewPicker(context).save({newFileNames:[`WTV-error-${Date.now()}.txt`],fileSuffixChoices:['文本日志|.txt']});
    if (!paths.length) return false;
    PlaybackDiagnostics.write(paths[0],PlaybackDiagnostics.report(),false); return true;
  }
  static clear(): void {
    for (const name of ['fault.log','fault-previous.log','previous.log','current.log']) {
      const path = `${PlaybackDiagnostics.directory}/${name}`;
      if (PlaybackDiagnostics.directory && fs.accessSync(path)) fs.unlinkSync(path);
    }
    PlaybackDiagnostics.entries = []; PlaybackDiagnostics.storageError = '';
  }
}
