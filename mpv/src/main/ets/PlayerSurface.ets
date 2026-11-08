/**
 * Copyright (C) 2025 Bao Han <erbws@qq.com>
 */

import { Player } from './Player';

@ComponentV2
export struct PlayerSurface {
  @Param @Require player: Player;
  @Param ignoreSafeArea: boolean = true;
  @Param radius: Length | BorderRadiuses | LocalizedBorderRadiuses = 0;

  build() {
    XComponent({
      type: XComponentType.SURFACE,
      controller: this.player,
    })
      .width(LayoutPolicy.matchParent)
      .height(LayoutPolicy.matchParent)
      .borderRadius(this.radius)
      .ignoreLayoutSafeArea(this.ignoreSafeArea ? undefined : [], this.ignoreSafeArea ? undefined : [])
  }
}
