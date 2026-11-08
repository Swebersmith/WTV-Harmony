import { common } from '@kit.AbilityKit';
import { window, LengthMetrics } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { connection } from '@kit.NetworkKit';
import { HdsTabs, HdsTabsController, HdsNavigation, HdsNavDestination, HdsNavigationTitleMode, TitleSize, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { APP_THEME, FIELD, EMPHASIS } from '../design/Theme';
import { applySystemBars } from '../design/WindowStyle';
import { Api } from '../services/Api';
import { Store } from '../services/Store';
import { MediaSession } from '../services/MediaSession';
import { BackgroundPlayback } from '../services/BackgroundPlayback';
import { PictureInPicture } from '../services/PictureInPicture';
import { VideoSurface } from '../services/VideoSurface';
import { PlaybackDiagnostics } from '../services/PlaybackDiagnostics';
import { AdFilter, AdRange, originalTime, filteredTime, prepareNativeMedia } from '../services/AdFilter';
import { NativePlayback } from '../services/NativePlayback';
import { NativePlayer } from '../components/NativePlayer';
import { WebPlayer, WebPlayerHandle } from '../components/WebPlayer';
import { Endpoint, Movie, Episode, Playlist, WatchRecord, PLATFORMS, PLATFORM_NAMES, emptyMovie,
  defaults, movieKey, validUrl, officialSearch, episodeLabel, mediaUrl as isMediaUrl } from '../model/Models';

const BG: Resource = $r('app.color.page_background');
const CARD: Resource = $r('app.color.card_background');
const INK: Resource = $r('app.color.text_primary');
const MUTED: Resource = $r('app.color.text_secondary');
const ACCENT: string = '#167E6B';

@Entry
@Component
struct Index {
  private nav: NavPathStack = new NavPathStack();
  private tabs: HdsTabsController = new HdsTabsController();
  private discoverScroll: Scroller = new Scroller();
  private playerScroll: Scroller = new Scroller();
  private playerScrollBeforeFullscreen: number = 0;
  private libraryScroll: Scroller = new Scroller();
  private settingsScroll: Scroller = new Scroller();
  private tabChangedAt: number = 0;
  private video: NativePlayback = new NativePlayback();
  private videoSurface: VideoSurface = new VideoSurface(this.video);
  private webPlayer: WebPlayerHandle = new WebPlayerHandle();
  private originalMediaUrl: string = '';
  private mediaHls: boolean = false;
  private filterFallbackUsed: boolean = false;
  private loadResumeOriginal: number = 0;
  private api: Api = new Api();
  private store: Store = new Store();
  private media: MediaSession = new MediaSession();
  private backgroundLease: BackgroundPlayback = new BackgroundPlayback();
  private pip: PictureInPicture = new PictureInPicture();
  private backgroundWarning: boolean = false;
  private backgroundSerial: number = 0;
  private disposed: boolean = false;
  private adFilter: AdFilter = new AdFilter();
  private adRanges: AdRange[] = [];
  private nativeWindow?: window.Window;
  private originalOrientation: window.Orientation = window.Orientation.UNSPECIFIED;
  private orientationQueue: Promise<void> = Promise.resolve();
  private context?: common.UIAbilityContext;
  private net?: connection.NetConnection;
  @State sessionReady: boolean = false;
  private searchSerial: number = 0;
  private detailSerial: number = 0;
  private resolveSerial: number = 0;
  private savedAt: number = 0;
  private suppressedRecords: Set<string> = new Set<string>();
  private undoRecord?: WatchRecord;
  private undoIndex: number = 0;
  private undoTimer: number = -1;
  private resumeAt: number = 0;
  private recordReady: boolean = false;
  private activeMovie: Movie = emptyMovie();
  private activeEpisode: Episode = {title:'',url:''};
  @StorageLink('sharedUrl') @Watch('onShared') shared: string = '';
  @StorageProp('inForeground') @Watch('onForeground') foreground: boolean = true;
  @StorageLink('openPlayerRequest') @Watch('onOpenPlayer') openPlayerRequest: number = 0;
  @StorageProp('safeTopPx') safeTopPx: number = 0;
  @StorageProp('safeBottomPx') safeBottomPx: number = 0;
  @StorageProp('safeLeftPx') safeLeftPx: number = 0;
  @StorageProp('safeRightPx') safeRightPx: number = 0;
  @StorageProp('keyboardVisible') keyboardVisible: boolean = false;
  @State reduceMotion: boolean = false;
  @State tabMaterial: hdsMaterial.MaterialType = hdsMaterial.MaterialType.ADAPTIVE;
  @State ready: boolean = false;
  @State tab: number = 0;
  @State query: string = '';
  @State searchedQuery: string = '';
  @State platform: number = 0;
  @State sourceIndex: number = 0;
  @State sources: Endpoint[] = defaults().searches;
  @State parsers: Endpoint[] = defaults().parsers;
  @State parserIndex: number = 0;
  @State results: Movie[] = [];
  @State queries: string[] = [];
  @State favorites: Movie[] = [];
  @State records: WatchRecord[] = [];
  @State undoRecordVisible: boolean = false;
  @State loading: boolean = false;
  @State hasMore: boolean = false;
  @State page: number = 1;
  @State searchError: string = '';
  @State selected: Movie = emptyMovie();
  @State lines: Playlist[] = [];
  @State lineIndex: number = 0;
  @State detailLoading: boolean = false;
  @State detailError: string = '';
  @State currentMovie: Movie = emptyMovie();
  @State currentEpisode: Episode = {title:'',url:''};
  @State currentEpisodes: Episode[] = [];
  @State currentIndex: number = -1;
  @State inputUrl: string = '';
  @State mediaUrl: string = '';
  @State nativePlayerMounted: boolean = false;
  @State webUrl: string = '';
  @State blockAds: boolean = true;
  @State prepareService: string = defaults().prepareService || '';
  @State adStatus: string = '';
  @State resolving: boolean = false;
  @State playerError: string = '';
  @State playing: boolean = false;
  @State fullscreen: boolean = false;
  @State webFullscreen: boolean = false;
  @State buffering: boolean = false;
  @State elapsed: number = 0;
  @State duration: number = 0;
  @State site: string = defaults().site;
  @State autoNext: boolean = true;
  @State backgroundPlayback: boolean = true;
  @State autoPip: boolean = false;
  @State casting: boolean = false;
  @State castDevice: string = '';
  @State castElapsed: number = 0;
  @State castPlaying: boolean = false;
  @State videoAspect: number = 16 / 9;
  @State pipActive: boolean = false;
  @State playbackRate: number = 1;
  @State network: string = '检查网络';
  @State syncing: boolean = false;
  @State sheet: boolean = false;
  @State editKind: string = 'search';
  @State editId: string = '';
  @State editName: string = '';
  @State editUrl: string = '';
  @State editToken: string = '';
  @State editType: number = 0;
  @State editorError: string = '';

  aboutToAppear(): void {
    this.disposed = false;
    this.video.listen({
      prepared:(duration: number): void => {
        this.duration = duration; this.resumeAt = 0; this.updateMetadata();
        const size = this.video.getVideoSize();
        this.videoAspect = size[0] > 0 && size[1] > 0 ? size[0]/size[1] : 16/9;
        this.media.setCastMedia(this.mediaUrl,this.elapsed,duration,this.currentEpisode.url,this.currentMovie.title,this.currentEpisode.title);
        this.pip.size(size[0],size[1]); this.ensurePip().catch((): void => {});
      },
      time:(seconds: number): void => { this.elapsed = seconds; this.savePosition(); this.updateSystemPlayback(); },
      rate:(value: number): void => { this.playbackRate = value; this.updateSystemPlayback(); },
      seekFailed:(): void => { if (this.foreground) this.notice('跳转未完成，请重试'); },
      playing:(value: boolean): void => this.playbackChanged(value),
      buffering:(value: boolean): void => { this.buffering = value; this.updateSystemPlayback(); },
      ended:(): void => { if (this.autoNext && this.currentIndex >= 0 && this.currentIndex+1 < this.currentEpisodes.length) this.neighbor(1); },
      failed:(code: number): void => this.nativePlaybackFailed(code)
    });
    this.initialize();
  }
  async initialize(): Promise<void> {
    try {
      const materials = hdsMaterial.getSystemMaterialTypes();
      this.tabMaterial = materials.includes(hdsMaterial.MaterialType.IMMERSIVE)
        ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE;
    } catch { this.tabMaterial = hdsMaterial.MaterialType.ADAPTIVE; }
    try {
      this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.backgroundLease.open(this.context,(): void => this.video.pause());
      this.media.setCastEvents({
        started:(device: string): void => this.castStarted(device),
        stopped:(seconds: number): void => this.castStopped(seconds),
        state:(playing: boolean): void => { this.castPlaying = playing; if (this.casting) this.media.update(playing,this.castElapsed,this.playbackRate).catch((): void => {}); },
        position:(seconds: number): void => this.castPosition(seconds),
        error:(message: string): void => this.notice(message)
      });
      this.nativeWindow = await window.getLastWindow(this.context);
      this.originalOrientation = this.nativeWindow.getPreferredOrientation();
      await this.store.open(this.context);
      this.sources = this.store.settings.searches;
      this.parsers = this.store.settings.parsers;
      this.site = this.store.settings.site;
      this.autoNext = this.store.settings.autoNext;
      this.backgroundPlayback = this.store.settings.backgroundPlayback !== false;
      this.autoPip = this.backgroundPlayback && this.store.settings.autoPip === true;
      this.reduceMotion = this.store.settings.reduceMotion === true;
      this.blockAds = this.store.settings.blockAds !== false;
      this.prepareService = this.store.settings.prepareService || defaults().prepareService || '';
      this.favorites = this.store.library.favorites;
      this.records = this.store.library.records;
      this.queries = this.store.library.queries;
      this.ready = true;
      this.onShared();
      this.onOpenPlayer();
      this.watchNetwork();
    } catch { this.notice('本地存储初始化失败，请重新启动应用'); }
  }
  aboutToDisappear(): void {
    this.disposed = true; ++this.backgroundSerial; ++this.resolveSerial;
    clearTimeout(this.undoTimer);
    this.api.cancel();
    this.adFilter.cancel(); this.nativeFullscreenChanged(false);
    this.pip.close().catch((): void => {}).finally((): void => this.videoSurface.dispose()); this.backgroundLease.close().catch((): void => {});
    this.video.setKeepAlive(false); this.video.clear(); this.video.detach();
    this.media.close().catch((): void => {});
    this.net?.unregister((): void => {});
    this.keepAwake(false);
    this.persist();
  }
  onBackPress(): boolean {
    if (this.webPlayer.exitFullscreen()) return true;
    if (this.fullscreen) { this.nativeFullscreenChanged(false); return true; }
    if (this.sheet) { this.sheet = false; return true; }
    if (this.nav.size() > 0) return false;
    if (this.tab !== 0) { this.changeTab(0); return true; }
    return false;
  }
  onForeground(): void {
    PlaybackDiagnostics.record(`foreground=${this.foreground} playing=${this.playing} backgroundEnabled=${this.backgroundPlayback} pip=${this.pipActive} task=${this.backgroundLease.isRunning()}`);
    if (!this.foreground) {
      if (!this.backgroundPlayback && !this.pipActive) this.video.pause();
      this.webPlayer.exitFullscreen(); this.persist(); this.keepAwake(false);
    } else { this.onOpenPlayer(); this.keepAwake(this.playing && this.tab === 1 && !this.pipActive); }
    this.syncBackground(); this.syncPip();
  }
  onOpenPlayer(): void {
    if (this.ready && this.foreground && this.openPlayerRequest > 0) {
      this.openPlayerRequest = 0;
      // Do not reset an already visible player page: clearing the stack is what made PiP restores look like a refresh.
      if (this.nav.size() > 0) this.nav.clear();
      if (this.tab !== 1) this.changeTab(1);
    }
  }
  onShared(): void {
    if (this.ready && validUrl(this.shared)) { this.inputUrl = this.shared; this.shared = ''; this.changeTab(1); }
  }
  watchNetwork(): void {
    connection.hasDefaultNet().then((value: boolean): void => { this.network = value ? '网络已连接' : '当前离线'; }).catch((): void => { this.network = '网络状态未知'; });
    this.net = connection.createNetConnection();
    this.net.on('netAvailable',(): void => { this.network = '网络已连接'; });
    this.net.on('netLost',(): void => { this.network = '网络已变化'; });
    this.net.register((): void => {});
  }
  notice(message: string): void { this.getUIContext().getPromptAction().showToast({message,duration:3500}); }
  message(error: Error): string { return error.message || '操作未成功，请检查网络后重试'; }
  async copyPlaybackDiagnostics(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,PlaybackDiagnostics.report()));
      this.notice('播放诊断已复制');
    } catch { this.notice('复制失败，请重试'); }
  }
  async exportErrorLog(): Promise<void> {
    if (!this.context) return;
    try {
      if (await PlaybackDiagnostics.exportFile(this.context)) this.notice('错误日志已导出');
    } catch { this.notice('导出失败，可尝试复制日志'); }
  }
  clearErrorLog(): void {
    try { PlaybackDiagnostics.clear(); this.notice('错误日志已清空'); }
    catch { this.notice('部分日志未能清空，请重试'); }
  }
  persist(): void {
    if (!this.ready) return;
    this.store.settings = {site:this.site,searches:this.sources,parsers:this.parsers,autoNext:this.autoNext,schemaVersion:2,blockAds:this.blockAds,prepareService:this.prepareService,reduceMotion:this.reduceMotion,
      backgroundPlayback:this.backgroundPlayback,autoPip:this.autoPip};
    this.store.library = {favorites:this.favorites,records:this.records,queries:this.queries};
    this.store.save().catch((): void => this.notice('保存失败，本次修改可能无法保留'));
  }
  changeTab(index: number): void {
    if (this.tab === index) return;
    if (this.tab === 1 && index !== 1) {
      this.resumeAt = originalTime(this.elapsed,this.adRanges); this.savePosition(true);
      if (!this.backgroundPlayback && !this.pipActive) { this.video.pause(); this.recordReady = false; }
      this.keepAwake(false);
    }
    this.tabChangedAt = Date.now(); this.tab = index; this.tabs.changeIndex(index);
    this.keepAwake(this.playing && this.foreground && index === 1 && !this.pipActive); this.syncPip();
  }
  repeatTab(index: number): void {
    if (index !== this.tab || Date.now()-this.tabChangedAt < 100) return;
    const scroll = [this.discoverScroll,this.playerScroll,this.libraryScroll,this.settingsScroll][index];
    scroll.scrollTo({xOffset:0,yOffset:0,animation:this.reduceMotion ? false : {duration:220,curve:Curve.EaseOut}});
  }
  invalidateSearch(): void {
    ++this.searchSerial; this.loading = false; this.hasMore = false; this.page = 1;
    this.results = []; this.searchError = ''; this.searchedQuery = '';
  }
  async search(more: boolean = false): Promise<void> {
    if (!this.ready || this.loading) return;
    const query = this.query.trim();
    if (!query || query.length > 80) { this.notice('请输入 1–80 字的片名'); return; }
    const source = this.sources[this.sourceIndex];
    if (!source) { this.notice('请先添加搜索接口'); return; }
    if (more && query !== this.searchedQuery) { this.notice('片名已修改，请重新搜索'); return; }
    const serial = ++this.searchSerial;
    const requestedPage = more ? this.page+1 : 1;
    this.loading = true; this.searchError = '';
    if (!more) { this.results = []; this.hasMore = false; this.page = 1; }
    this.searchedQuery = query;
    this.queries = [query,...this.queries.filter((item: string): boolean => item !== query)].slice(0,15);
    this.persist();
    try {
      const result = await this.api.search(source,query,PLATFORMS[this.platform],requestedPage);
      if (serial !== this.searchSerial) return;
      this.results = more ? this.results.concat(result.results) : result.results;
      this.hasMore = result.hasMore; this.page = requestedPage;
      if (result.partial) this.notice('接口返回部分结果，可稍后重试');
    } catch (error) { if (serial === this.searchSerial) this.searchError = this.message(error as Error); }
    finally { if (serial === this.searchSerial) this.loading = false; }
  }
  async openMovie(item: Movie): Promise<void> {
    const serial = ++this.detailSerial;
    this.selected = item; this.lines = []; this.lineIndex = 0; this.detailError = ''; this.detailLoading = true;
    if (!this.nav.getAllPathName().includes('detail')) this.nav.pushPath({name:'detail'},!this.reduceMotion);
    try {
      const source = this.sources.find((value: Endpoint): boolean => value.id === item.sourceId);
      if (!source) throw new Error('这部影片的搜索源已删除，请重新添加后搜索');
      const detail = await this.api.detail(source,item);
      if (serial !== this.detailSerial) return;
      this.selected = detail.series; this.lines = detail.playlists;
    } catch (error) { if (serial === this.detailSerial) this.detailError = this.message(error as Error); }
    finally { if (serial === this.detailSerial) this.detailLoading = false; }
  }
  isFavorite(item: Movie): boolean { return this.favorites.some((m: Movie): boolean => movieKey(m) === movieKey(item)); }
  toggleFavorite(item: Movie): void {
    this.getUIContext().animateTo({duration:this.reduceMotion ? 0 : 180,curve:Curve.EaseOut},(): void => {
      if (this.isFavorite(item)) this.favorites = this.favorites.filter((m: Movie): boolean => movieKey(m) !== movieKey(item));
      else this.favorites = [item,...this.favorites].slice(0,200);
    });
    this.persist();
  }
  chooseEpisode(index: number): void {
    const episodes = this.lines[this.lineIndex]?.episodes || [];
    if (!episodes[index]) return;
    this.currentMovie = this.selected; this.currentEpisodes = episodes; this.currentIndex = index;
    this.currentEpisode = episodes[index]; this.inputUrl = episodes[index].url;
    this.resumeAt = this.records.find((r: WatchRecord): boolean => r.episode.url === episodes[index].url)?.seconds || 0;
    if (this.parsers[this.parserIndex]?.type === 'direct' && !isMediaUrl(episodes[index].url)) {
      const web = this.parsers.findIndex((parser: Endpoint): boolean => parser.type === 'web' && parser.enabled);
      if (web >= 0) this.parserIndex = web;
    }
    this.nav.clear(); this.changeTab(1); this.resolve();
  }
  playLink(): void {
    if (this.inputUrl.trim() !== this.currentEpisode.url) {
      this.currentMovie = emptyMovie(); this.currentMovie.url = this.inputUrl.trim();
      this.currentEpisode = {title:'链接播放',url:this.inputUrl.trim()};
      this.currentEpisodes = []; this.currentIndex = -1; this.resumeAt = 0;
    }
    this.resolve();
  }
  async resolve(): Promise<void> {
    const serial = ++this.resolveSerial;
    if (this.casting) {
      this.casting = false; this.castDevice = ''; this.castPlaying = false;
      this.media.stopCast(false).catch((): void => {});
    }
    this.adFilter.cancel();
    this.savePosition(true); this.recordReady = false;
    this.webPlayer.exitFullscreen(); this.webUrl = '';
    this.video.clear(); this.playing = false; this.keepAwake(false);
    this.media.update(false,this.elapsed).catch((): void => {});
    this.playerError = ''; this.resolving = true; this.mediaUrl = ''; this.elapsed = 0; this.duration = 0; this.adStatus = ''; this.adRanges = [];
    this.syncBackground(); this.syncPip();
    this.originalMediaUrl = ''; this.filterFallbackUsed = false;
    try {
      const parser = this.parsers[this.parserIndex];
      if (!parser) throw new Error('请先添加解析接口');
      const target = await this.api.playback(this.currentEpisode.url,parser);
      if (serial !== this.resolveSerial) return;
      if (target.kind === 'web') {
        await this.pip.close(); await this.backgroundLease.sync(false); await this.media.close(); this.sessionReady = false;
        if (serial !== this.resolveSerial) return;
        this.pipActive = false; this.video.setKeepAlive(false); this.video.setAudioOnly(false); this.video.detach();
        this.nativePlayerMounted = false;
        if (this.fullscreen) this.nativeFullscreenChanged(false);
        this.webUrl = target.url; return;
      }
      this.webUrl = '';
      if (this.blockAds && /\.m3u8(?:[?#]|$)/i.test(target.url)) this.adStatus = '正在检查 HLS 插播…';
      const plan = await prepareNativeMedia(target.url,this.blockAds,this.prepareService,this.adFilter);
      if (serial !== this.resolveSerial) return;
      this.adRanges = plan.ranges; this.adStatus = plan.status; this.originalMediaUrl = plan.originalUrl; this.mediaHls = plan.hls;
      this.activeMovie = this.currentMovie; this.activeEpisode = this.currentEpisode;
      this.mediaUrl = plan.url; this.nativePlayerMounted = true; this.loadResumeOriginal = this.resumeAt;
      await this.ensureSession();
      if (serial !== this.resolveSerial) return;
      this.updateMetadata(); this.syncBackground(); this.syncPip();
      this.video.load(plan.url,plan.hls,filteredTime(this.resumeAt,this.adRanges),this.canPlayNative());
    } catch (error) {
      if (serial === this.resolveSerial) { this.playerError = this.message(error as Error); if (this.fullscreen) this.nativeFullscreenChanged(false); }
    }
    finally { if (serial === this.resolveSerial) this.resolving = false; }
  }
  nativePlaybackFailed(code: number): void {
    if (!this.filterFallbackUsed && this.originalMediaUrl && this.mediaUrl !== this.originalMediaUrl) {
      this.filterFallbackUsed = true;
      const resume = this.recordReady ? originalTime(this.elapsed,this.adRanges) : this.loadResumeOriginal;
      this.recordReady = false; this.adRanges = []; this.playerError = '';
      this.adStatus = '过滤流暂不可播放 · 已恢复直连，本次未过滤';
      this.mediaUrl = this.originalMediaUrl;
      this.video.load(this.mediaUrl,this.mediaHls,resume,this.canPlayNative());
      return;
    }
    this.playerError = code === -2 ? '媒体加载超时，请重试或切换线路' : '媒体暂不可播放，请重试或切换线路';
    this.playbackChanged(false);
  }
  toggleAdFilter(value: boolean): void {
    if (this.blockAds === value) return;
    this.blockAds = value; this.persist();
    if ((this.mediaUrl || this.resolving) && this.currentEpisode.url) {
      if (this.recordReady) this.resumeAt = originalTime(this.elapsed,this.adRanges);
      this.resolve();
    }
  }
  nativeFullscreenChanged(value: boolean): void {
    this.adjustPlayerScroll(value,this.fullscreen);
    this.fullscreen = value;
    AppStorage.setOrCreate('mediaFullscreen',value);
    this.orientationQueue = this.orientationQueue.then(async (): Promise<void> => {
      if (!this.nativeWindow) return;
      await this.nativeWindow.setPreferredOrientation(value ? window.Orientation.AUTO_ROTATION_LANDSCAPE : this.originalOrientation).catch((): void => {});
      await applySystemBars(this.nativeWindow,value);
    }).catch((): void => {});
  }
  webFullscreenChanged(value: boolean): void {
    this.adjustPlayerScroll(value,this.webFullscreen); this.webFullscreen = value;
  }
  adjustPlayerScroll(value: boolean, previous: boolean): void {
    if (value === previous) return;
    try {
      if (value) this.playerScrollBeforeFullscreen = this.playerScroll.currentOffset().yOffset;
      this.playerScroll.scrollTo({xOffset:0,yOffset:value ? 0 : this.playerScrollBeforeFullscreen,animation:false});
    } catch {}
  }
  async ensureSession(): Promise<void> {
    if (this.disposed || this.sessionReady || !this.context || !this.mediaUrl) return;
    try {
      await this.media.setBackground(this.backgroundPlayback || this.pipActive);
      await this.media.open(this.context,{
        play:(): void => this.playFromSystem(),pause:(): void => this.video.pause(),
        stop:(): void => { this.video.pause(); this.pip.stop(false).catch((): void => {}); },
        next:(): void => this.neighbor(1),previous:(): void => this.neighbor(-1),
        seek:(seconds: number): void => this.seekFromSystem(seconds),
        skip:(seconds: number): void => this.seekFromSystem(this.video.position()+seconds),
        rate:(value: number): void => this.video.setRate(value)
      });
      if (this.disposed) return;
      this.sessionReady = this.media.isOpen();
      this.updateSystemPlayback();
    } catch { this.notice('系统媒体会话暂不可用，仍可使用页面播放控件'); }
  }
  canPlayNative(): boolean { return !!this.mediaUrl && !this.webUrl && (this.backgroundPlayback || this.pipActive || (this.foreground && this.tab === 1)); }
  playFromSystem(): void {
    if (this.foreground && this.tab !== 1 && !this.backgroundPlayback && !this.pipActive) this.changeTab(1);
    if (this.canPlayNative()) this.video.start();
  }
  updateSystemPlayback(): void { this.media.update(this.playing,this.elapsed,this.playbackRate,this.buffering).catch((): void => {}); }
  seekFromSystem(seconds: number): void {
    if (this.video.setCurrentTime(seconds)) {
      this.media.update(this.playing,this.elapsed,this.playbackRate,this.buffering,true).catch((): void => {});
    }
  }
  updateMetadata(): void {
    if (!this.mediaUrl || this.webUrl) return;
    this.media.metadata(this.currentEpisode.url,this.currentMovie.title,this.currentEpisode.title,this.currentMovie.cover,this.duration).catch((): void => {});
  }
  syncBackground(): void {
    const serial = ++this.backgroundSerial;
    const allowed = this.backgroundPlayback || this.pipActive;
    this.video.setKeepAlive(!!this.mediaUrl && !this.webUrl); this.video.setAudioOnly(!this.foreground && !this.pipActive);
    const mode = this.media.setBackground(allowed); mode.catch((): void => {});
    if (this.disposed || !this.context) return;
    this.ensureSession().then(async (): Promise<void> => {
      if (this.disposed || serial !== this.backgroundSerial) return;
      if (allowed && this.playing && !this.sessionReady) throw new Error('会话未就绪');
      const required = allowed && this.playing && !!this.mediaUrl && !this.webUrl;
      if (!required) await this.backgroundLease.sync(false);
      await mode;
      if (required && serial === this.backgroundSerial) await this.backgroundLease.sync(true);
    }).catch((error: Error): void => {
      if (this.disposed || serial !== this.backgroundSerial) return;
      PlaybackDiagnostics.record(`background sync failed ${error.message}`);
      if (!this.foreground && this.playing) PlaybackDiagnostics.record('pause: background task unavailable');
      if (!this.foreground && this.playing) this.video.pause();
      if (!this.backgroundWarning) { this.backgroundWarning = true; this.notice('后台播放暂不可用，请返回应用播放'); }
    });
  }
  async ensurePip(): Promise<void> {
    if (!this.context || !this.mediaUrl || this.webUrl) throw new Error('请先播放原生视频');
    await this.pip.open(this.context,this.videoSurface,{
      play:(): void => this.playFromSystem(),pause:(): void => this.video.pause(),
      next:(): void => this.neighbor(1),previous:(): void => this.neighbor(-1),
      skip:(seconds: number): void => this.seekFromSystem(this.video.position()+seconds),
      changed:(active: boolean): void => {
        this.pipActive = active; this.keepAwake(this.playing && this.foreground && this.tab === 1 && !active); this.syncBackground();
      },
      restore:(): void => { PlaybackDiagnostics.record(`PiP restore tab=${this.tab}`); if (!this.disposed && this.tab !== 1) this.changeTab(1); },
      failed:(): void => { if (!this.foreground && !this.backgroundPlayback) this.video.pause(); this.notice('系统小窗暂不可用'); }
    },this.getUIContext());
    this.syncPip();
  }
  syncPip(): void {
    this.pip.configure(this.autoPip && this.backgroundPlayback,!!this.mediaUrl && !this.webUrl && !this.casting && this.tab === 1,
      this.playing,this.currentIndex > 0,this.currentIndex >= 0 && this.currentIndex+1 < this.currentEpisodes.length);
  }
  castStarted(device: string): void {
    this.casting = true; this.castDevice = device; this.castElapsed = this.elapsed; this.castPlaying = this.playing;
    PlaybackDiagnostics.record(`cast started device=${device} at=${this.elapsed.toFixed(1)}`);
    if (this.playing) this.video.pause();
    this.syncPip();
  }
  castStopped(seconds: number): void {
    if (this.disposed) return;
    const resume = this.castPlaying;
    this.casting = false; this.castDevice = ''; this.castPlaying = false;
    this.castElapsed = seconds; this.elapsed = seconds;
    PlaybackDiagnostics.record(`cast stopped at=${seconds.toFixed(1)} resume=${resume}`);
    if (this.mediaUrl && !this.webUrl && this.nativePlayerMounted) {
      this.video.setCurrentTime(seconds);
      if (resume) this.video.start();
    }
    this.syncPip();
  }
  castPosition(seconds: number): void {
    this.castElapsed = seconds;
    if (this.casting) { this.elapsed = seconds; this.savePosition(); }
  }
  toggleCast(): void {
    if (!this.casting) return;
    const next = !this.castPlaying; this.castPlaying = next;
    (next ? this.media.castPlay() : this.media.castPause()).catch((): void => {
      this.castPlaying = !next; this.notice('投屏控制未送达');
    });
  }
  stopCasting(): void {
    if (!this.casting) return;
    this.media.stopCast().catch((): void => this.notice('结束投屏失败，请稍后重试'));
  }
  async startSmallWindow(): Promise<void> {
    try {
      await this.ensurePip();
      if (this.fullscreen) { this.nativeFullscreenChanged(false); await this.orientationQueue; }
      await this.pip.start();
    } catch (error) { this.notice(this.message(error as Error)); }
  }
  restoreSmallWindow(): void { this.pip.stop(true).catch((): void => this.notice('暂无法返回播放框')); }
  setBackgroundPlayback(value: boolean): void {
    this.backgroundPlayback = value; if (!value) this.autoPip = false;
    this.backgroundWarning = false; this.persist(); this.syncBackground(); this.syncPip();
    if (!value && !this.pipActive && (!this.foreground || this.tab !== 1)) this.video.pause();
  }
  neighbor(direction: number): void {
    const index = this.currentIndex+direction;
    if (index < 0 || index >= this.currentEpisodes.length) { this.notice('没有更多选集'); return; }
    this.currentIndex = index; this.currentEpisode = this.currentEpisodes[index];
    this.inputUrl = this.currentEpisode.url; this.resumeAt = 0; this.resolve();
  }
  playCurrentEpisode(index: number): void {
    if (!this.currentEpisodes[index]) return;
    this.currentIndex = index; this.currentEpisode = this.currentEpisodes[index];
    this.inputUrl = this.currentEpisode.url; this.resumeAt = 0; this.resolve();
  }
  savePosition(force: boolean = false): void {
    if (!this.recordReady || !this.activeEpisode.url || this.suppressedRecords.has(this.activeEpisode.url) || (!force && Date.now()-this.savedAt < 10000)) return;
    this.savedAt = Date.now();
    const record: WatchRecord = {movie:this.activeMovie,episode:this.activeEpisode,seconds:originalTime(this.elapsed,this.adRanges),updated:Date.now()};
    this.records = [record,...this.records.filter((r: WatchRecord): boolean => r.episode.url !== record.episode.url)].slice(0,100);
    this.persist();
  }
  resume(record: WatchRecord): void {
    this.currentMovie = record.movie; this.currentEpisode = record.episode;
    this.currentEpisodes = []; this.currentIndex = -1; this.inputUrl = record.episode.url; this.resumeAt = record.seconds;
    this.changeTab(1); this.resolve();
  }
  keepAwake(value: boolean): void {
    if (this.context) window.getLastWindow(this.context).then((win: window.Window): void => {
      win.setWindowKeepScreenOn(value).catch((): void => {});
    }).catch((): void => {});
  }
  playbackChanged(value: boolean): void {
    if (this.playing !== value) PlaybackDiagnostics.record(`playback playing=${value} foreground=${this.foreground}`);
    if (value) { this.suppressedRecords.delete(this.activeEpisode.url); this.recordReady = true; }
    this.playing = value;
    this.keepAwake(value && this.foreground && this.tab === 1 && !this.pipActive);
    this.updateSystemPlayback(); this.syncBackground(); this.syncPip();
    if (!value) this.savePosition(true);
  }
  async paste(): Promise<void> {
    try {
      const text = (await pasteboard.getSystemPasteboard().getData()).getPrimaryText();
      const url = text.match(/https?:\/\/[^\s<>"']+/i)?.[0] || '';
      if (!validUrl(url)) { this.notice('剪贴板没有有效的视频链接'); return; }
      this.inputUrl = url;
    } catch { this.notice('无法读取剪贴板，请长按输入框粘贴'); }
  }
  async share(): Promise<void> {
    if (!this.context || !validUrl(this.currentEpisode.url)) return;
    try {
      const controller = new systemShare.ShareController(new systemShare.SharedData({utd:'general.hyperlink',content:this.currentEpisode.url,title:this.currentMovie.title}));
      await controller.show(this.context,{selectionMode:systemShare.SelectionMode.SINGLE});
    } catch { this.notice('分享未完成，可复制视频链接'); }
  }
  async syncSite(): Promise<void> {
    if (!validUrl(this.site,true)) { this.notice('站点地址需要使用 HTTPS'); return; }
    this.syncing = true;
    try {
      const config = await this.api.siteConfig(this.site);
      this.sources = this.sources.filter((s: Endpoint): boolean => !s.id.startsWith('site-')).concat(config.searches);
      this.parsers = this.parsers.filter((p: Endpoint): boolean => !p.id.startsWith('site-')).concat(config.parsers);
      this.sourceIndex = 0; this.parserIndex = 0; this.invalidateSearch(); this.persist();
      this.notice(`已同步 ${config.searches.length} 个搜索源、${config.parsers.length} 个网页播放线路`);
    } catch (error) { this.notice(this.message(error as Error)); }
    finally { this.syncing = false; }
  }
  edit(kind: string, endpoint?: Endpoint): void {
    this.editKind = kind; this.editId = endpoint?.id || ''; this.editName = endpoint?.name || '';
    this.editUrl = endpoint?.url || ''; this.editToken = endpoint?.apiKey || ''; this.editorError = '';
    this.editType = kind === 'search' ? Math.max(0,['wtv','videosearch','maccms'].indexOf(endpoint?.type || 'wtv')) : endpoint?.type === 'web' ? 1 : 0;
    this.sheet = true;
  }
  saveEndpoint(): void {
    const url = this.editUrl.trim();
    if (!this.editName.trim() || this.editName.trim().length > 60) { this.editorError = '请输入 1–60 字的接口名称'; return; }
    if (!validUrl(url,true)) { this.editorError = '请填写 HTTPS 接口地址；解析地址可包含 {url} 占位符'; return; }
    if (this.editToken.length > 500 || /[\r\n]/.test(this.editToken)) { this.editorError = '令牌最长 500 字，且不能包含换行'; return; }
    const entries = this.editKind === 'search' ? this.sources : this.parsers;
    if (!this.editId && entries.length >= 30) { this.editorError = '每类最多添加 30 个接口'; return; }
    const item: Endpoint = {id:this.editId || `custom-${Date.now()}`,name:this.editName.trim(),url,apiKey:this.editToken.trim(),enabled:true,
      type:this.editKind === 'search' ? ['wtv','videosearch','maccms'][this.editType] : ['json','web'][this.editType]};
    if (item.type === 'web') item.apiKey = '';
    const updated = this.editId ? entries.map((old: Endpoint): Endpoint => old.id === item.id ? item : old) : entries.concat([item]);
    if (this.editKind === 'search') { this.sources = updated; this.sourceIndex = updated.findIndex((v: Endpoint): boolean => v.id === item.id); this.invalidateSearch(); }
    else { this.parsers = updated; this.parserIndex = updated.findIndex((v: Endpoint): boolean => v.id === item.id); }
    this.sheet = false; this.persist(); this.notice('接口已保存');
  }
  removeEndpoint(kind: string, item: Endpoint): void {
    this.getUIContext().getPromptAction().showDialog({title:'删除接口',message:`确定删除“${item.name}”？`,buttons:[
      {text:'取消',color:ACCENT},{text:'删除',color:'#C04444'}
    ]}).then((result): void => {
      if (result.index !== 1) return;
      if (kind === 'search') { this.sources = this.sources.filter((s: Endpoint): boolean => s.id !== item.id); this.sourceIndex = 0; this.invalidateSearch(); }
      else { this.parsers = this.parsers.filter((p: Endpoint): boolean => p.id !== item.id); this.parserIndex = 0; }
      this.persist();
    });
  }
  clearHistory(): void {
    this.getUIContext().getPromptAction().showDialog({title:'清空观看记录',message:'删除本机保存的观看进度和最近搜索？',buttons:[{text:'取消',color:ACCENT},{text:'清空',color:'#C04444'}]})
      .then((result): void => { if (result.index === 1) { clearTimeout(this.undoTimer); this.undoRecordVisible = false; this.undoRecord = undefined; this.records = []; this.queries = []; this.persist(); } });
  }
  deleteRecord(record: WatchRecord): void {
    const index = this.records.findIndex((item: WatchRecord): boolean => item.episode.url === record.episode.url);
    if (index < 0) return;
    this.undoRecord = this.records[index]; this.undoIndex = index; this.suppressedRecords.add(record.episode.url);
    this.getUIContext().animateTo({duration:this.reduceMotion ? 0 : 180,curve:Curve.EaseOut},(): void => {
      this.records = this.records.filter((item: WatchRecord): boolean => item.episode.url !== record.episode.url); this.undoRecordVisible = true;
    });
    clearTimeout(this.undoTimer);
    this.undoTimer = setTimeout((): void => { this.undoRecordVisible = false; this.undoRecord = undefined; },5000);
    this.persist();
  }
  restoreRecord(): void {
    const record = this.undoRecord; if (!record) return;
    this.suppressedRecords.delete(record.episode.url);
    if (!this.records.some((item: WatchRecord): boolean => item.episode.url === record.episode.url)) {
      const records = this.records.slice(); records.splice(Math.min(this.undoIndex,records.length),0,record); this.records = records.slice(0,100);
    }
    clearTimeout(this.undoTimer); this.undoRecordVisible = false; this.undoRecord = undefined; this.persist();
  }
  time(seconds: number): string { return `${Math.floor(seconds/60)}:${String(Math.floor(seconds%60)).padStart(2,'0')}`; }

  @Builder
  tabLabel(label: string, index: number) {
    Row() {
      // The glyph's ink sits about 4vp below the bar centre; lift it to match the prototype.
      SymbolGlyph(this.tabSymbol(index)).fontSize(26).fontWeight(FontWeight.Bold).width(32).height(32).offset({y:-4})
        .fontColor([this.tab === index ? EMPHASIS : MUTED])
    }.height(56).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).width('100%')
      .accessibilityText(label).accessibilityDescription(this.tab === index ? '已选中' : '切换栏目')
  }
  tabSymbol(index: number): Resource {
    if (index === 0) return $r('sys.symbol.magnifyingglass');
    if (index === 1) return $r('sys.symbol.play_circle');
    if (index === 2) return $r('sys.symbol.heart');
    return $r('sys.symbol.gearshape');
  }
  @Builder
  errorPanel(message: string) {
    Column({space:10}) {
      Text('暂时无法完成').fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK)
      Text(message).fontSize(14).fontColor(MUTED).textAlign(TextAlign.Center).copyOption(CopyOptions.LocalDevice)
    }.padding(22).width('100%').backgroundColor(CARD).borderRadius(24)
  }
  @Builder
  movieCard(item: Movie) {
    Row({space:14}) {
      Stack() {
        Text(item.title.slice(0,8)).fontSize(15).fontColor('#FFFFFF').padding(8).textAlign(TextAlign.Center)
        if (validUrl(item.cover,true)) { Image(item.cover).width('100%').height('100%').objectFit(ImageFit.Cover) }
      }.width(84).height(116).backgroundColor('#2F5D65').borderRadius(12).clip(true)
      Column({space:8}) {
        Text(item.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK).maxLines(2).textOverflow({overflow:TextOverflow.Ellipsis}).width('100%')
        Text([item.year,item.remarks,item.platform === 'resource' ? '' : PLATFORM_NAMES[PLATFORMS.indexOf(item.platform)] || ''].filter((s: string): boolean => !!s).join(' · ') || '查看详情与选集').fontSize(12).fontColor(MUTED).maxLines(2).width('100%')
        Text(item.overview || '打开影片，选择播放线路与集数').fontSize(12).fontColor(MUTED).maxLines(2).textOverflow({overflow:TextOverflow.Ellipsis}).width('100%')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(26).fontColor(ACCENT)
    }.width('100%').padding(16).backgroundColor(CARD).borderRadius(24).onClick((): void => { this.openMovie(item); })
      .stateStyles({pressed:{opacity:0.82}})
      .accessibilityText(`${item.title}，查看详情`)
  }
  @Builder
  discover() {
    Scroll(this.discoverScroll) {
      Column({space:14}) {
        Column({space:13}) {
          Search({value:this.query,placeholder:'搜索电影、剧集、综艺'})
            .enableKeyboardOnFocus(false)
            .searchButton('搜索').onChange((text: string): void => { this.query = text; })
            .onSubmit((): void => { this.search(); }).height(48).backgroundColor(FIELD).borderRadius(16)
          if (this.sources.length) {
            Select(this.sources.map((s: Endpoint): SelectOption => ({value:s.name})))
              .selected(this.sourceIndex).value(this.sources[this.sourceIndex]?.name || '选择搜索源').width('100%')
              .onSelect((index: number): void => { this.sourceIndex = index; this.invalidateSearch(); })
          } else { Button('添加搜索接口').onClick((): void => this.edit('search')) }
          if (officialSearch(this.sources[this.sourceIndex])) {
            Scroll() {
              Row({space:8}) {
              ForEach(PLATFORM_NAMES,(name: string,index: number) => {
                Button(name,{type:ButtonType.Normal}).fontSize(12).fontColor(this.platform === index ? '#FFFFFF' : MUTED)
                  .backgroundColor(this.platform === index ? ACCENT : BG).height(34).borderRadius(10)
                  .onClick((): void => { this.platform = index; this.invalidateSearch(); })
              })
              }
            }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          }
        }.padding(16).backgroundColor(CARD).borderRadius(24)
        if (!this.searchedQuery) {
          if (this.queries.length) {
            Row() {
              Text('最近搜索').fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).layoutWeight(1)
              Button('清空').fontSize(12).backgroundColor(Color.Transparent).fontColor(MUTED).onClick((): void => { this.queries = []; this.persist(); })
            }.width('100%')
            Flex({wrap:FlexWrap.Wrap}) {
              ForEach(this.queries,(q: string) => {
                Button(q).fontSize(13).backgroundColor(CARD).fontColor(INK).margin({right:8,bottom:8})
                  .onClick((): void => { this.query = q; this.search(); })
              })
            }.width('100%')
          }
        }
        if (this.loading) { LoadingProgress().width(36).height(36).color(ACCENT) }
        if (this.searchError) { this.errorPanel(this.searchError); Button('重新搜索').onClick((): void => { this.search(); }) }
        if (this.searchedQuery && !this.loading && !this.searchError && !this.results.length) {
          this.errorPanel('没有找到匹配内容，可尝试其他片名、平台或搜索源')
        }
        if (this.results.length) {
          Text(`“${this.searchedQuery}” · ${this.results.length} 个结果`).fontSize(14).fontColor(MUTED).width('100%')
          ForEach(this.results,(item: Movie) => { this.movieCard(item) },(item: Movie): string => movieKey(item))
          if (this.hasMore) { Button(this.loading ? '正在加载…' : '加载下一页').enabled(!this.loading).onClick((): void => { this.search(true); }) }
        }
        Text(this.network).fontSize(11).fontColor(MUTED).margin({top:10,bottom:10})
      }.padding({left:20,right:20,top:this.getUIContext().px2vp(this.safeTopPx)+64,bottom:this.getUIContext().px2vp(this.safeBottomPx)+88}).width('100%').constraintSize({maxWidth:760})
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }
  @Builder
  detailPage() {
    HdsNavDestination() {
      Scroll() {
        Column({space:18}) {
          Row({space:10}) {
            Button({type:ButtonType.Circle}) { Image($r('app.media.nav_back')).width(22).height(22) }
              .width(40).height(40).backgroundColor(FIELD).accessibilityText('返回').onClick((): void => { ++this.detailSerial; this.nav.pop(!this.reduceMotion); })
            Text('影片详情').fontSize(21).fontWeight(FontWeight.Bold).fontColor(INK)
          }.width('100%').margin({bottom:6})
          Row({space:16}) {
            if (validUrl(this.selected.cover,true)) { Image(this.selected.cover).width(104).height(150).borderRadius(16).objectFit(ImageFit.Cover) }
            Column({space:12}) {
              Text(this.selected.title).fontSize(25).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
              Text([this.selected.year,this.selected.remarks].filter((value: string): boolean => !!value).join(' · ')).fontSize(13).fontColor(MUTED).width('100%')
              Button(this.isFavorite(this.selected) ? '已加入片单' : '加入片单',{type:ButtonType.Normal}).fontSize(13)
                .height(38).borderRadius(12).backgroundColor(ACCENT).onClick((): void => this.toggleFavorite(this.selected))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
          Text(this.selected.overview || '暂无影片简介').fontSize(14).fontColor(MUTED).lineHeight(23).width('100%').copyOption(CopyOptions.LocalDevice)
          if (this.detailLoading) { LoadingProgress().color(ACCENT).width(36).height(36) }
          if (this.detailError) {
            this.errorPanel(this.detailError)
            Button('重试').onClick((): void => { this.openMovie(this.selected); })
          }
          if (this.lines.length) {
            Row() {
              Text(`选集 · ${this.lines[this.lineIndex]?.episodes.length || 0}`).fontSize(19).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
              Select(this.lines.map((line: Playlist): SelectOption => ({value:line.name})))
                .selected(this.lineIndex).value(this.lines[this.lineIndex]?.name || '').onSelect((index: number): void => { this.lineIndex = index; })
            }.width('100%')
            Flex({wrap:FlexWrap.Wrap,justifyContent:FlexAlign.SpaceBetween}) {
              ForEach(this.lines[this.lineIndex]?.episodes || [],(episode: Episode,index: number) => {
                Row() {
                  Text(episodeLabel(episode,this.selected.title,index)).fontSize(14).fontColor(INK).lineHeight(21)
                    .width('100%').textAlign(TextAlign.Center).wordBreak(WordBreak.BREAK_ALL)
                }.width('48.5%').constraintSize({minHeight:52}).padding({left:10,right:10,top:14,bottom:14})
                  .backgroundColor(CARD).borderRadius(12).margin({bottom:10}).onClick((): void => this.chooseEpisode(index))
                  .stateStyles({pressed:{opacity:0.65}}).focusable(true).accessibilityRole(AccessibilityRoleType.BUTTON)
                  .accessibilityText(episode.title || `第 ${index+1} 集`)
              },(episode: Episode,index: number): string => `${index}|${episode.url}`)
            }.width('100%')
          }
        }.padding({left:20,right:20,top:this.getUIContext().px2vp(this.safeTopPx)+8,bottom:this.getUIContext().px2vp(this.safeBottomPx)+24}).width('100%')
      }.height('100%').width('100%')
    }.hideTitleBar(true).backgroundColor(BG).systemTransition(this.reduceMotion ? NavigationSystemTransitionType.NONE : NavigationSystemTransitionType.CONTENT)
      .onBackPressed((): boolean => { ++this.detailSerial; return false; })
  }
  @Builder
  playerPage() {
    Scroll(this.playerScroll) {
      Column({space:this.fullscreen || this.webFullscreen ? 0 : 16}) {
        Stack() {
          if (this.nativePlayerMounted) {
            NativePlayer({controller:this.video,surface:this.videoSurface,title:this.currentMovie.title,subtitle:this.currentEpisode.title,status:this.adStatus,error:this.playerError,
              playing:this.playing,buffering:this.resolving || this.buffering,elapsed:this.elapsed,duration:this.duration,fullscreen:this.fullscreen,reduceMotion:this.reduceMotion,active:this.tab === 1,
              inPip:this.pipActive,systemRate:this.playbackRate,videoAspect:this.videoAspect,castReady:this.sessionReady,casting:this.casting,castDevice:this.castDevice,castElapsed:this.castElapsed,castPlaying:this.castPlaying,
              onCastToggle:(): void => this.toggleCast(),onCastStop:(): void => this.stopCasting(),
              onSmallWindow:(): void => { this.startSmallWindow(); },onRestoreWindow:(): void => this.restoreSmallWindow(),
              episodeNames:this.currentEpisodes.map((episode: Episode,index: number): string => episodeLabel(episode,this.currentMovie.title,index)),episodeIndex:this.currentIndex,
              onFullscreen:(value: boolean): void => this.nativeFullscreenChanged(value),onRetry:(): void => {
                this.resumeAt = this.recordReady ? originalTime(this.elapsed,this.adRanges) : this.loadResumeOriginal; this.resolve();
              },
              onEpisode:(index: number): void => this.playCurrentEpisode(index)})
          } else if (this.webUrl) {
            WebPlayer({src:this.webUrl,handle:this.webPlayer,active:this.tab === 1,title:this.currentEpisode.title,
              onFullscreen:(value: boolean): void => this.webFullscreenChanged(value)})
          } else {
            Column({space:12}) {
              if (this.resolving) { LoadingProgress().width(32).height(32).color('#6DE1C3') }
              else { Image($r('app.media.player_play')).width(34).height(34).opacity(0.75) }
              Text(this.resolving ? '正在获取媒体地址…' : '选择一集，或粘贴视频链接').fontSize(14).fontColor('#D3E6E1')
            }.height('100%').width('100%').justifyContent(FlexAlign.Center)
          }
        }.width('100%').height(this.fullscreen || this.webFullscreen ? '100%' : 224).backgroundColor('#0D141E').borderRadius(this.fullscreen || this.webFullscreen ? 0 : 22).clip(true)
        if (!this.fullscreen && !this.webFullscreen) {
        if (this.playerError && !this.nativePlayerMounted) { this.errorPanel(this.playerError) }
        if (this.currentEpisode.url) {
          Row() {
            Column({space:4}) {
              Text(this.currentMovie.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK).maxLines(1).width('100%')
              Text(this.webUrl ? this.currentEpisode.title : `${this.currentEpisode.title}  ·  ${this.time(this.elapsed)} / ${this.time(this.duration)}`).fontSize(12).fontColor(MUTED).width('100%')
            }.layoutWeight(1)
            Button('分享').fontSize(13).backgroundColor(CARD).fontColor(ACCENT).onClick((): void => { this.share(); })
          }.width('100%')
          Row({space:8}) {
            Button('上一集',{type:ButtonType.Normal}).height(42).borderRadius(14).backgroundColor(CARD).fontColor(INK).layoutWeight(1).fontSize(13).enabled(this.currentIndex > 0).onClick((): void => this.neighbor(-1))
            Text(this.webUrl ? '网页线路' : '原生播放').fontSize(11).fontColor(MUTED).padding(8)
            Button('下一集',{type:ButtonType.Normal}).height(42).borderRadius(14).backgroundColor(CARD).fontColor(INK).layoutWeight(1).fontSize(13).enabled(this.currentIndex >= 0 && this.currentIndex+1 < this.currentEpisodes.length).onClick((): void => this.neighbor(1))
          }.width('100%')
        }
        if (!this.webUrl) {
          Row({space:12}) {
            Column({space:4}) {
              Text('HLS 去插播').fontSize(14).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
            }.layoutWeight(1)
            Toggle({type:ToggleType.Switch,isOn:this.blockAds}).selectedColor(ACCENT).onChange((value: boolean): void => this.toggleAdFilter(value))
          }.padding(16).width('100%').backgroundColor(CARD).borderRadius(16)
        }
        Column({space:14}) {
          Text('链接与解析').fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
          TextInput({text:this.inputUrl,placeholder:'影片链接或 MP4 / M3U8 直链'}).onChange((text: string): void => { this.inputUrl = text; })
            .enableKeyboardOnFocus(false)
            .type(InputType.URL).height(48).backgroundColor(FIELD).borderRadius(16)
          Row({space:10}) {
            PasteButton().fontSize(13).height(36).onClick((_event: ClickEvent,result: PasteButtonOnClickResult): void => { if (result === PasteButtonOnClickResult.SUCCESS) this.paste(); })
            Select(this.parsers.map((p: Endpoint): SelectOption => ({value:`${p.name}${p.type === 'web' ? ' · 网页型' : ''}`})))
              .selected(this.parserIndex).value(this.parsers[this.parserIndex]?.name || '先添加解析接口').layoutWeight(1)
              .onSelect((index: number): void => { this.parserIndex = index; })
          }.width('100%')
          Button(this.resolving ? '正在解析…' : '开始播放',{type:ButtonType.Normal}).borderRadius(14).width('100%').height(46).backgroundColor(ACCENT).enabled(!this.resolving && this.ready)
            .onClick((): void => this.playLink())
        }.padding(18).backgroundColor(CARD).borderRadius(24)
        if (this.currentEpisodes.length) {
          Text('正在追 · 选集').fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
          Flex({wrap:FlexWrap.Wrap,justifyContent:FlexAlign.SpaceBetween}) {
            ForEach(this.currentEpisodes,(episode: Episode,index: number) => {
              Row() {
                Text(episodeLabel(episode,this.currentMovie.title,index)).fontSize(13).lineHeight(20).width('100%').wordBreak(WordBreak.BREAK_ALL)
                  .fontColor(index === this.currentIndex ? '#FFFFFF' : INK).textAlign(TextAlign.Center)
              }.width('48.5%').constraintSize({minHeight:48}).padding(12).borderRadius(12).backgroundColor(index === this.currentIndex ? ACCENT : CARD)
                .margin({bottom:8}).onClick((): void => this.playCurrentEpisode(index))
                .stateStyles({pressed:{opacity:0.65}}).focusable(true).accessibilityRole(AccessibilityRoleType.BUTTON).accessibilityText(episode.title)
            })
          }.width('100%')
        }
        }
      }.padding({left:this.fullscreen || this.webFullscreen ? 0 : 20,right:this.fullscreen || this.webFullscreen ? 0 : 20,
        top:this.fullscreen || this.webFullscreen ? 0 : this.getUIContext().px2vp(this.safeTopPx)+64,
        bottom:this.fullscreen || this.webFullscreen ? 0 : this.getUIContext().px2vp(this.safeBottomPx)+88})
        .width('100%').height(this.fullscreen || this.webFullscreen ? '100%' : undefined).constraintSize({maxWidth:this.fullscreen || this.webFullscreen ? '100%' : 760})
    }.width('100%').height('100%').scrollable(this.fullscreen || this.webFullscreen ? ScrollDirection.None : ScrollDirection.Vertical).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }
  @Builder
  libraryPage() {
    List({space:14,scroller:this.libraryScroll}) {
      ListItem() {
        Row({space:12}) {
          this.libraryStat(String(this.favorites.length),'部收藏')
          this.libraryStat(String(this.records.length),'条观看记录')
        }.width('100%').margin({bottom:8})
      }
      ListItem() { Text(`收藏 · ${this.favorites.length}`).fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK).width('100%') }
      if (!this.favorites.length) { ListItem() { Text('在影片详情中点击“加入收藏”').fontSize(14).fontColor(MUTED).width('100%').padding(18) } }
      ForEach(this.favorites,(item: Movie) => { ListItem() { this.movieCard(item) } },(item: Movie): string => movieKey(item))
      ListItem() {
        Row() {
          Text('继续观看').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
          Button('清空记录').fontSize(12).fontColor(MUTED).backgroundColor(Color.Transparent).onClick((): void => this.clearHistory())
        }.width('100%').margin({top:16})
      }
      if (this.undoRecordVisible) {
        ListItem() {
          Row() {
            Text('已删除观看记录').fontSize(12).fontColor(MUTED).layoutWeight(1)
            Button('撤销',{type:ButtonType.Normal}).height(34).fontSize(12).fontColor(EMPHASIS).backgroundColor(Color.Transparent).onClick((): void => this.restoreRecord())
          }.padding({left:16,right:8,top:4,bottom:4}).width('100%').backgroundColor(CARD).borderRadius(16)
        }
      }
      if (!this.records.length) { ListItem() { Text('开始播放后，进度将保存在本机').fontSize(14).fontColor(MUTED).width('100%').padding(18) } }
      ForEach(this.records,(record: WatchRecord) => {
        ListItem() {
          Row({space:12}) {
            Column({space:6}) {
              Text(record.movie.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
              Text(`${record.episode.title} · 已看 ${this.time(record.seconds)}`).fontSize(12).fontColor(MUTED).width('100%')
            }.layoutWeight(1)
            Button('续播').fontSize(13).backgroundColor(ACCENT).onClick((): void => this.resume(record))
          }.padding(18).backgroundColor(CARD).borderRadius(24).width('100%')
        }.borderRadius(24).clip(true).swipeAction({end:{builder:(): void => { this.recordDeleteAction(record); },actionAreaDistance:56,onAction:(): void => this.deleteRecord(record)},edgeEffect:SwipeEdgeEffect.Spring})
          .accessibilityDescription('左滑删除观看记录')
      },(record: WatchRecord): string => record.episode.url)
    }.width('100%').height('100%').padding({left:20,right:20}).constraintSize({maxWidth:760})
      .contentStartOffset(this.getUIContext().px2vp(this.safeTopPx)+64).contentEndOffset(this.getUIContext().px2vp(this.safeBottomPx)+88)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }
  @Builder
  recordDeleteAction(record: WatchRecord) {
    Button({type:ButtonType.Normal}) {
      Column({space:5}) {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor([Color.White])
        Text('删除').fontSize(12).fontWeight(FontWeight.Medium).fontColor(Color.White)
      }.justifyContent(FlexAlign.Center).height('100%').width('100%')
    }.width(72).height('100%').backgroundColor('#D94D59').borderRadius(24).accessibilityText('删除这条观看记录')
      .onClick((): void => this.deleteRecord(record))
  }
  @Builder
  libraryStat(value: string, label: string) {
    Column({space:5}) {
      Text(value).fontSize(28).fontWeight(FontWeight.Medium).fontColor(INK)
      Text(label).fontSize(12).fontColor(MUTED)
    }.layoutWeight(1).padding(20).backgroundColor(CARD).borderRadius(24)
  }
  @Builder
  endpointCard(item: Endpoint, kind: string) {
    Column({space:8}) {
      Row() {
        Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK).layoutWeight(1)
        Text(item.type === 'web' ? '网页解析' : item.type === 'page' ? '网页直开' : item.type.toUpperCase()).fontSize(10).fontColor(ACCENT)
      }.width('100%')
      if (item.url) { Text(item.url).fontSize(11).fontColor(MUTED).maxLines(2).textOverflow({overflow:TextOverflow.Ellipsis}).width('100%') }
      Row({space:8}) {
        if (!item.id.startsWith('site-') && item.type !== 'direct' && item.type !== 'page') {
          Button('编辑').fontSize(12).fontColor(ACCENT).backgroundColor(BG).onClick((): void => this.edit(kind,item))
        }
        if (item.type !== 'direct' && item.type !== 'page') { Button('删除').fontSize(12).fontColor('#BC5050').backgroundColor(BG).onClick((): void => this.removeEndpoint(kind,item)) }
        if (item.apiKey) { Text('已设置 Bearer 令牌').fontSize(11).fontColor(MUTED) }
      }.width('100%')
    }.padding(16).backgroundColor(CARD).borderRadius(24).width('100%')
  }
  @Builder
  settingsPage() {
    Scroll(this.settingsScroll) {
      Column({space:14}) {
        Row() {
          Column({space:6}) {
            Text('接口设置').fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
            Text(`${this.sources.length} 个搜索源 · ${this.parsers.length} 个解析与网页线路`).fontSize(12).fontColor(MUTED).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text('›').fontSize(26).fontColor(ACCENT)
        }.padding(18).width('100%').backgroundColor(CARD).borderRadius(24)
          .onClick((): void => { this.nav.pushPath({name:'endpoints'},!this.reduceMotion); })
          .stateStyles({pressed:{opacity:0.82}}).accessibilityText('接口设置，进入二级页面')
        Row() {
          Text('后台播放').fontSize(15).fontColor(INK).layoutWeight(1)
          Toggle({type:ToggleType.Switch,isOn:this.backgroundPlayback}).selectedColor(ACCENT).onChange((value: boolean): void => this.setBackgroundPlayback(value))
        }.padding(18).width('100%').backgroundColor(CARD).borderRadius(24)
        Row() {
          Text('退出应用时自动小窗').fontSize(15).fontColor(INK).layoutWeight(1)
          Toggle({type:ToggleType.Switch,isOn:this.autoPip}).selectedColor(ACCENT).enabled(this.backgroundPlayback)
            .onChange((value: boolean): void => { this.autoPip = value; this.persist(); this.ensurePip().catch((): void => {}); this.syncPip(); })
        }.padding(18).width('100%').backgroundColor(CARD).borderRadius(24)
        Row() {
          Text('自动播放下一集').fontSize(15).fontColor(INK).layoutWeight(1)
          Toggle({type:ToggleType.Switch,isOn:this.autoNext}).selectedColor(ACCENT).onChange((value: boolean): void => { this.autoNext = value; this.persist(); })
        }.padding(18).width('100%').backgroundColor(CARD).borderRadius(24)
        Row({space:12}) {
          Column({space:4}) {
            Text('减少动效').fontSize(15).fontColor(INK).width('100%')
            Text('使用更安静的页面切换与反馈').fontSize(12).fontColor(MUTED).width('100%')
          }.layoutWeight(1)
          Toggle({type:ToggleType.Switch,isOn:this.reduceMotion}).selectedColor(ACCENT)
            .onChange((value: boolean): void => { this.reduceMotion = value; this.persist(); })
        }.padding(18).width('100%').backgroundColor(CARD).borderRadius(24)
        Column({space:12}) {
          Row() {
            Text('原生播放器去插播').fontSize(15).fontColor(INK).layoutWeight(1)
            Toggle({type:ToggleType.Switch,isOn:this.blockAds}).selectedColor(ACCENT).onChange((value: boolean): void => this.toggleAdFilter(value))
          }.width('100%')
          TextInput({text:this.prepareService,placeholder:'Crayon /api/player/prepare 的 HTTPS 地址'}).enableKeyboardOnFocus(false).type(InputType.URL).backgroundColor(BG)
            .onChange((value: string): void => { this.prepareService = value; })
          Button('保存服务地址',{type:ButtonType.Normal}).fontSize(13).borderRadius(12).backgroundColor(BG).fontColor(ACCENT)
            .onClick((): void => { if (validUrl(this.prepareService,true)) { this.persist(); this.notice('去插播服务已保存'); } else this.notice('请输入 HTTPS 服务地址'); })
          Text('使用你之前的 Crayon 服务过滤 HLS 清单，视频分片直连片源。仅处理识别出的插播分片，无法去除画面内嵌广告。')
            .fontSize(12).fontColor(MUTED).lineHeight(19).width('100%')
        }.padding(18).width('100%').backgroundColor(CARD).borderRadius(24)
        Column({space:8}) {
          Text('WTV  1.7.6 · MPV').fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK)
          Text('搜索、详情与片单使用鸿蒙原生页面。直链由原生播放器播放，网页线路由 ArkWeb 播放；部分验证和私有协议取决于线路本身。').fontSize(12).fontColor(MUTED).lineHeight(19)
        }.padding(18).width('100%')
        Column({space:12}) {
          Text('错误与播放日志').fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
          Text('闪退后重新打开应用，在这里导出。包含上次退出原因、系统提供的崩溃堆栈和播放步骤；仅保存在本机。')
            .fontSize(12).fontColor(MUTED).lineHeight(19).width('100%')
          Button('导出错误日志 TXT',{type:ButtonType.Normal}).fontSize(14).borderRadius(12).width('100%').backgroundColor(ACCENT)
            .onClick((): void => { this.exportErrorLog(); })
          Row({space:12}) {
            Button('复制日志',{type:ButtonType.Normal}).fontSize(13).backgroundColor(FIELD).fontColor(INK).layoutWeight(1)
              .onClick((): void => { this.copyPlaybackDiagnostics(); })
            Button('清空日志',{type:ButtonType.Normal}).fontSize(13).backgroundColor(FIELD).fontColor(MUTED).layoutWeight(1)
              .onClick((): void => this.clearErrorLog())
          }.width('100%')
        }.padding(18).width('100%').backgroundColor(CARD).borderRadius(24)
      }.width('100%').padding({left:20,right:20,top:this.getUIContext().px2vp(this.safeTopPx)+64,bottom:this.getUIContext().px2vp(this.safeBottomPx)+88}).constraintSize({maxWidth:760})
    }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }
  @Builder
  endpointsPage() {
    HdsNavDestination() {
      Scroll() {
        Column({space:14}) {
          Row({space:10}) {
            Button({type:ButtonType.Circle}) { Image($r('app.media.nav_back')).width(22).height(22) }
              .width(40).height(40).backgroundColor(FIELD).accessibilityText('返回')
              .onClick((): void => { this.nav.pop(!this.reduceMotion); })
            Text('接口设置').fontSize(21).fontWeight(FontWeight.Bold).fontColor(INK)
          }.width('100%').margin({bottom:6})
          Column({space:12}) {
            Text('WTV 站点同步').fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
            TextInput({text:this.site,placeholder:'https://你的站点'}).enableKeyboardOnFocus(false).type(InputType.URL).onChange((value: string): void => { this.site = value; }).backgroundColor(BG)
            Button(this.syncing ? '同步中…' : '同步搜索源与线路').width('100%').backgroundColor(ACCENT).enabled(!this.syncing && this.ready).onClick((): void => { this.syncSite(); })
          }.padding(18).backgroundColor(CARD).borderRadius(24)
          Row() {
            Text('搜索接口').fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
            Button('＋ 添加').fontSize(13).fontColor(ACCENT).backgroundColor(CARD).onClick((): void => this.edit('search'))
          }.width('100%').margin({top:4})
          ForEach(this.sources,(item: Endpoint) => { this.endpointCard(item,'search') },(item: Endpoint): string => item.id)
          Row() {
            Text('解析接口').fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
            Button('＋ 添加').fontSize(13).fontColor(ACCENT).backgroundColor(CARD).onClick((): void => this.edit('parser'))
          }.width('100%').margin({top:10})
          ForEach(this.parsers,(item: Endpoint) => { this.endpointCard(item,'parser') },(item: Endpoint): string => item.id)
        }.padding({left:20,right:20,top:this.getUIContext().px2vp(this.safeTopPx)+8,bottom:this.getUIContext().px2vp(this.safeBottomPx)+24})
          .width('100%').constraintSize({maxWidth:760})
      }.height('100%').width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }.hideTitleBar(true).backgroundColor(BG)
      .systemTransition(this.reduceMotion ? NavigationSystemTransitionType.NONE : NavigationSystemTransitionType.CONTENT)
      .onBackPressed((): boolean => false)
  }
  @Builder
  endpointEditor() {
    Scroll() {
      Column({space:18}) {
        Text(this.editKind === 'search' ? '搜索接口' : '解析与播放器接口').fontSize(22).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
        TextInput({text:this.editName,placeholder:'接口名称'}).enableKeyboardOnFocus(false).maxLength(60).onChange((text: string): void => { this.editName = text; }).backgroundColor(FIELD).borderRadius(16)
        if (this.editKind === 'search') {
          Select([{value:'WTV 站点 API'},{value:'VideoSearch 五平台 API'},{value:'MacCMS JSON / XML 采集 API'}])
            .selected(this.editType).value(['WTV 站点 API','VideoSearch 五平台 API','MacCMS JSON / XML 采集 API'][this.editType])
            .onSelect((index: number): void => { this.editType = index; }).width('100%')
        } else {
          Select([{value:'JSON 解析 → 原生播放'},{value:'网页解析 / 网页播放器'}]).selected(this.editType)
            .value(['JSON 解析 → 原生播放','网页解析 / 网页播放器'][this.editType]).width('100%')
            .onSelect((index: number): void => { this.editType = index; })
        }
        TextInput({text:this.editUrl,placeholder:this.editKind === 'search' ? 'https://example.com/api.php/provide/vod/' : 'https://example.com/parse?url={url}'})
          .enableKeyboardOnFocus(false)
          .type(InputType.URL).onChange((text: string): void => { this.editUrl = text; }).backgroundColor(FIELD).borderRadius(16)
        if (this.editKind === 'search' || this.editType === 0) {
          TextInput({text:this.editToken,placeholder:'可选：Bearer 令牌'}).enableKeyboardOnFocus(false).type(InputType.Password).maxLength(500)
            .onChange((text: string): void => { this.editToken = text; }).backgroundColor(FIELD).borderRadius(16)
        }
        Text(this.editKind === 'search' ? 'WTV 填站点根地址；VideoSearch 填 API 根地址；MacCMS 填完整 JSON/XML 采集地址。添加后即可在发现页切换。' :
          this.editType === 1 ? '填入网页播放器 / 解析页面地址，例如 https://example.com/?url={url}。影片地址会自动编码并传入网页。' :
          '使用 GET 请求。{url} 自动替换为编码后的影片地址，也支持以 ?url= 或 ?v= 结尾。响应支持 {"url":"https://…"}、play_url、playUrl，或 data 下的同名字段。')
          .fontSize(13).fontColor(MUTED).lineHeight(22).width('100%')
        if (this.editorError) { Text(this.editorError).fontSize(13).fontColor('#C04444').width('100%') }
        Button('保存接口',{type:ButtonType.Normal}).borderRadius(16).width('100%').height(46).backgroundColor(ACCENT).onClick((): void => this.saveEndpoint())
        Button('取消',{type:ButtonType.Normal}).borderRadius(16).width('100%').backgroundColor(BG).fontColor(MUTED).onClick((): void => { this.sheet = false; })
      }.padding(24).width('100%')
    }.width('100%').height('100%').backgroundColor(CARD)
  }
  @Builder
  destination(name: string) {
    if (name === 'detail') { this.detailPage() }
    else if (name === 'endpoints') { this.endpointsPage() }
  }
  build() {
    WithTheme({theme:APP_THEME}) {
      Stack({alignContent:Alignment.TopStart}) {
        HdsNavigation(this.nav) {
      HdsTabs({barPosition:BarPosition.End,controller:this.tabs,index:this.tab}) {
        TabContent() { this.discover() }.tabBar(this.tabLabel('搜索',0))
        TabContent() { this.playerPage() }.tabBar(this.tabLabel('播放',1))
        TabContent() { this.libraryPage() }.tabBar(this.tabLabel('片单',2))
        TabContent() { this.settingsPage() }.tabBar(this.tabLabel('设置',3))
      }.vertical(false).barMode(BarMode.Fixed).barOverlap(true).barHeight(this.keyboardVisible || this.fullscreen || this.webFullscreen ? 0 : 56).scrollable(false)
        .barFloatingStyle({barSideMargin:24,barBottomMargin:this.getUIContext().px2vp(this.safeBottomPx)+10,barWidth:{mediumWidth:360,largeWidth:400},
          gradientMask:{maskColor:Color.Transparent,maskHeight:0},
          systemMaterialEffect:{materialType:this.tabMaterial,materialLevel:hdsMaterial.MaterialLevel.ADAPTIVE},thermoCtrl:true})
        .animationDuration(this.reduceMotion ? 0 : 220).onChange((index: number): void => this.changeTab(index))
        .onTabBarClick((index: number): void => this.repeatTab(index)).backgroundColor(Color.Transparent).width('100%').height('100%')
    }.id('wtv-root-navigation').hideTitleBar(this.fullscreen || this.webFullscreen).hideBackButton(true).titleMode(HdsNavigationTitleMode.MINI)
      .titleBar({
        avoidLayoutSafeArea:true,enableComponentSafeArea:false,
        padding:{start:LengthMetrics.vp(20),end:LengthMetrics.vp(20)},
        content:{title:{mainTitle:['搜索','播放','片单','设置'][this.tab],mainTitleSize:TitleSize.TITLE_ML}},
        style:{
          scrollEffectOpts:{enableScrollEffect:true,scrollEffectType:ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
            blurEffectiveStartOffset:LengthMetrics.vp(0),blurEffectiveEndOffset:LengthMetrics.vp(56)},
          originalStyle:{backgroundStyle:{backgroundColor:Color.Transparent,blurRadius:0},contentStyle:{titleStyle:{mainTitleColor:INK}}},
          scrollEffectStyle:{backgroundStyle:{backgroundColor:BG,blurRadius:20},contentStyle:{titleStyle:{mainTitleColor:INK}}},
          systemMaterialEffect:{materialType:this.tabMaterial,materialLevel:hdsMaterial.MaterialLevel.ADAPTIVE},thermoCtrl:true
        }
      })
      .bindToScrollable([[this.discoverScroll,this.playerScroll,this.libraryScroll,this.settingsScroll][this.tab]])
      .mode(NavigationMode.Stack).navDestination(this.destination)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],[LayoutSafeAreaEdge.TOP,LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor(BG).width('100%').height('100%').padding({
        left:this.fullscreen || this.webFullscreen ? 0 : this.getUIContext().px2vp(this.safeLeftPx),right:this.fullscreen || this.webFullscreen ? 0 : this.getUIContext().px2vp(this.safeRightPx)})
      .bindSheet($$this.sheet,this.endpointEditor(),{height:SheetSize.LARGE,showClose:true,backgroundColor:CARD})
      }.backgroundColor(this.fullscreen || this.webFullscreen ? '#000000' : BG).width('100%').height(LayoutPolicy.matchParent)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM],[LayoutSafeAreaEdge.TOP,LayoutSafeAreaEdge.BOTTOM])
    }
  }
}
