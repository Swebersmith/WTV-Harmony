import { window } from '@kit.ArkUI';

export async function applySystemBars(win: window.Window, media: boolean = false): Promise<void> {
  const fullscreen = media || AppStorage.get<boolean>('mediaFullscreen') === true;
  const dark = fullscreen || AppStorage.get<boolean>('systemDark') === true;
  await win.setWindowSystemBarProperties({statusBarColor:'#00000000',navigationBarColor:'#00000000',
    statusBarContentColor:dark ? '#EDF5F4' : '#172C32',navigationBarContentColor:dark ? '#EDF5F4' : '#172C32'});
  // Hide both only for fullscreen media; normal pages keep transparent, legible system UI.
  await Promise.all([
    win.setSpecificSystemBarEnabled('status',!fullscreen),
    win.setSpecificSystemBarEnabled('navigationIndicator',!fullscreen)
  ]);
}

export function updateAvoidAreas(win: window.Window): void {
  try {
    const system = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const cutout = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    const gesture = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    AppStorage.setOrCreate('safeTopPx',Math.max(system.topRect.height,cutout.topRect.height));
    AppStorage.setOrCreate('safeBottomPx',Math.max(system.bottomRect.height,gesture.bottomRect.height,cutout.bottomRect.height));
    AppStorage.setOrCreate('safeLeftPx',Math.max(system.leftRect.width,cutout.leftRect.width));
    AppStorage.setOrCreate('safeRightPx',Math.max(system.rightRect.width,cutout.rightRect.width));
  } catch { /* Retain the last observed safe areas during a transient window change. */ }
}
