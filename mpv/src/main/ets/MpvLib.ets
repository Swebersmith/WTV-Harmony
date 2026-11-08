/**
 * Copyright (C) 2025 Bao Han <erbws@qq.com>
 */

import libmpv from 'libmpv_wrapper.so';

export type MpvNode =
  | string
  | number
  | boolean
  | ArrayBuffer
  | MpvNode[]
  | Map<string, MpvNode>

export interface EventObserver {
  onPropertyChanged(property: string, value?: number | boolean | string): void;

  onEvent(id: number, name: string, detail?: string): void;
}

export interface LogObserver {
  onLogMessage(prefix: string, level: string, msg: string): void;
}

export enum MpvFormat {
  MPV_FORMAT_NONE = 0,
  MPV_FORMAT_STRING = 1,
  MPV_FORMAT_OSD_STRING = 2,
  MPV_FORMAT_FLAG = 3,
  MPV_FORMAT_INT64 = 4,
  MPV_FORMAT_DOUBLE = 5,
  MPV_FORMAT_NODE = 6,
  MPV_FORMAT_NODE_ARRAY = 7,
  MPV_FORMAT_NODE_MAP = 8,
  MPV_FORMAT_BYTE_ARRAY = 9,
}

export enum MpvEvent {
  MPV_EVENT_NONE = 0,
  MPV_EVENT_SHUTDOWN = 1,
  MPV_EVENT_LOG_MESSAGE = 2,
  MPV_EVENT_GET_PROPERTY_REPLY = 3,
  MPV_EVENT_SET_PROPERTY_REPLY = 4,
  MPV_EVENT_COMMAND_REPLY = 5,
  MPV_EVENT_START_FILE = 6,
  MPV_EVENT_END_FILE = 7,
  MPV_EVENT_FILE_LOADED = 8,
  /** @deprecated */
  MPV_EVENT_IDLE = 11,
  /** @deprecated */
  MPV_EVENT_TICK = 14,
  MPV_EVENT_CLIENT_MESSAGE = 16,
  MPV_EVENT_VIDEO_RECONFIG = 17,
  MPV_EVENT_AUDIO_RECONFIG = 18,
  MPV_EVENT_SEEK = 20,
  MPV_EVENT_PLAYBACK_RESTART = 21,
  MPV_EVENT_PROPERTY_CHANGE = 22,
  MPV_EVENT_QUEUE_OVERFLOW = 24,
  MPV_EVENT_HOOK = 25,
}

export class MpvLib {
  private observers: EventObserver[] = [];
  private logObservers: LogObserver[] = [];
  private ctx: libmpv.NativePlayer = new libmpv.NativePlayer();

  create(): void {
    this.ctx.create();
  }

  initialize(): void {
    this.ctx.initialize();
  }

  destroy(): void {
    this.ctx.destroy();
  }

  attachSurface(surfaceId: string): void {
    this.ctx.attachSurface(surfaceId);
  }

  detachSurface(): void {
    this.ctx.detachSurface();
  }

  command(cmds: Array<string>): number {
    return this.ctx.command(cmds);
  }

  commandWithReturn(cmds: Array<string>): MpvNode {
    return this.ctx.commandWithReturn(cmds);
  }

  loadFile(url: string, options: Map<string, string>): void {
    this.ctx.loadFile(url, options);
  }

  requestLogMessages(level: string): void {
    this.ctx.requestLogMessages(level);
  }

  setOptionString(option: string, value: string): void {
    this.ctx.setOptionString(option, value);
  }

  getProperty(property: string): number {
    return this.ctx.getProperty(property);
  }

  getPropertyBool(property: string): boolean {
    return this.ctx.getPropertyBool(property);
  }

  getPropertyString(property: string): string {
    return this.ctx.getPropertyString(property);
  }

  setProperty(property: string, value: number | boolean | string): void {
    if (typeof value === "number") {
      if (Number.isInteger(value)) {
        this.ctx.setPropertyInt(property, value);
      } else {
        this.ctx.setPropertyDouble(property, value);
      }
    } else if (typeof value === "boolean") {
      this.ctx.setPropertyBool(property, value);
    } else {
      this.ctx.setPropertyString(property, value);
    }
  }

  observeProperty(property: string, format: MpvFormat): void {
    this.ctx.observeProperty(property, format);
  }

  addEventObserver(o: EventObserver) {
    this.observers.push(o);
  }

  removeEventObserver(o: EventObserver) {
    let index = this.observers.indexOf(o);
    if (index != -1) {
      this.observers.splice(index, 1);
    }
  }

  addLogObserver(o: LogObserver) {
    this.logObservers.push(o);
  }

  removeLogObserver(o: LogObserver) {
    let index = this.logObservers.indexOf(o);
    if (index != -1) {
      this.logObservers.splice(index, 1);
    }
  }

  registerEventCallback(): void {
    libmpv.JSBind.initTaskRunner("main");
    libmpv.JSBind.bindFunction("property", this.eventProperty);
    libmpv.JSBind.bindFunction("event", this.event);
  }

  registerLogCallback(): void {
    libmpv.JSBind.initTaskRunner("main");
    libmpv.JSBind.bindFunction("log", this.log);
  }

  removeEventCallbacks(): void {
    libmpv.JSBind.unbindFunction("property");
    libmpv.JSBind.unbindFunction("event");
  }

  removeLogCallback(): void {
    libmpv.JSBind.unbindFunction("log");
  }

  private eventProperty = (property: string, value?: number | boolean | string): void => {
    this.observers.forEach((o) => {
      o.onPropertyChanged(property, value);
    })
  }

  private event = (id: number, name: string, detail?: string): void => {
    this.observers.forEach((o) => {
      o.onEvent(id, name, detail);
    })
  }

  private log = (prefix: string, level: string, msg: string): void => {
    this.logObservers.forEach((o) => {
      o.onLogMessage(prefix, level, msg);
    })
  }
}
