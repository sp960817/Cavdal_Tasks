import { common } from '@kit.AbilityKit';
import notificationManager from '@ohos.notificationManager';
import { CalendarSource, TodoTask, WidgetBlurStyle } from '../model/TaskModels';
import { TaskRepository } from '../data/TaskRepository';
import { SyncService } from '../sync/SyncService';
import { formatDueForDisplay, parseDueAsBeijing } from '../formatters/DueTimeFormatter';
import { VTodoCodec } from '../caldav/VTodoCodec';

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
  @State calendarViewDate: Date = new Date();
  @State hasDue: boolean = false;
  @State reminderOption: string = '无';
  @State repeatOption: string = '无';
  @State settingPanel: string = '';
  @State showTimePopup: boolean = false;
  @State showAddSheet: boolean = false;
  @State showDueSheet: boolean = false;
  @State selectedTabIndex: number = 0;
  @State showEditSheet: boolean = false;
  @State showSearch: boolean = false;
  @State showCompleted: boolean = true;
  @State showReminderPopup: boolean = false;
  @State showRepeatPopup: boolean = false;
  @State searchQuery: string = '';
  @State editingTask: TodoTask | null = null;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  private uiContext: UIContext = this.getUIContext();
  private context: common.UIAbilityContext = this.requireHostContext();
  // 统一使用应用级上下文，与桌面小组件共享同一份数据存储
  private repository: TaskRepository = new TaskRepository(this.context.getApplicationContext());
  private syncService: SyncService = new SyncService(this.context.getApplicationContext());
  private firstPageShow: boolean = true;
  private reminderNotificationPrompted: boolean = false;

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
      this.showDueSheet = false;
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
    this.calendarViewDate = new Date(now.getFullYear(), now.getMonth(), 1);
    this.hasDue = false;
    this.reminderOption = '无';
    this.repeatOption = '无';
    this.settingPanel = '';
    this.showTimePopup = false;
    this.showDueSheet = false;
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

  private duePreview(): string {
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${this.selectedDueDate.getFullYear()}年${this.selectedDueDate.getMonth() + 1}月${this.selectedDueDate.getDate()}日 ${pad(this.selectedDueHour)}:${pad(this.selectedDueMinute)}`;
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

  private monthTitle(): string {
    const monthNames: string[] = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];
    return monthNames[this.calendarViewDate.getMonth()];
  }

  private weekdayHeaders(): string[] {
    return ['一', '二', '三', '四', '五', '六', '日'];
  }

  private calendarCells(): number[] {
    const year = this.calendarViewDate.getFullYear();
    const month = this.calendarViewDate.getMonth();
    const firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7;
    const count = new Date(year, month + 1, 0).getDate();
    const cells: number[] = [];
    for (let index = 0; index < firstWeekday; index++) {
      cells.push(0);
    }
    for (let day = 1; day <= count; day++) {
      cells.push(day);
    }
    while (cells.length < 35 || cells.length % 7 !== 0) {
      cells.push(0);
    }
    return cells;
  }

  private isSelectedDay(day: number): boolean {
    return day > 0 &&
      this.selectedDueDate.getFullYear() === this.calendarViewDate.getFullYear() &&
      this.selectedDueDate.getMonth() === this.calendarViewDate.getMonth() &&
      this.selectedDueDate.getDate() === day;
  }

  private holidayText(day: number): string {
    const month = this.calendarViewDate.getMonth() + 1;
    if (month === 6 && day === 1) {
      return '儿童节';
    }
    if (month === 6 && day === 19) {
      return '端午节';
    }
    if (month === 6 && day === 21) {
      return '父亲节';
    }
    return '';
  }

  private isRestDay(day: number): boolean {
    const week = new Date(this.calendarViewDate.getFullYear(), this.calendarViewDate.getMonth(), day).getDay();
    return day > 0 && (week === 0 || week === 6);
  }

  private changeMonth(offset: number): void {
    this.calendarViewDate = new Date(this.calendarViewDate.getFullYear(), this.calendarViewDate.getMonth() + offset, 1);
  }

  private selectCalendarDay(day: number): void {
    if (day === 0) {
      return;
    }
    this.selectedDueDate = new Date(this.calendarViewDate.getFullYear(), this.calendarViewDate.getMonth(), day);
  }

  private visibleCompletedTasks(): TodoTask[] {
    return this.completed.length > 5 ? this.completed.slice(0, 5) : this.completed;
  }

  private async toggleTask(task: TodoTask, done: boolean): Promise<void> {
    try {
      await this.syncService.setTaskCompleted(task.id, done);
      this.statusText = done ? '已完成' : '已恢复';
      await this.refreshLists();
    } catch (err) {
      this.statusText = `操作失败：${JSON.stringify(err)}`;
      this.safeShowToast('操作失败，请重试');
    }
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

  private widgetBlurLabel(style: WidgetBlurStyle): string {
    if (style === 'none') return '通透';
    if (style === 'thin') return '轻薄';
    if (style === 'thick') return '厚重';
    return '标准';
  }

  private async updateWidgetBlurStyle(style: WidgetBlurStyle): Promise<void> {
    const previous = this.widgetBlurStyle;
    this.widgetBlurStyle = style;
    try {
      await this.syncService.saveWidgetBlurStyle(style);
      this.statusText = `卡片背景已设为${this.widgetBlurLabel(style)}`;
    } catch (err) {
      this.widgetBlurStyle = previous;
      this.statusText = `卡片设置失败：${JSON.stringify(err)}`;
      this.safeShowToast('卡片设置失败');
    }
  }

  @Builder
  private WidgetAppearanceSettings() {
    Column({ space: 10 }) {
      Text('桌面卡片背景')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Row({ space: 4 }) {
        ForEach(['none', 'thin', 'regular', 'thick'] as WidgetBlurStyle[], (style: WidgetBlurStyle) => {
          Button(this.widgetBlurLabel(style))
            .fontSize(13)
            .fontColor(this.widgetBlurStyle === style ?
              $r('app.color.on_accent') : $r('app.color.text_secondary'))
            .backgroundColor(this.widgetBlurStyle === style ?
              $r('app.color.accent') : $r('app.color.surface_input'))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => this.updateWidgetBlurStyle(style))
        }, (style: WidgetBlurStyle) => style)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
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
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
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

  @Builder
  private ActiveTaskRow(task: TodoTask) {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        Toggle({ type: ToggleType.Checkbox, isOn: false })
          .onChange((isOn: boolean) => {
            if (isOn) {
              this.toggleTask(task, true);
            }
          })
          .width(22)
          .height(22)

        Text(task.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (task.due.length > 0) {
          Text(formatDueForDisplay(task.due))
            .fontSize(14)
            .fontColor($r('app.color.accent'))
        }

        if (VTodoCodec.detectReminder(task.rawIcs, task.due) !== '无') {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(14)
            .fontColor([$r('app.color.accent')])
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.editingTask = {
          id: task.id, uid: task.uid, href: task.href, calendarHref: task.calendarHref,
          etag: task.etag, title: task.title, description: task.description, due: task.due,
          priority: task.priority, status: task.status, completedAt: task.completedAt,
          percentComplete: task.percentComplete, rawIcs: task.rawIcs,
          syncState: task.syncState, updatedAt: task.updatedAt
        };
        this.loadTaskState(task);
        this.showEditSheet = true;
      })

      if (task.syncState !== 'synced') {
        Row() {
          Blank()
            .layoutWeight(1)
          Text(task.syncState === 'pending' ? '待同步' : task.syncState)
            .fontSize(12)
            .fontColor(task.syncState === 'conflict' ? $r('app.color.danger_text') : $r('app.color.warning_text'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 4, right: 6 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private CompletedTaskRow(task: TodoTask) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: true })
        .onChange((isOn: boolean) => {
          if (!isOn) {
            this.toggleTask(task, false);
          }
        })
        .width(22)
        .height(22)

      Text(task.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (task.due.length > 0) {
        Text(formatDueForDisplay(task.due))
          .fontSize(14)
          .fontColor($r('app.color.text_disabled'))
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 4, right: 6 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private ActiveTasksCard() {
    Column() {
      if (this.tasks.length === 0) {
        Text('没有进行中的待办')
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
          .height(52)
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.tasks.filter((t: TodoTask) => {
            if (this.searchQuery.length === 0) return true;
            return t.title.toLowerCase().includes(this.searchQuery.toLowerCase());
          }), (task: TodoTask) => {
            ListItem() {
              this.ActiveTaskRow(task)
            }
            .swipeAction({
              end: {
                builder: () => {
                  this.DeleteSwipeAction(task)
                },
                onAction: () => {
                  this.deleteTaskInList(task);
                }
              }
            })
          }, (task: TodoTask) => `${task.id}-${task.updatedAt}-${task.syncState}`)
        }
        .width('100%')
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(18)
  }

  @Builder
  private DeleteSwipeAction(task: TodoTask) {
    Row() {
      Text('删除')
        .fontSize(16)
        .fontColor($r('app.color.on_accent'))
        .fontWeight(FontWeight.Medium)
    }
    .width(72)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.danger'))
    .borderRadius({ topRight: 16, bottomRight: 16 })
    .onClick(() => {
      this.deleteTaskInList(task);
    })
  }

  @Builder
  private CompletedTasksCard() {
    Column() {
      Row() {
        Text('已完成')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
        Text(`${this.completed.length}`)
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ right: 8 })
        SymbolGlyph(this.showCompleted ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(18)
          .fontColor([$r('app.color.text_disabled')])
      }
      .width('100%')
      .height(34)
      .margin({ bottom: this.showCompleted ? 8 : 0 })
      .onClick(() => {
        this.showCompleted = !this.showCompleted;
      })

      if (this.showCompleted) {
        if (this.completed.length === 0) {
          Text('暂无已完成事项')
            .fontSize(15)
            .fontColor($r('app.color.text_disabled'))
            .height(52)
            .width('100%')
            .textAlign(TextAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.completed.filter((t: TodoTask) => {
              if (this.searchQuery.length === 0) return true;
              return t.title.toLowerCase().includes(this.searchQuery.toLowerCase());
            }), (task: TodoTask) => {
              ListItem() {
                this.CompletedTaskRow(task)
              }
            .swipeAction({
              end: {
                builder: () => {
                  this.DeleteSwipeAction(task)
                },
                onAction: () => {
                  this.deleteTaskInList(task);
                }
              }
            })
            }, (task: TodoTask) => `${task.id}-${task.updatedAt}-${task.syncState}`)
          }
          .width('100%')
          .height(240)
          .scrollBar(BarState.Auto)
        }
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(18)
  }

  private filteredActiveTasks(): TodoTask[] {
    if (this.searchQuery.length === 0) {
      return this.tasks;
    }
    const q = this.searchQuery.toLowerCase();
    return this.tasks.filter((t: TodoTask) => t.title.toLowerCase().includes(q));
  }

  @Builder
  private SettingsView() {
    Column({ space: 14 }) {
      this.ServerSettingsMenu()
      this.WidgetAppearanceSettings()
      Button('立即同步')
        .onClick(() => this.syncNow())
        .width('100%')
      Button('清空本地缓存')
        .fontColor($r('app.color.danger_text'))
        .backgroundColor($r('app.color.surface'))
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
      this.ActiveTasksCard()
      this.CompletedTasksCard()

      Text(this.statusText)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .padding({ left: 22, right: 22, top: 4, bottom: 120 })
    .width('100%')
  }

  @Builder
  private AddTaskSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => {
          this.showAddSheet = false;
          this.showDueSheet = false;
        })

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
            .fontSize(14)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(18)
            .height(36)
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
            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.calendar'))
                .fontSize(21)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.hasDue ? $r('app.color.on_accent') : $r('app.color.accent')])
            }
            .width(42)
            .height(42)
            .backgroundColor(this.hasDue ? $r('app.color.accent') : $r('app.color.accent_soft'))
            .borderRadius(21)
            .onClick(() => this.showDatePicker())

            if (this.hasDue) {
              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph($r('sys.symbol.clock'))
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.reminderOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
              }
              .width(42)
              .height(42)
              .backgroundColor(this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.accent_soft'))
              .borderRadius(21)
              .onClick(() => this.showTimePicker())
            }

            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.bell'))
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.reminderOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
            }
            .width(42)
            .height(42)
            .backgroundColor(this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.accent_soft'))
            .borderRadius(21)
            .onClick(() => this.showReminderPopup = !this.showReminderPopup)

            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph($r('sys.symbol.repeat'))
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor([this.repeatOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
            }
            .width(42)
            .height(42)
            .backgroundColor(this.repeatOption !== '无' ? $r('app.color.accent') : $r('app.color.accent_soft'))
            .borderRadius(21)
            .onClick(() => this.showRepeatPopup = !this.showRepeatPopup)
          }

          Blank()
            .layoutWeight(1)

          Button('取消')
            .height(42)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(21)
            .onClick(() => {
              this.showAddSheet = false;
              this.showDueSheet = false;
            })
        }
          .width('100%')
          .margin({ top: 4 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 26 })
      .backgroundColor($r('app.color.surface_translucent'))
      .borderRadius({ topLeft: 28, topRight: 28 })
      .shadow({ radius: 28, color: $r('app.color.icon_background'), offsetX: 0, offsetY: -8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay'))
  }

  @Builder
  private DuePickerSheet() {
    Column() {
      Blank()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => this.showDueSheet = false)

      Column({ space: 12 }) {
        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(23)
              .fontColor([$r('app.color.text_primary')])
          }
            .type(ButtonType.Normal)
            .width(46)
            .height(46)
            .backgroundColor($r('app.color.surface_input'))
            .borderRadius(23)
            .border({ width: 1, color: $r('app.color.divider') })
            .shadow({ radius: 14, color: $r('app.color.icon_background'), offsetX: 0, offsetY: 6 })
            .onClick(() => this.showDueSheet = false)

          Text('日期和时间')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .layoutWeight(1)

          Button() {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(22)
              .fontColor([$r('app.color.on_accent')])
          }
            .width(46)
            .height(46)
            .backgroundColor($r('app.color.accent'))
            .borderRadius(23)
            .shadow({ radius: 16, color: $r('app.color.shadow'), offsetX: 0, offsetY: 8 })
            .onClick(() => {
              this.hasDue = true;
              this.settingPanel = '';
              this.showDueSheet = false;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.duePreview())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)

        Scroll() {
          Column({ space: 12 }) {
            this.CalendarPanel()
            this.DateTimePanel()
          }
          .width('100%')
          .padding({ right: 6 })
        }
        .width('100%')
        .height(448)
        .scrollBar(BarState.Auto)
        .scrollBarWidth('4vp')

        Text('清除')
          .fontSize(17)
          .fontColor($r('app.color.danger'))
          .height(42)
          .width('100%')
          .textAlign(TextAlign.Center)
          .onClick(() => {
            const now = new Date();
            this.selectedDueDate = now;
            this.selectedDueHour = now.getHours();
            this.selectedDueMinute = now.getMinutes();
            this.calendarViewDate = new Date(now.getFullYear(), now.getMonth(), 1);
            this.hasDue = false;
            this.reminderOption = '无';
            this.repeatOption = '无';
            this.settingPanel = '';
            this.showDueSheet = false;
          })
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 16, bottom: 20 })
      .backgroundColor($r('app.color.surface_translucent'))
      .borderRadius({ topLeft: 28, topRight: 28 })
      .shadow({ radius: 28, color: $r('app.color.icon_background'), offsetX: 0, offsetY: -8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay'))
  }

  @Builder
  private EditTaskSheet() {
    Column() {
      if (this.editingTask !== null) {
        Blank()
          .layoutWeight(1)
          .width('100%')
          .onClick(() => {
            this.showEditSheet = false;
            this.editingTask = null;
          })
      }

      if (this.editingTask !== null) {
        Column({ space: 12 }) {
          Row() {
            Text('编辑待办')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Button('完成')
              .fontSize(14)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .borderRadius(18)
              .height(36)
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
              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph($r('sys.symbol.calendar'))
                  .fontSize(21)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.hasDue ? $r('app.color.on_accent') : $r('app.color.accent')])
              }
              .width(42)
              .height(42)
              .backgroundColor(this.hasDue ? $r('app.color.accent') : $r('app.color.accent_soft'))
              .borderRadius(21)
              .onClick(() => this.showDatePicker())

              if (this.hasDue) {
                Stack({ alignContent: Alignment.Center }) {
                  SymbolGlyph($r('sys.symbol.clock'))
                    .fontSize(20)
                    .fontWeight(FontWeight.Medium)
                    .fontColor([this.reminderOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
                }
                .width(42)
                .height(42)
                .backgroundColor(this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.accent_soft'))
                .borderRadius(21)
                .onClick(() => this.showTimePicker())
              }

              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph($r('sys.symbol.bell'))
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.reminderOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
              }
              .width(42)
              .height(42)
              .backgroundColor(this.reminderOption !== '无' ? $r('app.color.accent') : $r('app.color.accent_soft'))
              .borderRadius(21)
              .onClick(() => this.showReminderPopup = !this.showReminderPopup)

              Stack({ alignContent: Alignment.Center }) {
                SymbolGlyph($r('sys.symbol.repeat'))
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.repeatOption !== '无' ? $r('app.color.on_accent') : $r('app.color.accent')])
              }
              .width(42)
              .height(42)
              .backgroundColor(this.repeatOption !== '无' ? $r('app.color.accent') : $r('app.color.accent_soft'))
              .borderRadius(21)
              .onClick(() => this.showRepeatPopup = !this.showRepeatPopup)
            }
            Blank().layoutWeight(1)
          }

          Row({ space: 10 }) {
            Blank()
              .layoutWeight(1)
            Button('取消')
              .height(42)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .borderRadius(21)
              .onClick(() => {
                this.showEditSheet = false;
                this.editingTask = null;
              })
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 26 })
        .backgroundColor($r('app.color.surface_translucent'))
        .borderRadius({ topLeft: 28, topRight: 28 })
        .shadow({ radius: 28, color: $r('app.color.icon_background'), offsetX: 0, offsetY: -8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay'))
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
      this.calendarViewDate = new Date(due.year, due.month - 1, 1);
      this.hasDue = true;
    } else {
      const now = new Date();
      this.selectedDueDate = now;
      this.selectedDueHour = now.getHours();
      this.selectedDueMinute = now.getMinutes();
      this.calendarViewDate = new Date(now.getFullYear(), now.getMonth(), 1);
      this.hasDue = false;
    }
    this.reminderOption = VTodoCodec.detectReminder(task.rawIcs, task.due);
    this.repeatOption = VTodoCodec.detectRepeat(task.rawIcs);
    this.settingPanel = '';
    this.showTimePopup = false;
    this.showReminderPopup = false;
    this.showRepeatPopup = false;
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
  private CalendarPanel() {
    Column({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('app.color.text_tertiary')])
          .width(38)
          .onClick(() => this.changeMonth(-1))
        Text(this.monthTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(24)
          .fontColor([$r('app.color.text_tertiary')])
          .width(38)
          .onClick(() => this.changeMonth(1))
      }
      .width('100%')
      .height(36)

      Grid() {
        ForEach(this.weekdayHeaders(), (label: string) => {
          GridItem() {
            Text(label)
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .height(22)
        }, (label: string) => label)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsGap(0)
      .columnsGap(0)
      .width('100%')
      .height(24)

      Grid() {
        ForEach(this.calendarCells(), (day: number, index: number) => {
          GridItem() {
            if (day === 0) {
              Blank()
                .width('100%')
                .height(37)
            } else {
              Stack({ alignContent: Alignment.Center }) {
                if (this.isSelectedDay(day)) {
                  Circle()
                    .width(38)
                    .height(38)
                    .fill($r('app.color.accent'))
                }
                Column({ space: 1 }) {
                  Text(`${day}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.isSelectedDay(day) ? $r('app.color.on_accent') : $r('app.color.text_primary'))
                    .textAlign(TextAlign.Center)
                  if (!this.isSelectedDay(day) && this.holidayText(day).length > 0) {
                    Text(this.holidayText(day))
                      .fontSize(9)
                      .fontColor($r('app.color.success'))
                      .textAlign(TextAlign.Center)
                      .maxLines(1)
                  } else if (!this.isSelectedDay(day) && this.isRestDay(day)) {
                    Text('休')
                      .fontSize(9)
                      .fontColor($r('app.color.success'))
                      .textAlign(TextAlign.Center)
                  } else {
                    Text(' ')
                      .fontSize(9)
                  }
                }
              }
              .width('100%')
              .height(37)
              .onClick(() => this.selectCalendarDay(day))
            }
          }
        }, (day: number, index: number) => `${index}-${day}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsGap(2)
      .columnsGap(0)
      .width('100%')
      .height(210)
    }
    .width('100%')
  }

  @Builder
  private DateTimePanel() {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(21)
          .fontColor([$r('app.color.text_secondary')])
          .width(30)
        Text('时间')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.hasDue ? this.timeOnlyPreview() : '无')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(15)
          .fontColor([this.hasDue ? $r('app.color.text_disabled') : $r('app.color.divider')])
          .onClick(() => {
            const now = new Date();
            this.selectedDueHour = now.getHours();
            this.selectedDueMinute = now.getMinutes();
            this.hasDue = false;
            this.reminderOption = '无';
          })
      }
      .height(46)
      .width('100%')
      .onClick(() => {
        this.reminderOption = '立刻';
        this.showTimePopup = true;
        this.settingPanel = '';
      })
      Divider()
        .color($r('app.color.divider'))
        .margin({ left: 42 })
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.alarm'))
          .fontSize(21)
          .fontColor([$r('app.color.text_secondary')])
          .width(30)
        Text('提醒')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.reminderOption)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(15)
          .fontColor([this.reminderOption !== '无' ? $r('app.color.text_disabled') : $r('app.color.divider')])
          .onClick(() => {
            this.reminderOption = '无';
          })
      }
      .height(46)
      .width('100%')
      .onClick(() => {
        this.settingPanel = this.settingPanel === 'reminder' ? '' : 'reminder';
      })
      if (this.settingPanel === 'reminder') {
        this.OptionChips(this.reminderOptions(), 'reminder')
      }
      Divider()
        .color($r('app.color.divider'))
        .margin({ left: 42 })
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.repeat'))
          .fontSize(21)
          .fontColor([$r('app.color.text_secondary')])
          .width(30)
        Text('重复')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.repeatOption)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(15)
          .fontColor([this.repeatOption !== '无' ? $r('app.color.text_disabled') : $r('app.color.divider')])
          .onClick(() => {
            this.repeatOption = '无';
          })
      }
      .height(46)
      .width('100%')
      .onClick(() => {
        this.settingPanel = this.settingPanel === 'repeat' ? '' : 'repeat';
      })
      if (this.settingPanel === 'repeat') {
        this.OptionChips(this.repeatOptions(), 'repeat')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface_input'))
    .borderRadius(18)
  }

  @Builder
  private SettingRow(icon: Resource, label: string, value: string, target: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([$r('app.color.text_secondary')])
        .width(30)
      Text(label)
        .fontSize(17)
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
    Row({ space: 8 }) {
      ForEach(options, (option: string) => {
        Text(option)
          .fontSize(13)
          .fontColor((target === 'reminder' ? this.reminderOption : this.repeatOption) === option ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor((target === 'reminder' ? this.reminderOption : this.repeatOption) === option ? $r('app.color.accent') : $r('app.color.surface_input'))
          .borderRadius(14)
          .onClick(() => {
            if (target === 'reminder') {
              this.reminderOption = option;
            } else {
              this.repeatOption = option;
            }
          })
      }, (option: string) => `${target}-${option}`)
    }
    .width('100%')
    .padding({ left: 42, right: 0, bottom: 8 })
  }

  @Builder
  private OptionPopup(title: string, options: string[], target: string) {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          if (target === 'reminder') {
            this.showReminderPopup = false;
          } else {
            this.showRepeatPopup = false;
          }
        })
      Column({ space: 10 }) {
        Text(title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 16, bottom: 4 })

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(options, (option: string) => {
            Text(option)
              .fontSize(13)
              .fontColor((target === 'reminder' ? this.reminderOption : this.repeatOption) === option ? $r('app.color.on_accent') : $r('app.color.text_secondary'))
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor((target === 'reminder' ? this.reminderOption : this.repeatOption) === option ? $r('app.color.accent') : $r('app.color.surface_input'))
              .borderRadius(14)
              .margin(4)
              .onClick(() => {
                if (target === 'reminder') {
                  this.reminderOption = option;
                } else {
                  this.repeatOption = option;
                }
              })
          }, (option: string) => `${target}-${option}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
      }
      .width('90%')
      .backgroundColor($r('app.color.surface_translucent'))
      .borderRadius(20)
      .shadow({ radius: 28, color: $r('app.color.shadow'), offsetX: 0, offsetY: 8 })
      .backdropBlur(20)
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          if (target === 'reminder') {
            this.showReminderPopup = false;
          } else {
            this.showRepeatPopup = false;
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay'))
  }

  private hourRange(): string[] {
    const range: string[] = [];
    for (let h = 0; h < 24; h++) {
      range.push(h < 10 ? `0${h}` : `${h}`);
    }
    return range;
  }

  private minuteRange(): string[] {
    const range: string[] = [];
    for (let m = 0; m < 60; m++) {
      range.push(m < 10 ? `0${m}` : `${m}`);
    }
    return range;
  }

  @Builder
  private TimePickerPopup() {
    Column() {
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          this.hasDue = true;
          this.reminderOption = '立刻';
          this.showTimePopup = false;
        })
      Column() {
        Row() {
          TextPicker({ range: this.hourRange(), selected: this.selectedDueHour })
            .onChange((value: string | string[], index: number | number[]) => {
              this.selectedDueHour = index as number;
            })
            .layoutWeight(1)
            .backgroundColor($r('app.color.surface_input'))
            .borderRadius(14)
          Text('时')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 6, right: 10 })
          TextPicker({ range: this.minuteRange(), selected: this.selectedDueMinute })
            .onChange((value: string | string[], index: number | number[]) => {
              this.selectedDueMinute = index as number;
            })
            .layoutWeight(1)
            .backgroundColor($r('app.color.surface_input'))
            .borderRadius(14)
          Text('分')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 6, right: 0 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 16 })

        Divider()
          .color($r('app.color.divider'))
          .width('100%')

        Row({ space: 16 }) {
          Button('取消')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.surface'))
            .borderRadius(20)
            .height(44)
            .layoutWeight(1)
            .onClick(() => this.showTimePopup = false)
          Button('确定')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(20)
            .height(44)
            .layoutWeight(1)
            .onClick(() => {
              this.hasDue = true;
              this.reminderOption = '立刻';
              this.showTimePopup = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 20 })
      }
      .width('72%')
      .backgroundColor($r('app.color.surface_translucent'))
      .borderRadius(20)
      .shadow({ radius: 28, color: $r('app.color.shadow'), offsetX: 0, offsetY: 8 })
      .backdropBlur(20)
      Blank()
        .layoutWeight(1)
        .onClick(() => {
          this.hasDue = true;
          this.reminderOption = '立刻';
          this.showTimePopup = false;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay'))
  }

  @Builder
  private BottomTabItem(index: number, icon: Resource, label: string) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(21)
        .fontColor([this.selectedTabIndex === index ? $r('app.color.accent') : $r('app.color.text_secondary')])
      Text(label)
        .fontSize(11)
        .fontWeight(this.selectedTabIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTabIndex === index ? $r('app.color.accent') : $r('app.color.text_secondary'))
    }
    .width(68)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selectedTabIndex === index ? $r('app.color.accent_soft') : $r('app.color.transparent'))
    .borderRadius(24)
    .onClick(() => this.selectedTabIndex = index)
  }

  @Builder
  private AddTodoBottomButton() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor([$r('app.color.accent')])
    }
    .width(58)
    .height(58)
    .onClick(() => this.openAddSheet())
  }

  @Builder
  private FloatingBottomBar() {
    Row() {
      Blank()
        .width(58)

      Row({ space: 4 }) {
        this.BottomTabItem(0, $r('sys.symbol.list_bullet'), '首页')
        this.BottomTabItem(1, $r('sys.symbol.gearshape'), '设置')
      }
      .height(58)
      .padding({ left: 6, right: 6 })
      .backgroundColor('#DDF9FAFC')
      .borderRadius(29)
      .backdropBlur(24)
      .shadow({ radius: 14, color: $r('app.color.shadow'), offsetX: 0, offsetY: 6 })
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      Button() {
        this.AddTodoBottomButton()
      }
      .type(ButtonType.Normal)
      .width(58)
      .height(58)
      .backgroundColor('#DDF9FAFC')
      .borderRadius(29)
      .backdropBlur(24)
      .shadow({ radius: 14, color: $r('app.color.shadow'), offsetX: 0, offsetY: 6 })
    }
    .width('100%')
    .height(58)
    .padding({ left: 22, right: 22, bottom: 44 })
    .backgroundColor($r('app.color.transparent'))
  }

  @Builder
  private BottomImmersiveMask() {
    Column()
      .width('100%')
      .height(124)
      .linearGradient({
        angle: 180,
        colors: [
          [$r('app.color.transparent'), 0.0],
          [$r('app.color.page_background'), 0.78],
          [$r('app.color.page_background'), 1.0]
        ]
      })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
        if (this.configured) {
          Row() {
            Text(this.selectedTabIndex === 1 ? 'Cavdal Tasks' : '待办事项')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            Stack({ alignContent: Alignment.Center }) {
              SymbolGlyph(this.searchQuery.length > 0 ? $r('sys.symbol.xmark') : $r('sys.symbol.magnifyingglass'))
                .fontSize(16)
                .fontColor([$r('app.color.text_tertiary')])
            }
            .width(38)
            .height(38)
            .backgroundColor($r('app.color.icon_background'))
            .borderRadius(19)
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
            TextInput({ placeholder: '搜索待办事项...', text: this.searchQuery })
              .onChange((value: string) => this.searchQuery = value)
              .height(44)
              .fontSize(16)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(18)
              .margin({ left: 22, right: 22, bottom: 4 })
          }

          if (this.selectedTabIndex === 0) {
            Refresh({ refreshing: $$this.refreshing, promptText: '正在同步' }) {
              Scroll() {
                Column() {
                  this.HomeView()
                }
                .width('100%')
                .backgroundColor($r('app.color.page_background'))
              }
              .width('100%')
              .scrollBar(BarState.Auto)
              .align(Alignment.TopStart)
            }
            .layoutWeight(1)
            .width('100%')
            .pullToRefresh(this.configured && this.selectedTabIndex === 0)
            .refreshOffset(64)
            .onRefreshing(() => {
              this.refreshFromPull();
            })
          } else {
            Scroll() {
              Column() {
                this.SettingsView()
              }
              .width('100%')
              .backgroundColor($r('app.color.page_background'))
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Auto)
            .align(Alignment.TopStart)
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

      if (this.configured) {
        this.BottomImmersiveMask()
        this.FloatingBottomBar()
      }

      if (this.showAddSheet) {
        this.AddTaskSheet()
      }

      if (this.showEditSheet) {
        this.EditTaskSheet()
      }

      if (this.showReminderPopup) {
        this.OptionPopup('提醒', this.reminderOptions(), 'reminder')
      }

      if (this.showRepeatPopup) {
        this.OptionPopup('重复', this.repeatOptions(), 'repeat')
      }

      if (this.showTimePopup) {
        this.TimePickerPopup()
      }
    }
    .height('100%')
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
