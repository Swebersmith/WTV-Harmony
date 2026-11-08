/**
 * Copyright (C) 2026 Bao Han <erbws@qq.com>
 */

import { AudioParams } from "./AudioParams";
import { Chapter } from "./Chapter";
import { PlayerLog } from "./PlayerLog";
import { Track, Tracks } from "./Track";
import { Playlist } from "./Playlist";
import { PlaylistMode } from "./PlaylistMode";
import { VideoParams } from "./VideoParams";
import { Stream } from "../utils/Stream";

function samePlaylist(first: Playlist, second: Playlist): boolean {
  if (first.index !== second.index || first.medias.length !== second.medias.length) {
    return false;
  }
  for (let index = 0; index < first.medias.length; index++) {
    if (first.medias[index].uri !== second.medias[index].uri) {
      return false;
    }
  }
  return true;
}

function sameTrack(first: Track, second: Track): boolean {
  return first.video.id === second.video.id &&
    first.video.codec === second.video.codec &&
    first.video.lang === second.video.lang &&
    first.video.title === second.video.title &&
    first.audio.id === second.audio.id &&
    first.audio.codec === second.audio.codec &&
    first.audio.lang === second.audio.lang &&
    first.audio.title === second.audio.title &&
    first.subs.id === second.subs.id &&
    first.subs.codec === second.subs.codec &&
    first.subs.lang === second.subs.lang &&
    first.subs.title === second.subs.title;
}

function sameTracks(first: Tracks, second: Tracks): boolean {
  if (
    first.video.length !== second.video.length ||
    first.audio.length !== second.audio.length ||
    first.subs.length !== second.subs.length
  ) {
    return false;
  }
  for (let index = 0; index < first.video.length; index++) {
    if (
      first.video[index].id !== second.video[index].id ||
      first.video[index].codec !== second.video[index].codec ||
      first.video[index].lang !== second.video[index].lang ||
      first.video[index].title !== second.video[index].title
    ) {
      return false;
    }
  }
  for (let index = 0; index < first.audio.length; index++) {
    if (
      first.audio[index].id !== second.audio[index].id ||
      first.audio[index].codec !== second.audio[index].codec ||
      first.audio[index].lang !== second.audio[index].lang ||
      first.audio[index].title !== second.audio[index].title
    ) {
      return false;
    }
  }
  for (let index = 0; index < first.subs.length; index++) {
    if (
      first.subs[index].id !== second.subs[index].id ||
      first.subs[index].codec !== second.subs[index].codec ||
      first.subs[index].lang !== second.subs[index].lang ||
      first.subs[index].title !== second.subs[index].title
    ) {
      return false;
    }
  }
  return true;
}

function sameChapters(first: Chapter[], second: Chapter[]): boolean {
  if (first.length !== second.length) {
    return false;
  }
  for (let index = 0; index < first.length; index++) {
    if (
      first[index].title !== second[index].title ||
      first[index].time !== second[index].time
    ) {
      return false;
    }
  }
  return true;
}

function sameLog(first: PlayerLog, second: PlayerLog): boolean {
  return first.prefix === second.prefix &&
    first.level === second.level &&
    first.text === second.text;
}

export class PlayerStream {
  /**
   * Currently opened files.
   */
  playlist: Stream<Playlist> = new Stream<Playlist>(samePlaylist);
  /**
   * Whether player is playing.
   */
  playing: Stream<boolean> = new Stream<boolean>((first: boolean, second: boolean) => first === second);
  /**
   * Whether end of file reached.
   */
  eof: Stream<boolean> = new Stream<boolean>((first: boolean, second: boolean) => first === second);
  /**
   * Current playback duration in seconds (0.000).
   */
  duration: Stream<number> = new Stream<number>((first: number, second: number) => first === second);
  /**
   * Current playback position in seconds (0.000).
   */
  position: Stream<number> = new Stream<number>((first: number, second: number) => first === second);
  /**
   * Current volume (0-130).
   */
  volume: Stream<number> = new Stream<number>((first: number, second: number) => first === second);
  /**
   * Current playback speed.
   */
  speed: Stream<number> = new Stream<number>((first: number, second: number) => first === second);
  /**
   * Whether playback is paused because of waiting for the cache.
   */
  buffering: Stream<boolean> = new Stream<boolean>((first: boolean, second: boolean) => first === second);
  /**
   * The percentage (0-100) of the cache fill status until the player will unpause. (related to buffering).
   */
  bufferingPercentage: Stream<number> =
    new Stream<number>((first: number, second: number) => first === second);
  /**
   * Current buffer position in seconds.
   */
  buffer: Stream<number> = new Stream<number>((first: number, second: number) => first === second);
  /**
   * Current playlist or file loop mode.
   */
  playlistMode: Stream<PlaylistMode> = new Stream<PlaylistMode>();
  /**
   * Currently selected video, audio and subtitle track.
   */
  track: Stream<Track> = new Stream<Track>(sameTrack);
  /**
   * Available video, audio and subtitle tracks.
   */
  tracks: Stream<Tracks> = new Stream<Tracks>(sameTracks);
  /**
   * Available chapters.
   */
  chapters: Stream<Chapter[]> = new Stream<Chapter[]>(sameChapters);
  /**
   * Video params.
   */
  videoParams: Stream<VideoParams> = new Stream<VideoParams>();
  /**
   * Video bitrate.
   */
  videoBitrate: Stream<number> = new Stream<number>((first: number, second: number) => first === second);
  /**
   * Audio params.
   */
  audioParams: Stream<AudioParams> = new Stream<AudioParams>();
  /**
   * Audio bitrate.
   */
  audioBitrate: Stream<number> = new Stream<number>((first: number, second: number) => first === second);
  /**
   * Stream of mpv log.
   */
  log: Stream<PlayerLog> = new Stream<PlayerLog>(sameLog);
  /**
   * Internal error stream.
   */
  error: Stream<string> = new Stream<string>();

  /**
   * Cancel all listeners
   */
  destroy(): void {
    this.playlist.close();
    this.playing.close();
    this.eof.close();
    this.duration.close();
    this.position.close();
    this.volume.close();
    this.speed.close();
    this.buffering.close();
    this.bufferingPercentage.close();
    this.buffer.close();
    this.playlistMode.close();
    this.track.close();
    this.tracks.close();
    this.chapters.close();
    this.videoParams.close();
    this.videoBitrate.close();
    this.audioParams.close();
    this.audioBitrate.close();
    this.log.close();
    this.error.close();
  }
}
