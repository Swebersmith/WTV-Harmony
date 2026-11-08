import { UIAbility, Want, AbilityConstant, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { applySystemBars, updateAvoidAreas } from '../design/WindowStyle';

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void { this.receive(want); }
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void { this.receive(want); }
  private receive(want: Want): void {
    const shared = want.parameters?.['ohos.extra.param.key.content'] as string || want.uri || '';
    const match = shared.match(/https?:\/\/[^\s<>"']+/i);
    if (match) AppStorage.setOrCreate('sharedUrl',match[0]);
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    AppStorage.setOrCreate('abilityContext',this.context);
    AppStorage.setOrCreate('systemDark',this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    this.mainWindow = stage.getMainWindowSync();
    const win = this.mainWindow;
    win.on('avoidAreaChange',(event: window.AvoidAreaOptions): void => {
      if (event.type === window.AvoidAreaType.TYPE_KEYBOARD) AppStorage.setOrCreate('keyboardVisible',event.area.bottomRect.height > 0);
      else updateAvoidAreas(win);
    });
    win.setWindowLayoutFullScreen(true).then(async (): Promise<void> => {
      updateAvoidAreas(win); await applySystemBars(win);
    }).catch((): void => {}).finally((): void => { stage.loadContent('pages/Index'); });
  }
  onConfigurationUpdate(config: Configuration): void {
    if (config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK || config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      AppStorage.setOrCreate('systemDark',config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
    if (this.mainWindow) applySystemBars(this.mainWindow).catch((): void => {});
  }
  onWindowStageDestroy(): void { this.mainWindow?.off('avoidAreaChange'); this.mainWindow = undefined; }
  onForeground(): void { AppStorage.setOrCreate('inForeground',true); }
  onBackground(): void { AppStorage.setOrCreate('inForeground',false); }
}
