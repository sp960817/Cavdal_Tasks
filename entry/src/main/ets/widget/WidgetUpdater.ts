import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsStore, TaskRepository } from '../data/TaskRepository';

const WIDGET_PREF_NAME = 'cavdal_widget_forms';
const FORM_IDS_KEY = 'formIds';
const TEXT_COLOR_KEY = 'textColor';
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'CavdalWidgetUpdate';

interface FormTarget {
  formId: string;
  dimension?: number;
  textColor?: string;
}

function parseFormIds(value: string): string[] {
  try {
    return JSON.parse(value) as string[];
  } catch (_err) {
    return [];
  }
}

function errorText(err: Object): string {
  try {
    return JSON.stringify(err);
  } catch (_jsonErr) {
    return `${err}`;
  }
}

export class WidgetUpdater {
  private static async formIds(context: common.Context): Promise<string[]> {
    try {
      const pref = await preferences.getPreferences(context, WIDGET_PREF_NAME);
      return parseFormIds(`${await pref.get(FORM_IDS_KEY, '[]')}`);
    } catch (err) {
      console.error(`[WidgetUpdater] formIds failed: ${errorText(err)}`);
      return [];
    }
  }

  private static async saveFormIds(context: common.Context, formIds: string[]): Promise<void> {
    try {
      const pref = await preferences.getPreferences(context, WIDGET_PREF_NAME);
      await pref.put(FORM_IDS_KEY, JSON.stringify(formIds));
      await pref.flush();
    } catch (err) {
      console.error(`[WidgetUpdater] saveFormIds failed: ${errorText(err)}`);
      throw new Error(`saveFormIds failed: ${errorText(err)}`);
    }
  }

  static async savedTextColor(context: common.Context): Promise<string | undefined> {
    try {
      const pref = await preferences.getPreferences(context, WIDGET_PREF_NAME);
      const color = `${await pref.get(TEXT_COLOR_KEY, '')}`;
      return color.length > 0 ? color : undefined;
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'load text color failed: %{public}s', errorText(err));
      return undefined;
    }
  }

  static async registerForm(context: common.Context, formId: string, textColor?: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      const pref = await preferences.getPreferences(context, WIDGET_PREF_NAME);
      const formIds = parseFormIds(`${await pref.get(FORM_IDS_KEY, '[]')}`);
      if (formIds.indexOf(formId) < 0) {
        formIds.push(formId);
        await pref.put(FORM_IDS_KEY, JSON.stringify(formIds));
      }
      if (textColor !== undefined && textColor.length > 0) {
        await pref.put(TEXT_COLOR_KEY, textColor);
      }
      await pref.flush();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'register form failed: %{public}s', errorText(err));
      throw new Error(`registerForm failed: ${errorText(err)}`);
    }
  }

  static async unregisterForm(context: common.Context, formId: string): Promise<void> {
    const formIds = await WidgetUpdater.formIds(context);
    await WidgetUpdater.saveFormIds(context, formIds.filter((id: string) => id !== formId));
  }

  private static async runningForms(context: common.Context): Promise<FormTarget[]> {
    const textColor = await WidgetUpdater.savedTextColor(context);
    try {
      const running = await formProvider.getPublishedRunningFormInfos();
      const targets: FormTarget[] = [];
      for (let i = 0; i < running.length; i++) {
        const info: formInfo.RunningFormInfo = running[i];
        if (info.formName !== 'cavdal_tasks' || info.abilityName !== 'EntryFormAbility') {
          continue;
        }
        targets.push({ formId: info.formId, dimension: info.dimension, textColor });
      }
      if (targets.length > 0) {
        await WidgetUpdater.saveFormIds(context, targets.map((target: FormTarget) => target.formId));
        return targets;
      }
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'get running forms failed: %{public}s', errorText(err));
    }

    // Keep the registry as a fallback if FormManager is temporarily unavailable.
    const storedIds = await WidgetUpdater.formIds(context);
    return storedIds.map((formId: string) => ({ formId, textColor } as FormTarget));
  }

  static async updateAllForms(context: common.Context): Promise<void> {
    const settings = await new SettingsStore(context).load();
    const payload = await new TaskRepository(context).widgetPayload(settings.lastSyncAt);
    const targets = await WidgetUpdater.runningForms(context);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'update style=%{public}s forms=%{public}d',
      settings.widgetBlurStyle, targets.length);
    for (let i = 0; i < targets.length; i++) {
      const target = targets[i];
      const bindingData: Record<string, string> = {
        tasksJson: JSON.stringify(payload.tasks),
        pendingCount: `${payload.pendingCount}`,
        lastSyncText: payload.lastSyncText,
        widgetBlurStyle: settings.widgetBlurStyle
      };
      if (target.dimension !== undefined) {
        bindingData['formDimension'] = `${target.dimension}`;
      }
      if (target.textColor !== undefined) {
        bindingData['textColor'] = target.textColor;
      }
      const data = formBindingData.createFormBindingData(bindingData);
      try {
        await formProvider.updateForm(target.formId, data);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'updated id=%{public}s dimension=%{public}s',
          target.formId, `${target.dimension ?? ''}`);
      } catch (err) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'update id=%{public}s failed: %{public}s',
          target.formId, errorText(err));
      }
    }
  }
}
