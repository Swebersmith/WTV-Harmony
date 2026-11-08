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
