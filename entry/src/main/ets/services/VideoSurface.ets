import { NodeController, FrameNode, typeNode, UIContext } from '@kit.ArkUI';

// Follow the official typeNode preview/PiP pattern: move one node, not the MPV output.
export class VideoSurface extends NodeController {
  readonly controller: XComponentController;
  private content?: typeNode.XComponent;
  private host?: FrameNode;
  private inPip: boolean = false;
  constructor(controller: XComponentController) { super(); this.controller = controller; }
  getContent(context: UIContext): typeNode.XComponent {
    if (!this.content) this.content = typeNode.createNode(context,'XComponent',{
      type:XComponentType.SURFACE,controller:this.controller
    });
    return this.content;
  }
  makeNode(context: UIContext): FrameNode {
    this.host = new FrameNode(context);
    this.host.commonAttribute.width('100%').height('100%');
    this.getContent(context).commonAttribute.width('100%').height('100%');
    if (!this.inPip) this.attachToPage();
    return this.host;
  }
  setInPip(value: boolean): void {
    if (this.inPip === value) return;
    this.inPip = value;
    if (value) {
      if (this.content && this.content.getParent() === this.host) this.host?.removeChild(this.content);
    }
    else this.attachToPage();
  }
  private attachToPage(): void {
    if (!this.content || !this.host || this.content.getParent() === this.host) return;
    this.content.getParent()?.removeChild(this.content);
    this.host.appendChild(this.content);
  }
  dispose(): void {
    this.content?.getParent()?.removeChild(this.content);
    this.content?.dispose(); this.host?.dispose();
    this.content = undefined; this.host = undefined;
  }
}
