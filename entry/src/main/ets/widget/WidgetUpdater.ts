import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { SettingsStore, TaskRepository } from '../data/TaskRepository';

const WIDGET_PREF_NAME = 'cavdal_widget_forms';
const FORM_IDS_KEY = 'formIds';

function parseFormIds(value: string): string[] {
  try {
    return JSON.parse(value) as string[];
  } catch (_err) {
    return [];
  }
}

export class WidgetUpdater {
  private static async formIds(context: common.Context): Promise<string[]> {
    const pref = await preferences.getPreferences(context, WIDGET_PREF_NAME);
    return parseFormIds(`${await pref.get(FORM_IDS_KEY, '[]')}`);
  }

  private static async saveFormIds(context: common.Context, formIds: string[]): Promise<void> {
    const pref = await preferences.getPreferences(context, WIDGET_PREF_NAME);
    await pref.put(FORM_IDS_KEY, JSON.stringify(formIds));
    await pref.flush();
  }

  static async registerForm(context: common.Context, formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    const formIds = await WidgetUpdater.formIds(context);
    if (formIds.indexOf(formId) < 0) {
      formIds.push(formId);
      await WidgetUpdater.saveFormIds(context, formIds);
    }
  }

  static async unregisterForm(context: common.Context, formId: string): Promise<void> {
    const formIds = await WidgetUpdater.formIds(context);
    await WidgetUpdater.saveFormIds(context, formIds.filter((id: string) => id !== formId));
  }

  static async updateAllForms(context: common.Context): Promise<void> {
    const settings = await new SettingsStore(context).load();
    const payload = await new TaskRepository(context).widgetPayload(settings.lastSyncAt);
    const data = formBindingData.createFormBindingData({
      tasksJson: JSON.stringify(payload.tasks),
      pendingCount: `${payload.pendingCount}`,
      lastSyncText: payload.lastSyncText,
      widgetBlurStyle: settings.widgetBlurStyle
    });
    const formIds = await WidgetUpdater.formIds(context);
    for (let i = 0; i < formIds.length; i++) {
      try {
        await formProvider.updateForm(formIds[i], data);
      } catch (_err) {
      }
    }
  }
}
