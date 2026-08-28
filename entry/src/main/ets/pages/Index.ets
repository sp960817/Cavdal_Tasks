import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import notificationManager from '@ohos.notificationManager';
import { CalendarSource, TodoTask, WidgetBlurStyle } from '../model/TaskModels';
import { TaskRepository } from '../data/TaskRepository';
import { SyncService } from '../sync/SyncService';
import { parseDueAsBeijing } from '../formatters/DueTimeFormatter';
import { VTodoCodec } from '../caldav/VTodoCodec';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { SymbolGlyphModifier, curves, uiMaterial } from '@kit.ArkUI';
import { motion } from '@kit.MultimodalAwarenessKit';
import { TaskCards } from '../components/home/TaskCards';
import { WidgetAppearanceCard, widgetBlurLabel } from '../components/settings/WidgetAppearanceCard';
import { calculateHomeLayout, HomeLayoutMetrics } from '../utils/HomeLayout';

@Entry
@Component
struct Index {
  @State configured: boolean = false;
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State widgetBlurStyle: WidgetBlurStyle = 'thin';
  @State statusText: string = '正在载入';
  @State serverUrl: string = '';
  @State username: string = '';
  @State password: string = '';
  @State calendars: CalendarSource[] = [];
  @State selectedCalendarIndex: number = 0;
  @State tasks: TodoTask[] = [];
  @State completed: TodoTask[] = [];
  @State newTitle: string = '';
  @State newDescription: string = '';
  @State selectedDueDate: Date = new Date();
  @State selectedDueHour: number = new Date().getHours();
  @State selectedDueMinute: number = new Date().getMinutes();
  @State hasDue: boolean = false;
  @State reminderOption: string = '无';
  @State repeatOption: string = '无';
  @State settingPanel: string = '';
  @State showAddSheet: boolean = false;
  @State selectedTabIndex: number = 0;
  // API 26 Beta2 首次布局时会先按默认栏高测量一次；首屏完成后置 48，
  // 通过 barHeight 状态变化触发 bar 区域重排（而非重建整棵 Tabs），
  // 让原生 Tabs 在用户交互前按目标栏高重新测量。
  @State tabBarHeight: number = 47;
  private tabBarLayoutPassTriggered: boolean = false;
  @State showEditSheet: boolean = false;
  @State showSearch: boolean = false;
  @State showCompleted: boolean = false;
  @State completedUserOverride: boolean = true;
  @State homeViewportHeight: number = 0;
  @State searchQuery: string = '';
  @State editingTask: TodoTask | null = null;
  @State handednessEnabled: boolean = false;
  @State fabAlignRules: AlignRuleOption = {
    right: { anchor: '__container__', align: HorizontalAlign.End },
    bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
  };
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  private uiContext: UIContext = this.getUIContext();
  private context: common.UIAbilityContext = this.requireHostContext();
  // 统一使用应用级上下文，与桌面小组件共享同一份数据存储
  private repository: TaskRepository = new TaskRepository(this.context.getApplicationContext());
  private syncService: SyncService = new SyncService(this.context.getApplicationContext());
  private firstPageShow: boolean = true;
  private reminderNotificationPrompted: boolean = false;
  private hdsController: HdsTabsController = new HdsTabsController();
  private tabsController: TabsController = new TabsController();
  private handleHoldingHandChange: Callback<motion.HoldingHandStatus> = (status: motion.HoldingHandStatus) => {
    this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 288, 30) }, () => {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
          this.fabAlignRules = {
            left: { anchor: '__container__', align: HorizontalAlign.Start },
            bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
          };
        } else if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
          this.fabAlignRules = {
            right: { anchor: '__container__', align: HorizontalAlign.End },
            bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
          };
        }
      }
    });
  };
  private homeTabBar: BottomTabBarStyle = new BottomTabBarStyle({
    normal: new SymbolGlyphModifier($r('sys.symbol.checkmark_square'))
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('app.color.text_secondary')]),
    selected: new SymbolGlyphModifier($r('sys.symbol.checkmark_square'))
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('app.color.accent')])
  }, '首页').labelStyle({
    unselectedColor: $r('app.color.text_secondary'),
    selectedColor: $r('app.color.accent')
  });
  private settingsTabBar: BottomTabBarStyle = new BottomTabBarStyle({
    normal: new SymbolGlyphModifier($r('sys.symbol.gearshape'))
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('app.color.text_secondary')]),
    selected: new SymbolGlyphModifier($r('sys.symbol.gearshape'))
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([$r('app.color.accent')])
  }, '设置').labelStyle({
    unselectedColor: $r('app.color.text_secondary'),
    selectedColor: $r('app.color.accent')
  });
  private requireHostContext(): common.UIAbilityContext {
    const hostContext = this.uiContext.getHostContext();
    if (hostContext === undefined) {
      throw new Error('无法获取页面 Host Context');
    }
    return hostContext as common.UIAbilityContext;
  }

  private safeShowToast(message: string): void {
    try {
      this.uiContext.getPromptAction().showToast({ message });
    } catch (err) {
      console.error('Cavdal toast error', JSON.stringify(err));
    }
  }

  private taskHasReminder(task: TodoTask): boolean {
    return task.status !== 'completed' && task.due.length > 0 && VTodoCodec.detectReminder(task.rawIcs, task.due) !== '无';
  }

  private async ensureReminderNotifications(promptIfNeeded: boolean): Promise<boolean> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }
      if (!promptIfNeeded || this.reminderNotificationPrompted) {
        this.statusText = '系统通知未开启，待办提醒暂不可用';
        return false;
      }
      this.reminderNotificationPrompted = true;
      await notificationManager.requestEnableNotification(this.context);
      const rechecked = await notificationManager.isNotificationEnabled();
      if (rechecked) {
        this.safeShowToast('已开启应用通知');
        return true;
      }
      this.statusText = '系统通知未开启，待办提醒不会弹出';
      this.safeShowToast('请先开启应用通知，待办提醒才会弹出');
      return false;
    } catch (err) {
      this.statusText = `通知授权失败：${JSON.stringify(err)}`;
      console.error('Cavdal notification authorization error', JSON.stringify(err));
      return false;
    }
  }

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.unregisterHoldingHand();
  }

  private registerHoldingHand(): void {
    try {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        motion.on('holdingHandChanged', this.handleHoldingHandChange);
      }
    } catch (e) {
    }
  }

  private unregisterHoldingHand(): void {
    try {
      if (canIUse('SystemCapability.MultimodalAwareness.Motion')) {
        motion.off('holdingHandChanged', this.handleHoldingHandChange);
      }
    } catch (e) {
    }
  }

  private toggleHandedness(enabled: boolean): void {
    this.handednessEnabled = enabled;
    if (enabled) {
      this.registerHoldingHand();
    } else {
      this.unregisterHoldingHand();
      this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 288, 30) }, () => {
        this.fabAlignRules = {
          right: { anchor: '__container__', align: HorizontalAlign.End },
          bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
        };
      });
    }
    this.syncService.saveHandedness(enabled);
  }

  onPageShow(): void {
    if (this.firstPageShow) {
      this.firstPageShow = false;
      return;
    }
    if (this.configured) {
      this.syncNow();
    } else {
      this.refreshLists();
    }
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      const settings = await this.syncService.loadSettings();
      this.configured = settings.serverUrl.length > 0 && settings.calendarHref.length > 0;
      this.serverUrl = settings.serverUrl;
      this.username = settings.username;
      this.widgetBlurStyle = settings.widgetBlurStyle;
      this.handednessEnabled = settings.handednessEnabled;
      if (settings.handednessEnabled) {
        this.registerHoldingHand();
      }
      this.statusText = this.configured ? '准备同步' : '请配置 CalDAV Tasks 账号';
      await this.refreshLists();
      if (await this.ensureReminderNotifications(this.tasks.some((task: TodoTask) => this.taskHasReminder(task)))) {
        await this.syncService.syncLocalReminders();
      }
    } catch (err) {
      this.statusText = `启动加载失败：${JSON.stringify(err)}`;
    }
    this.loading = false;
    if (this.configured) {
      await this.syncNow();
    }
  }

  private scheduleTabBarLayoutPass(): void {
    if (!deviceInfo.apiAvailable('26.0.0') || !this.configured || this.tabBarLayoutPassTriggered) {
      return;
    }
    this.tabBarLayoutPassTriggered = true;
    // Beta2 首帧会忽略 barHeight 按默认栏高渲染（所以首帧"高一点"）。
    // 在 Tabs 挂载且首帧布局完成后（onAreaChange 回调）置目标栏高 48，
    // 让 bar 重排在首帧布局内完成，跳变不可感知。setTimeout 仅作兜底。
    this.tabBarHeight = 48;
    setTimeout(() => {
      if (this.configured) {
        this.tabBarHeight = 48;
      }
    }, 160);
  }

  private async refreshLists(): Promise<void> {
    try {
      this.tasks = await this.repository.activeTasks();
      this.completed = await this.repository.completedTasks();
    } catch (err) {
      this.statusText = `加载数据失败：${JSON.stringify(err)}`;
    }
  }

  private async discoverCalendars(): Promise<void> {
    if (this.serverUrl.length === 0 || this.username.length === 0 || this.password.length === 0) {
      this.safeShowToast('请填写服务器、用户名和密码');
      return;
    }
    this.loading = true;
    this.statusText = '正在发现 CalDAV 日历';
    try {
      this.calendars = await this.syncService.discover(this.serverUrl, this.username, this.password);
      this.selectedCalendarIndex = 0;
      this.statusText = this.calendars.length > 0 ? '请选择任务日历并保存' : '没有找到支持 VTODO 的日历';
    } catch (err) {
      this.statusText = `连接失败：${JSON.stringify(err)}`;
    }
    this.loading = false;
  }

  private async saveAccount(): Promise<void> {
    if (this.calendars.length === 0) {
      this.safeShowToast('请先测试连接');
      return;
    }
    try {
      await this.syncService.saveAccount(this.serverUrl, this.username, this.password, this.calendars[this.selectedCalendarIndex]);
      this.configured = true;
      this.selectedTabIndex = 0;
      this.statusText = '账号已保存';
      await this.syncNow();
    } catch (err) {
      this.statusText = `保存失败：${JSON.stringify(err)}`;
    }
  }

  private async syncNow(): Promise<void> {
    this.loading = true;
    this.statusText = '正在同步';
    try {
      const result = await this.syncService.syncNow();
      this.statusText = result.message;
      await this.refreshLists();
      if (this.tasks.some((task: TodoTask) => this.taskHasReminder(task))
        && await this.ensureReminderNotifications(true)) {
        await this.syncService.syncLocalReminders();
      }
    } catch (err) {
      const errMsg = `${err}`;
      const errCode = (err as Record<string, number>)['code'];
      this.statusText = errCode !== undefined ? `同步失败：[${errCode}] ${errMsg}` : `同步失败：${errMsg}`;
      console.error('Cavdal sync error', errMsg);
    }
    this.loading = false;
  }

  private async refreshFromPull(): Promise<void> {
    if (!this.configured || this.selectedTabIndex !== 0 || this.loading) {
      this.refreshing = false;
      return;
    }
    this.refreshing = true;
    try {
      await this.syncNow();
    } finally {
      this.refreshing = false;
    }
  }

  private async addTask(): Promise<void> {
    if (this.newTitle.trim().length === 0) {
      this.safeShowToast('请输入待办标题');
      return;
    }
    try {
      if (this.hasDue && this.reminderOption !== '无') {
        await this.ensureReminderNotifications(true);
      }
      await this.syncService.addTask(
        this.newTitle.trim(),
        this.newDescription.trim(),
        this.hasDue ? this.formatDueForCalDav() : '',
        this.hasDue ? this.reminderOption : '无',
        this.hasDue ? this.repeatOption : '无'
      );
      this.newTitle = '';
      this.newDescription = '';
      this.hasDue = false;
      this.reminderOption = '无';
      this.repeatOption = '无';
      this.settingPanel = '';
      this.showAddSheet = false;
      this.statusText = '已添加';
      await this.refreshLists();
    } catch (err) {
      this.safeShowToast('添加失败');
      this.statusText = `添加失败：${JSON.stringify(err)}`;
    }
  }

  private openAddSheet(): void {
    const now = new Date();
    this.selectedDueDate = now;
    this.selectedDueHour = now.getHours();
    this.selectedDueMinute = now.getMinutes();
    this.hasDue = false;
    this.reminderOption = '无';
    this.repeatOption = '无';
    this.settingPanel = '';
    this.showAddSheet = true;
  }

  private showDatePicker(): void {
    this.uiContext.showDatePickerDialog({
      selected: this.selectedDueDate,
      onAccept: (value: DatePickerResult) => {
        this.selectedDueDate.setFullYear(value.year, value.month, value.day);
        this.hasDue = true;
        this.reminderOption = '无';
      }
    });
  }

  private showTimePicker(): void {
    this.uiContext.showTimePickerDialog({
      selected: new Date(2026, 0, 1, this.selectedDueHour, this.selectedDueMinute),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.selectedDueHour = value.hour;
        this.selectedDueMinute = value.minute;
        this.hasDue = true;
        this.reminderOption = '立刻';
      }
    });
  }

  private formatDueForCalDav(): string {
    const due = new Date(
      this.selectedDueDate.getFullYear(),
      this.selectedDueDate.getMonth(),
      this.selectedDueDate.getDate(),
      this.selectedDueHour,
      this.selectedDueMinute,
      0
    );
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${due.getUTCFullYear()}${pad(due.getUTCMonth() + 1)}${pad(due.getUTCDate())}T${pad(due.getUTCHours())}${pad(due.getUTCMinutes())}00Z`;
  }

  private dateOnlyPreview(): string {
    return `${this.selectedDueDate.getFullYear()}年${this.selectedDueDate.getMonth() + 1}月${this.selectedDueDate.getDate()}日`;
  }

  private timeOnlyPreview(): string {
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${pad(this.selectedDueHour)}:${pad(this.selectedDueMinute)}`;
  }

  private reminderOptions(): string[] {
    return ['无', '立刻', '当天', '提前一天', '提前一周'];
  }

  private repeatOptions(): string[] {
    return ['无', '每天', '每周', '每月'];
  }

  private updateTaskListsImmediately(task: TodoTask, done: boolean): void {
    const updated = VTodoCodec.setCompletion(task, done);
    if (done) {
      this.tasks = this.tasks.filter((item: TodoTask) => item.id !== task.id);
      this.completed = [updated].concat(this.completed.filter((item: TodoTask) => item.id !== task.id));
      return;
    }
    this.completed = this.completed.filter((item: TodoTask) => item.id !== task.id);
    this.tasks = [updated].concat(this.tasks.filter((item: TodoTask) => item.id !== task.id));
  }

  private async toggleTask(task: TodoTask, done: boolean): Promise<void> {
    this.updateTaskListsImmediately(task, done);
    try {
      await this.syncService.setTaskCompleted(task.id, done);
      this.statusText = done ? '已完成' : '已恢复';
      await this.refreshLists();
    } catch (err) {
      await this.refreshLists();
      this.statusText = `操作失败：${JSON.stringify(err)}`;
      this.safeShowToast('操作失败，请重试');
    }
  }

  private openEditTask(task: TodoTask): void {
    this.editingTask = {
      id: task.id,
      uid: task.uid,
      href: task.href,
      calendarHref: task.calendarHref,
      etag: task.etag,
      title: task.title,
      description: task.description,
      due: task.due,
      priority: task.priority,
      status: task.status,
      completedAt: task.completedAt,
      percentComplete: task.percentComplete,
      rawIcs: task.rawIcs,
      syncState: task.syncState,
      updatedAt: task.updatedAt
    };
    this.loadTaskState(task);
    this.showEditSheet = true;
  }

  private setCompletedOpen(open: boolean): void {
    this.showCompleted = open;
    this.completedUserOverride = true;
  }

  private async deleteTaskInList(task: TodoTask): Promise<void> {
    try {
      await this.syncService.deleteTask(task.id);
      this.statusText = '已删除';
      await this.refreshLists();
    } catch (err) {
      this.statusText = `删除失败：${JSON.stringify(err)}`;
      this.safeShowToast('删除失败，请重试');
    }
  }

  private async clearLocal(): Promise<void> {
    try {
      await this.syncService.clearLocal();
      await this.refreshLists();
      this.statusText = '本地缓存已清空';
    } catch (err) {
      this.statusText = `清空失败：${JSON.stringify(err)}`;
      this.safeShowToast('清空失败');
    }
  }

  private async updateWidgetBlurStyle(style: WidgetBlurStyle): Promise<void> {
    const previous = this.widgetBlurStyle;
    this.widgetBlurStyle = style;
    try {
      await this.syncService.saveWidgetBlurStyle(style);
      this.statusText = `卡片背景已设为${widgetBlurLabel(style)}`;
    } catch (err) {
      this.widgetBlurStyle = previous;
      this.statusText = `卡片设置失败：${JSON.stringify(err)}`;
      this.safeShowToast('卡片设置失败');
    }
  }

  @Builder
  private ServerSettingsMenu() {
    Column({ space: 10 }) {
      this.SettingRow($r('sys.symbol.cloud'), 'Cavdal 服务器设置', this.configured ? this.username : '未配置', 'server')
      if (this.settingPanel === 'server' || !this.configured) {
        this.SetupView()
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface_translucent'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 0.5, color: $r('app.color.bar_glass_edge') })
    .borderRadius(18)
  }

  @Builder
  private SetupView() {
    Column({ space: 16 }) {
      Text('连接支持 CalDAV VTODO 的任务服务，桌面卡片可快速完成待办。')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ placeholder: 'https://example.com/caldav', text: this.serverUrl })
        .onChange((value: string) => this.serverUrl = value)
        .height(48)

      TextInput({ placeholder: '用户名', text: this.username })
        .onChange((value: string) => this.username = value)
        .height(48)

      TextInput({ placeholder: '密码或 App Password', text: this.password })
        .type(InputType.Password)
        .onChange((value: string) => this.password = value)
        .height(48)

      Row({ space: 12 }) {
        Button('测试连接')
          .onClick(() => this.discoverCalendars())
          .layoutWeight(1)
        Button('保存')
          .enabled(this.calendars.length > 0)
          .onClick(() => this.saveAccount())
          .layoutWeight(1)
      }
      .width('100%')

      if (this.calendars.length > 0) {
        Text('任务日历')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Column({ space: 8 }) {
          ForEach(this.calendars, (calendar: CalendarSource, index: number) => {
            Row() {
              Text(calendar.displayName)
                .fontSize(16)
                .layoutWeight(1)
              Radio({ value: `${index}`, group: 'calendar' })
                .checked(this.selectedCalendarIndex === index)
                .onChange((checked: boolean) => {
                  if (checked) {
                    this.selectedCalendarIndex = index;
                  }
                })
            }
            .width('100%')
            .height(44)
          }, (calendar: CalendarSource) => calendar.href)
        }
      }

      Text(this.statusText)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .padding(24)
    .width('100%')
  }

  private filteredActiveTasks(): TodoTask[] {
    if (this.searchQuery.length === 0) {
      return this.tasks;
    }
    const q = this.searchQuery.toLowerCase();
    return this.tasks.filter((t: TodoTask) => t.title.toLowerCase().includes(q));
  }

  private filteredCompletedTasks(): TodoTask[] {
    if (this.searchQuery.length === 0) {
      return this.completed;
    }
    const q = this.searchQuery.toLowerCase();
    return this.completed.filter((t: TodoTask) => t.title.toLowerCase().includes(q));
  }

  private pendingTaskCount(): number {
    return this.filteredActiveTasks().filter((t: TodoTask) => t.syncState !== 'synced').length;
  }

  private homeLayout(): HomeLayoutMetrics {
    return calculateHomeLayout(this.homeViewportHeight, this.filteredActiveTasks().length,
      this.pendingTaskCount(), this.filteredCompletedTasks().length,
      this.completedUserOverride, this.showCompleted);
  }

  @Builder
  private SettingsView() {
    Column({ space: 14 }) {
      this.ServerSettingsMenu()
      WidgetAppearanceCard({
        selectedStyle: this.widgetBlurStyle,
        onStyleChange: (style: WidgetBlurStyle): void => {
          this.updateWidgetBlurStyle(style);
        }
      })

      Row() {
        Column({ space: 2 }) {
          Text('智感握姿')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('加号按钮跟随握持手位置')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.handednessEnabled })
          .onChange((on: boolean) => this.toggleHandedness(on))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface_translucent'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .border({ width: 0.5, color: $r('app.color.bar_glass_edge') })
      .borderRadius(18)

      Button('立即同步')
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_accent'))
        .backgroundColor($r('app.color.accent'))
        .borderRadius(22)
        .onClick(() => this.syncNow())
        .width('100%')
      Button('清空本地缓存')
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.danger_text'))
        .backgroundColor($r('app.color.surface_translucent'))
        .border({ width: 1, color: $r('app.color.danger_text') })
        .borderRadius(22)
        .onClick(() => this.clearLocal())
        .width('100%')
    }
    .padding({ left: 22, right: 22, top: 4, bottom: 120 })
    .width('100%')
  }

  @Builder
  private HomeView() {
    Column({ space: 14 }) {
      TaskCards({
        activeTasks: this.filteredActiveTasks(),
        completedTasks: this.filteredCompletedTasks(),
        completedTotalCount: this.completed.length,
        activeHeight: this.homeLayout().activeHeight,
        completedHeight: this.homeLayout().completedHeight,
        completedOpen: this.homeLayout().completedOpen,
        onToggleTask: (task: TodoTask, done: boolean): void => {
          this.toggleTask(task, done);
        },
        onEditTask: (task: TodoTask): void => {
          this.openEditTask(task);
        },
        onDeleteTask: (task: TodoTask): void => {
          this.deleteTaskInList(task);
        },
        onAddTask: (): void => {
          this.openAddSheet();
        },
        onCompletedOpenChange: (open: boolean): void => {
          this.setCompletedOpen(open);
        }
      })

      Text(this.statusText)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.surface_translucent'))
        .borderRadius(12)
    }
    .padding({ left: 22, right: 22, top: 4, bottom: 132 })
    .width('100%')
    .height('100%')
  }

  @Builder
  private AddTaskSheetContent() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text('添加待办')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          if (this.hasDue) {
            Text(this.reminderOption !== '无' ? this.timeOnlyPreview() : this.dateOnlyPreview())
              .fontSize(13)
              .fontColor($r('app.color.accent'))
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('添加')
          .height(38)
          .padding({ left: 18, right: 18 })
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .borderRadius(19)
          .onClick(() => this.addTask())
      }
      .width('100%')

      TextInput({ placeholder: '待办标题', text: this.newTitle })
        .onChange((value: string) => this.newTitle = value)
        .height(54)
        .fontSize(18)
        .backgroundColor($r('app.color.surface_input'))
        .borderRadius(16)

      TextInput({ placeholder: '说明，可留空', text: this.newDescription })
        .onChange((value: string) => this.newDescription = value)
        .height(54)
        .fontSize(16)
        .backgroundColor($r('app.color.surface_input'))
        .borderRadius(16)

      Row({ space: 10 }) {
        Row({ space: 10 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(21)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.hasDue ? $r('app.color.on_accent') : $r('app.color.accent')])
          }
          .type(ButtonType.Normal)
          .width(44)
          .height(44)
          .backgroundColor(this.hasDue ? $r('app.color.accent') : $r('app.color.surface_translucent'))
          .border({ width: 1, color: this.hasDue ? $r('app.color.accent') : $r('app.color.bar_glass_edge') })
          .borderRadius(22)
          .onClick(() => this.showDatePicker())

          if (this.hasDue) {
            Button() {
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.reminderOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
            }
            .type(ButtonType.Normal)
            .width(44)
            .height(44)
            .backgroundColor(this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.surface_translucent'))
            .border({ width: 1, color: this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.bar_glass_edge') })
            .borderRadius(22)
            .onClick(() => this.showTimePicker())
          }

          Button() {
            SymbolGlyph($r('sys.symbol.bell'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.reminderOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
          }
          .type(ButtonType.Normal)
          .width(44)
          .height(44)
          .backgroundColor(this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.surface_translucent'))
          .border({ width: 1, color: this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.bar_glass_edge') })
          .borderRadius(22)
          .onClick(() => this.settingPanel = this.settingPanel === 'reminder' ? '' : 'reminder')

          Button() {
            SymbolGlyph($r('sys.symbol.repeat'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.repeatOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
          }
          .type(ButtonType.Normal)
          .width(44)
          .height(44)
          .backgroundColor(this.repeatOption !== '无' ? $r('app.color.accent') : $r('app.color.surface_translucent'))
          .border({ width: 1, color: this.repeatOption !== '无' ? $r('app.color.accent') : $r('app.color.bar_glass_edge') })
          .borderRadius(22)
          .onClick(() => this.settingPanel = this.settingPanel === 'repeat' ? '' : 'repeat')
        }

        Blank()
          .layoutWeight(1)

        Button('取消')
          .height(44)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 18, right: 18 })
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_translucent'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .border({ width: 1, color: $r('app.color.bar_glass_edge') })
          .borderRadius(22)
          .onClick(() => {
            this.showAddSheet = false;
          })
      }
        .width('100%')
        .margin({ top: 4 })

      if (this.settingPanel === 'reminder') {
        this.OptionChips(this.reminderOptions(), 'reminder')
      }
      if (this.settingPanel === 'repeat') {
        this.OptionChips(this.repeatOptions(), 'repeat')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 26 })
  }

  @Builder
  private EditTaskSheetContent() {
    if (this.editingTask !== null) {
      Column({ space: 12 }) {
        Row() {
          Text('编辑待办')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Button('完成')
            .height(38)
            .padding({ left: 18, right: 18 })
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(19)
            .onClick(() => {
              this.saveEdit();
            })
        }
        .width('100%')

        TextInput({ placeholder: '待办标题', text: this.editingTask!.title })
          .onChange((value: string) => {
            this.updateEditingTitle(value);
          })
          .height(54)
          .fontSize(18)
          .backgroundColor($r('app.color.surface_input'))
          .borderRadius(16)

        TextInput({ placeholder: '说明，可留空', text: this.editingTask!.description })
          .onChange((value: string) => {
            this.updateEditingDesc(value);
          })
          .height(54)
          .fontSize(16)
          .backgroundColor($r('app.color.surface_input'))
          .borderRadius(16)

        Row({ space: 10 }) {
          Row({ space: 10 }) {
            Button() {
              SymbolGlyph($r('sys.symbol.calendar'))
                .fontSize(21)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.hasDue ? $r('app.color.on_accent') : $r('app.color.accent')])
            }
            .type(ButtonType.Normal)
            .width(44)
            .height(44)
            .backgroundColor(this.hasDue ? $r('app.color.accent') : $r('app.color.surface_translucent'))
            .border({ width: 1, color: this.hasDue ? $r('app.color.accent') : $r('app.color.bar_glass_edge') })
            .borderRadius(22)
            .onClick(() => this.showDatePicker())

            if (this.hasDue) {
              Button() {
                SymbolGlyph($r('sys.symbol.clock'))
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.reminderOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
              }
              .type(ButtonType.Normal)
              .width(44)
              .height(44)
              .backgroundColor(this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.surface_translucent'))
              .border({ width: 1, color: this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.bar_glass_edge') })
              .borderRadius(22)
              .onClick(() => this.showTimePicker())
            }

            Button() {
              SymbolGlyph($r('sys.symbol.bell'))
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.reminderOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
            }
            .type(ButtonType.Normal)
            .width(44)
            .height(44)
            .backgroundColor(this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.surface_translucent'))
            .border({ width: 1, color: this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.bar_glass_edge') })
            .borderRadius(22)
            .onClick(() => this.settingPanel = this.settingPanel === 'reminder' ? '' : 'reminder')

            Button() {
              SymbolGlyph($r('sys.symbol.repeat'))
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.repeatOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
            }
            .type(ButtonType.Normal)
            .width(44)
            .height(44)
            .backgroundColor(this.repeatOption !== '无' ? $r('app.color.accent') : $r('app.color.surface_translucent'))
            .border({ width: 1, color: this.repeatOption !== '无' ? $r('app.color.accent') : $r('app.color.bar_glass_edge') })
            .borderRadius(22)
            .onClick(() => this.settingPanel = this.settingPanel === 'repeat' ? '' : 'repeat')
          }
          Blank().layoutWeight(1)
        }

        Row({ space: 10 }) {
          Blank()
            .layoutWeight(1)
          Button('取消')
            .height(44)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 18, right: 18 })
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.surface_translucent'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
            .border({ width: 1, color: $r('app.color.bar_glass_edge') })
            .borderRadius(22)
            .onClick(() => {
              this.showEditSheet = false;
              this.editingTask = null;
            })
        }
        .width('100%')
        .margin({ top: 4 })

        if (this.settingPanel === 'reminder') {
          this.OptionChips(this.reminderOptions(), 'reminder')
        }
        if (this.settingPanel === 'repeat') {
          this.OptionChips(this.repeatOptions(), 'repeat')
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 26 })
    }
  }

  private updateEditingTitle(value: string): void {
    if (this.editingTask !== null) {
      this.editingTask.title = value;
    }
  }

  private updateEditingDesc(value: string): void {
    if (this.editingTask !== null) {
      this.editingTask.description = value;
    }
  }

  private loadTaskState(task: TodoTask): void {
    const due = parseDueAsBeijing(task.due);
    if (due !== undefined) {
      this.selectedDueDate = new Date(due.year, due.month - 1, due.day);
      this.selectedDueHour = due.hour;
      this.selectedDueMinute = due.minute;
      this.hasDue = true;
    } else {
      const now = new Date();
      this.selectedDueDate = now;
      this.selectedDueHour = now.getHours();
      this.selectedDueMinute = now.getMinutes();
      this.hasDue = false;
    }
    this.reminderOption = VTodoCodec.detectReminder(task.rawIcs, task.due);
    this.repeatOption = VTodoCodec.detectRepeat(task.rawIcs);
    this.settingPanel = '';
  }

  private async saveEdit(): Promise<void> {
    if (this.editingTask === null) {
      return;
    }
    if (this.editingTask.title.trim().length === 0) {
      this.safeShowToast('请输入待办标题');
      return;
    }
    const taskId = this.editingTask.id;
    const title = this.editingTask.title.trim();
    const description = this.editingTask.description.trim();
    const due = this.hasDue ? this.formatDueForCalDav() : '';
    const reminder = this.hasDue ? this.reminderOption : '无';
    const repeat = this.hasDue ? this.repeatOption : '无';

    this.tasks = this.tasks.map((task: TodoTask) => {
      if (task.id !== taskId) {
        return task;
      }
      return {
        id: task.id, uid: task.uid, href: task.href, calendarHref: task.calendarHref,
        etag: task.etag, title, description, due, priority: task.priority, status: task.status,
        completedAt: task.completedAt, percentComplete: task.percentComplete, rawIcs: task.rawIcs,
        syncState: 'pending', updatedAt: Date.now()
      };
    });
    this.showEditSheet = false;
    this.editingTask = null;
    this.hasDue = false;
    this.reminderOption = '无';
    this.repeatOption = '无';
    this.statusText = '正在更新';

    try {
      if (reminder !== '无') {
        await this.ensureReminderNotifications(true);
      }
      await this.syncService.updateTask(
        taskId,
        title,
        description,
        due,
        reminder,
        repeat
      );
      this.statusText = '已更新';
      await this.refreshLists();
    } catch (err) {
      await this.refreshLists();
      this.safeShowToast('更新失败，请重试');
      this.statusText = `更新失败：${JSON.stringify(err)}`;
    }
  }

  @Builder
  private SettingRow(icon: Resource, label: string, value: string, target: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([$r('app.color.text_secondary')])
        .width(30)
      Text(label)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (target.length > 0) {
        SymbolGlyph(this.settingPanel === target ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([$r('app.color.text_disabled')])
      }
    }
    .height(46)
    .width('100%')
    .onClick(() => {
      if (target.length > 0) {
        this.settingPanel = this.settingPanel === target ? '' : target;
      }
    })
  }

  @Builder
  private OptionChips(options: string[], target: string) {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(options, (option: string) => {
          Button(option)
            .type(ButtonType.Normal)
            .fontSize(13)
            .fontColor((target === 'reminder' ? this.reminderOption : this.repeatOption) === option ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
            .backgroundColor((target === 'reminder' ? this.reminderOption : this.repeatOption) === option ? $r('app.color.accent') : $r('app.color.surface_input'))
            .borderRadius(16)
            .height(32)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              if (target === 'reminder') {
                this.reminderOption = option;
              } else {
                this.repeatOption = option;
              }
            })
        }, (option: string) => `${target}-${option}`)
      }
      .padding({ left: 0, right: 0, bottom: 8 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private MainTabContents() {
    TabContent() {
      Refresh({ refreshing: $$this.refreshing, promptText: '正在同步' }) {
        Column() {
          this.HomeView()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const h = newValue.height;
          if (typeof h === 'number') {
            this.homeViewportHeight = h;
          }
          // Tabs 首帧布局完成即触发 bar 重排，让 47→48 的跳变发生在首帧内
          this.scheduleTabBarLayoutPass();
        })
      }
      .width('100%')
      .height('100%')
      .pullToRefresh(this.configured)
      .refreshOffset(64)
      .onRefreshing(() => {
        this.refreshFromPull();
      })
    }
    .tabBar(this.homeTabBar)

    TabContent() {
      Scroll() {
        Column() {
          this.SettingsView()
        }
        .width('100%')
        .backgroundColor($r('app.color.page_background'))
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
    }
    .tabBar(this.settingsTabBar)
  }

  build() {
    RelativeContainer() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })

      Column() {
        if (this.configured) {
          Row() {
            Text(this.selectedTabIndex === 1 ? '设置' : '待办事项')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            Button() {
              SymbolGlyph(this.searchQuery.length > 0 ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([this.showSearch || this.searchQuery.length > 0 ? $r('app.color.accent') : $r('app.color.text_secondary')])
            }
            .type(ButtonType.Normal)
            .width(44)
            .height(44)
            .backgroundColor($r('app.color.surface_translucent'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
            .border({ width: 0.5, color: $r('app.color.bar_glass_edge') })
            .borderRadius(22)
            .margin({ right: 8 })
            .onClick(() => {
              if (this.searchQuery.length > 0) {
                this.searchQuery = '';
              } else {
                this.showSearch = !this.showSearch;
              }
            })

          }
          .width('100%')
          .padding({ left: 22, right: 22, top: this.uiContext.px2vp(this.statusBarHeight) + 8, bottom: 4 })

          if (this.showSearch) {
            Search({ value: this.searchQuery, placeholder: '搜索待办事项...' })
              .onChange((value: string) => this.searchQuery = value)
              .height(44)
              .textFont({ size: 16 })
              .placeholderFont({ size: 16 })
              .backgroundColor($r('app.color.surface'))
              .borderRadius(16)
              .margin({ left: 22, right: 22, bottom: 4 })
          }

          if (deviceInfo.apiAvailable('26.0.0')) {
            // API 26 起使用 ArkUI 原生悬浮 Tabs，避开旧目标版本 HdsTabs 在 Beta2 上不渲染的问题。
            Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
              this.MainTabContents()
            }
            .vertical(false)
            .scrollable(true)
            .barOverlap(true)
            // 状态驱动栏高：47 → 48 只触发 bar 区域重排，避免 .id() 重建整棵 Tabs。
            // 47vp 为过渡值，首帧视觉偏差 1vp 不可感知。
            .barHeight(this.tabBarHeight)
            .barFloatingStyle({
              barBottomMargin: 24,
              adaptToHandedness: true,
              systemMaterial: new uiMaterial.ImmersiveMaterial({
                colorInvert: true,
                interactive: true,
                lightEffect: { color: $r('app.color.accent') }
              })
            })
            .onChange((index: number) => {
              this.selectedTabIndex = index;
            })
            .layoutWeight(1)
            .width('100%')
          } else {
            // API 24-25 保留 HDS 实现，维持旧系统的沉浸光感和握姿适配。
            HdsTabs({ controller: this.hdsController }) {
              this.MainTabContents()
            }
            .barPosition(BarPosition.End)
            .vertical(false)
            .scrollable(true)
            .barOverlap(true)
            .barHeight(60)
            .barFloatingStyle({
              barBottomMargin: 24,
              adaptToHandedness: true,
              lightColor: $r('app.color.accent'),
              systemMaterialEffect: {
                materialType: hdsMaterial.MaterialType.IMMERSIVE,
                materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
              }
            })
            .onChange((index: number) => {
              this.selectedTabIndex = index;
            })
            .layoutWeight(1)
            .width('100%')
          }
        } else {
          Refresh({ refreshing: $$this.refreshing, promptText: '正在同步' }) {
            Scroll() {
              Column() {
                this.SetupView()
              }
              .width('100%')
              .padding({ top: this.uiContext.px2vp(this.statusBarHeight) + 8, bottom: 24 })
              .backgroundColor($r('app.color.page_background'))
            }
            .width('100%')
            .scrollBar(BarState.Auto)
            .align(Alignment.TopStart)
          }
          .layoutWeight(1)
          .width('100%')
          .pullToRefresh(false)
        }
      }
      .width('100%')
      .height('100%')
      .alignRules({
        top: { anchor: '__container__', align: VerticalAlign.Top },
        left: { anchor: '__container__', align: HorizontalAlign.Start }
      })

      if (this.configured) {
        if (this.selectedTabIndex === 0) {
          Button() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor([$r('app.color.on_accent')])
          }
          .type(ButtonType.Normal)
          .width(56)
          .height(56)
          .borderRadius(28)
          .backgroundColor($r('app.color.accent'))
          .shadow({ radius: 18, color: $r('app.color.shadow'), offsetX: 0, offsetY: 8 })
          .scale({ x: this.showAddSheet ? 0.94 : 1, y: this.showAddSheet ? 0.94 : 1 })
          .animation({ duration: 160, curve: Curve.EaseOut })
          .alignRules(this.fabAlignRules)
          .margin({ left: 22, right: 22, bottom: 96 })
          .onClick(() => this.openAddSheet())
        }
      }

      Column()
        .width(0)
        .height(0)
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })
        .bindSheet($$this.showAddSheet, this.AddTaskSheetContent(), {
          detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
          backgroundColor: $r('app.color.surface_translucent'),
          blurStyle: BlurStyle.COMPONENT_THIN,
          showClose: false
        })

      Column()
        .width(0)
        .height(0)
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })
        .bindSheet($$this.showEditSheet, this.EditTaskSheetContent(), {
          detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
          backgroundColor: $r('app.color.surface_translucent'),
          blurStyle: BlurStyle.COMPONENT_THIN,
          showClose: false,
          onDisappear: () => {
            this.editingTask = null;
          }
        })
    }
    .height('100%')
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
