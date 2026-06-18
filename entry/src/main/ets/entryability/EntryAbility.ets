import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;

  private updateSystemBars(isDark: boolean): void {
    if (this.mainWindow === undefined) {
      return;
    }
    const contentColor = isDark ? '#FFFFFFFF' : '#FF111318';
    this.mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: contentColor,
      navigationBarContentColor: contentColor
    });
  }

  private refreshSystemBars(): void {
    const colorMode = this.context.resourceManager.getConfigurationSync().colorMode;
    this.updateSystemBars(colorMode === resourceManager.ColorMode.DARK);
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      this.mainWindow = windowStage.getMainWindowSync();
      this.mainWindow.setWindowLayoutFullScreen(true);
      this.refreshSystemBars();
      try {
        const area = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        AppStorage.setOrCreate('statusBarHeight', area.topRect.height);
      } catch (_err) {
        AppStorage.setOrCreate('statusBarHeight', 0);
      }
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const colorMode = newConfig.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    this.updateSystemBars(colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    this.mainWindow = undefined;
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    this.refreshSystemBars();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
