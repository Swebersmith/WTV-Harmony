export interface Endpoint {
  id: string;
  name: string;
  url: string;
  type: string;
  apiKey: string;
  enabled: boolean;
  searchProtocol?: string;
}
export interface Movie {
  id: string;
  title: string;
  platform: string;
  year: string;
  cover: string;
  overview: string;
  remarks: string;
  url: string;
  detail_url: string;
  sourceId: string;
}
export interface Episode {
  title: string;
  url: string;
  episode_type?: string;
  episode_number?: number;
}
export interface Playlist { id: string; name: string; episodes: Episode[]; }
export interface Detail { series: Movie; playlists: Playlist[]; episodes: Episode[]; }
export interface WatchRecord { movie: Movie; episode: Episode; seconds: number; updated: number; }
export interface SearchResult { results: Movie[]; hasMore: boolean; partial: boolean; }
export interface Settings { site: string; searches: Endpoint[]; parsers: Endpoint[]; autoNext: boolean; schemaVersion?: number; blockAds?: boolean; prepareService?: string; reduceMotion?: boolean; backgroundPlayback?: boolean; autoPip?: boolean; }
export interface PlaybackTarget { kind: string; url: string; }
export interface Library { favorites: Movie[]; records: WatchRecord[]; queries: string[]; }
export const PLATFORMS: string[] = ['tencent','iqiyi','youku','mango','bilibili'];
export const PLATFORM_NAMES: string[] = ['腾讯视频','爱奇艺','优酷','芒果 TV','哔哩哔哩'];
export function emptyMovie(): Movie {
  return { id:'',title:'链接播放',platform:'',year:'',cover:'',overview:'',remarks:'',url:'',detail_url:'',sourceId:'site-default' };
}
export function defaults(): Settings {
  return {
    site:'https://wtv.webber.qzz.io',
    searches:[{id:'site-default',name:'WTV 五平台搜索',url:'https://wtv.webber.qzz.io',type:'wtv',apiKey:'',enabled:true}],
    parsers:[{id:'web-lx',name:'LX 解析',url:'https://jx.lxyy.club/index.php?url=',type:'web',apiKey:'',enabled:true},
      {id:'web-qige',name:'七哥解析',url:'https://jx.202617.xyz/tv.php?url=',type:'web',apiKey:'',enabled:true}],
    autoNext:true,schemaVersion:3,
    blockAds:true,prepareService:'https://crap.webber.qzz.io/api/player/prepare'
  };
}
export function movieKey(m: Movie): string { return `${m.sourceId}|${m.platform}|${m.id || m.detail_url || m.url}`; }
export function officialSearch(source?: Endpoint): boolean {
  if (!source) return false;
  if (source.searchProtocol) return source.searchProtocol === 'videosearch';
  return source.type === 'videosearch' || source.type === 'wtv' || source.type === 'wtv:default';
}
export function episodeLabel(episode: Episode, title: string, index: number): string {
  const full = clean(episode.title || '');
  if (!full) return `第 ${index+1} 集`;
  if (title && full.startsWith(title)) {
    const suffix = full.slice(title.length).replace(/^[\s·:：_—-]+/,'').trim();
    if (suffix && (/^(第|\d|正片|预告|花絮|幕后|特辑|彩蛋|番外|上|下|中|EP|HD|BD)/i.test(suffix) || /[\s·:：_—-]$/.test(full.slice(0,title.length+1)))) return suffix;
  }
  return full;
}
export function webNavigationAllowed(value: string, mainFrame: boolean = true): boolean {
  return validUrl(value) || (!mainFrame && value === 'about:blank');
}
export function validUrl(value: string, httpsOnly: boolean = false): boolean {
  // No script schemes, credentials, whitespace or empty hosts. User-configured HTTP is allowed for local APIs.
  return (httpsOnly ? /^https:\/\//i : /^https?:\/\//i).test(value) &&
    /^https?:\/\/[^\s\/@?#:]+(?::\d+)?(?:[/?#][^\s]*)?$/i.test(value) && value.length <= 8192;
}
export function mediaUrl(value: string): boolean { return validUrl(value) && /\.(m3u8|mp4|m4v|mpd|webm|mov)(?:[?#]|$)/i.test(value); }
export function clean(value: string): string { return value.replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim().slice(0,6000); }
export function withQuery(base: string, key: string, value: string): string {
  const hash = base.indexOf('#');
  let url = hash >= 0 ? base.slice(0,hash) : base;
  const re = new RegExp(`([?&])${key}=[^&]*`,'g');
  url = url.replace(re, (_match: string, prefix: string): string => `${prefix}${key}=${encodeURIComponent(value)}`);
  return new RegExp(`[?&]${key}=`).test(url) ? url : `${url}${url.includes('?') ? '&' : '?'}${key}=${encodeURIComponent(value)}`;
}
export function parserRequest(endpoint: string, source: string): string {
  if (endpoint.includes('{url}')) return endpoint.split('{url}').join(encodeURIComponent(source));
  if (/[?&][^=&]+=$/.test(endpoint)) return endpoint + encodeURIComponent(source);
  return withQuery(endpoint,'url',source);
}
