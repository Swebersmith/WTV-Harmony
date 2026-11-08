import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Settings, Library, defaults } from '../model/Models';

export class Store {
  private prefs?: preferences.Preferences;
  settings: Settings = defaults();
  library: Library = {favorites:[],records:[],queries:[]};
  async open(context: common.UIAbilityContext): Promise<void> {
    this.prefs = await preferences.getPreferences(context,{name:'wtv_native'});
    const config = await this.prefs.get('settings','') as string;
    const library = await this.prefs.get('library','') as string;
    if (config) { try { this.settings = JSON.parse(config) as Settings; } catch { this.settings = defaults(); } }
    if ((this.settings.schemaVersion || 1) < 2) {
      if (!this.settings.parsers.some((p): boolean => p.type === 'web')) {
        this.settings.parsers = this.settings.parsers.concat(defaults().parsers.filter((p): boolean => p.type === 'web'));
      }
      if (!this.settings.parsers.some((p): boolean => p.type === 'page')) this.settings.parsers.push(defaults().parsers[3]);
      this.settings.schemaVersion = 2;
    }
    if (library) { try { this.library = JSON.parse(library) as Library; } catch { this.library = {favorites:[],records:[],queries:[]}; } }
  }
  async save(): Promise<void> {
    if (!this.prefs) throw new Error('本地存储尚未就绪');
    await this.prefs.put('settings',JSON.stringify(this.settings));
    await this.prefs.put('library',JSON.stringify(this.library));
    await this.prefs.flush();
  }
}
