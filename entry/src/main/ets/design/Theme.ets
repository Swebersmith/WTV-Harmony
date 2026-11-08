import { CustomTheme } from '@kit.ArkUI';

export const PAGE: Resource = $r('app.color.page_background');
export const SURFACE: Resource = $r('app.color.card_background');
export const FIELD: Resource = $r('app.color.field_background');
export const TEXT: Resource = $r('app.color.text_primary');
export const SECONDARY: Resource = $r('app.color.text_secondary');
export const EMPHASIS: Resource = $r('app.color.accent_foreground');
export const BRAND: string = '#167E6B';
export const APP_THEME: CustomTheme = {
  colors: {
    brand:BRAND,fontPrimary:TEXT,fontSecondary:SECONDARY,fontEmphasize:EMPHASIS,
    iconPrimary:TEXT,iconSecondary:SECONDARY,iconEmphasize:EMPHASIS,
    backgroundPrimary:PAGE,backgroundSecondary:SURFACE,compBackgroundPrimary:SURFACE,
    compBackgroundSecondary:FIELD,compBackgroundEmphasize:BRAND,interactiveActive:EMPHASIS
  }
};

@Component
export struct PageHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  build() {
    Column({space:7}) {
      Text('WTV  /  CINEMA').fontSize(10).fontWeight(FontWeight.Medium).letterSpacing(2).fontColor(EMPHASIS)
        .width('100%').accessibilityLevel('no')
      Text(this.title).fontSize(30).fontWeight(FontWeight.Bold).fontColor(TEXT).width('100%')
      Text(this.subtitle).fontSize(13).fontColor(SECONDARY).lineHeight(20).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({top:14,bottom:10})
  }
}
