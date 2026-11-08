/**
 * Copyright (c) 2026 Bao Han <erbws@qq.com>
 */

type MpvNode =
  | string
  | number
  | boolean
  | ArrayBuffer
  | MpvNode[]
  | Map<string, MpvNode>

export declare class NativePlayer {
  constructor()

  create(): void

  initialize(): void

  destroy(): void

  attachSurface(surface: string): void

  detachSurface(): void

  command(commands: Array<string>): void

  commandWithReturn(commands: Array<string>): MpvNode

  loadFile(url: string, options: Map<string, string>): void

  requestLogMessages(level: string): void

  setOptionString(option: string, value: string): void

  getProperty(property: string): number

  getPropertyBool(property: string): boolean

  getPropertyString(property: string): string

  setPropertyInt(property: string, value: number): void

  setPropertyDouble(property: string, value: number): void

  setPropertyBool(property: string, value: boolean): void

  setPropertyString(property: string, value: string): void

  observeProperty(property: string, format: number): void
}

export class JSBind {
  static bindFunction: (name: string, func: Function) => number;

  static unbindFunction: (name: string) => number;

  static initTaskRunner: (name: string) => void;
}
