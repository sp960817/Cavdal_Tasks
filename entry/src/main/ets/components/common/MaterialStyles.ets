import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';

// System materials are supported by sheets on API 26. Keep the API 24 path
// independent and do not mask the native material with an opaque background.
export function taskSheetOptions(onDisappear: () => void = (): void => {}): SheetOptions {
  if (deviceInfo.apiAvailable('26.0.0')) {
    return {
      detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        colorInvert: false
      }),
      showClose: false,
      onDisappear
    };
  }
  return {
    detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
    backgroundColor: $r('app.color.surface_translucent'),
    blurStyle: BlurStyle.COMPONENT_THIN,
    showClose: false,
    onDisappear
  };
}
