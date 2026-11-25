import { deviceInfo } from '@kit.BasicServicesKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { CatSnack } from '../common/CatSnack';
import { TaskTextLayout } from '../common/TaskTextLayout';
import { TodoTask } from '../../model/TaskModels';
import { formatDueForDisplay } from '../../formatters/DueTimeFormatter';
import { VTodoCodec } from '../../caldav/VTodoCodec';
import { taskSheetOptions } from '../common/MaterialStyles';

// Non-virtual Repeat retains the old item when its key is unchanged.
// Include the display/edit snapshot, but not the import-time updatedAt value.
function taskRenderKey(task: TodoTask): string {
  return JSON.stringify([
    task.id, task.uid, task.href, task.calendarHref, task.etag,
    task.title, task.description, task.due, `${task.priority}`, task.status,
    task.completedAt, `${task.percentComplete}`, task.rawIcs, task.syncState
  ]);
}

@Component
struct SnackStrip {
  @Prop taskId: string = '';
  @Prop bites: number = 0;
  @State stripWidth: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        CatSnack({ taskId: this.taskId }).width(this.stripWidth || '100%').height(14)
          .position({ x: 0, y: 0 })
      }.height(14).width(((7 - this.bites) * 100 / 7) + '%').clip(true)
    }.width('85%').height(14)
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions) => {
        if (typeof size.width === 'number') this.stripWidth = size.width;
      })
  }
}

@Component
export struct TaskCards {
  @State menuTaskId: string = '';
  private titleLayout: TaskTextLayout = new TaskTextLayout();
  @Prop activeTasks: TodoTask[] = [];
  @Prop completedTasks: TodoTask[] = [];
  @Prop completedTotalCount: number = 0;
  @Prop collection: string = '全部';
  @Prop statusText: string = '';
  @Prop totalCount: number = 0;
  @Prop compactRows: boolean = false;
  @Prop addOnLeft: boolean = false;
  @Prop feedingAnimation: boolean = true;
  @Prop searchActive: boolean = false;
  onCollection: (value: string) => void = (_value: string): void => {};
  private collections: string[] = ['全部', '今天', '近七天', '逾期', '重要'];
  @State feedingId: string = '';
  @State catX: number = 0;
  @State catY: number = 0;
  @State bites: number = 0;
  @State landed: boolean = false;
  @State bowlEmpty: boolean = false;
  @State justFed: boolean = false;
  private timer: number = -1;
  private pendingMeal?: TodoTask;
  @State showCompletedSheet: boolean = false;
  onToggleTask: (task: TodoTask, done: boolean) => void =
    (_task: TodoTask, _done: boolean): void => {};
  onEditTask: (task: TodoTask) => void = (_task: TodoTask): void => {};
  onDeleteTask: (task: TodoTask) => void = (_task: TodoTask): void => {};
  onAddTask: () => void = (): void => {};

  private syncLabel(task: TodoTask): string {
    if (!task.calendarHref && task.syncState === 'pending') return '本机';
    if (task.syncState === 'conflict') {
      return '同步冲突';
    }
    return task.syncState === 'error' ? '同步失败' : '待同步';
  }

  private completedSheetOptions(): SheetOptions {
    const options = taskSheetOptions();
    options.detents = [SheetSize.MEDIUM, SheetSize.LARGE];
    return options;
  }

  private finishMeal(): void {
    clearInterval(this.timer);
    this.timer = -1;
    const task = this.pendingMeal;
    this.pendingMeal = undefined;
    this.feedingId = '';
    if (task !== undefined) {
      this.justFed = true;
      this.onToggleTask(task, true);
    }
  }

  aboutToDisappear(): void {
    if (this.pendingMeal !== undefined) this.finishMeal();
  }

  private animateComplete(task: TodoTask): void {
    if (this.pendingMeal !== undefined) return;
    this.pendingMeal = task;
    if (!this.feedingAnimation) {
      this.finishMeal();
      return;
    }
    const ui = this.getUIContext();
    const bounds = ui.getComponentUtils();
    try {
      const stage = bounds.getRectangleById('feeding-stage');
      const perch = bounds.getRectangleById('cat-perch');
      const snack = bounds.getRectangleById('snack-' + task.id);
      const bowl = bounds.getRectangleById('bowl-' + task.id);
      if (snack.size.width <= 0 || stage.size.width <= 0) {
        this.finishMeal();
        return;
      }
      // Positions are relative to the home Stack, even after scrolling the list.
      const startX = ui.px2vp(perch.windowOffset.x - stage.windowOffset.x);
      const startY = ui.px2vp(perch.windowOffset.y - stage.windowOffset.y);
      const left = ui.px2vp(snack.windowOffset.x - stage.windowOffset.x);
      const span = ui.px2vp(snack.size.width);
      const biteY = ui.px2vp(snack.windowOffset.y - stage.windowOffset.y) - 42;
      const bowlX = ui.px2vp(bowl.windowOffset.x - stage.windowOffset.x + bowl.size.width / 2) - 6;
      const bowlY = ui.px2vp(bowl.windowOffset.y - stage.windowOffset.y + bowl.size.height / 2) - 44;
      this.catX = startX;
      this.catY = startY;
      this.feedingId = task.id;
      this.bites = 0;
      this.bowlEmpty = false;
      this.landed = false;
      const start = Date.now();
      this.timer = setInterval(() => {
        const elapsed = Date.now() - start;
        if (elapsed < 380) {
          const t = elapsed / 380;
          this.catX = startX + (left + span - 8 - startX) * t;
          this.catY = startY + (biteY - startY) * t - 32 * Math.sin(Math.PI * t);
        } else if (elapsed < 1080) {
          const progress = (elapsed - 380) / 700;
          this.landed = true;
          this.bites = Math.floor(progress * 7);
          this.catX = left + span * (1 - progress) - 8;
          this.catY = biteY + 3 * Math.sin(progress * 14 * Math.PI);
        } else if (elapsed < 1480) {
          const t = Math.min(1, (elapsed - 1080) / 160);
          this.bites = 7;
          this.catX = left - 8 + (bowlX - left + 8) * t;
          this.catY = biteY + (bowlY - biteY) * t;
          this.bowlEmpty = elapsed >= 1280;
        } else {
          this.finishMeal();
        }
      }, 24);
    } catch (_err) {
      this.finishMeal();
    }
  }

  @Builder
  private CatPerch() {
    Row({ space: 4 }) {
      Column({ space: 5 }) {
        Text(this.justFed ? '呼噜，吃饱啦！' : '猫咪的饭点')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text(this.totalCount === 0 ? '清单空了，一起晒会儿太阳吧。' : '完成一件事，喂小猫一口。')
          .fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(2)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Stack() {
        Image($r('app.media.cat_grass')).width('100%').height('100%').objectFit(ImageFit.Fill)
          .accessibilityLevel('no')
        Image($r('app.media.cat_idle')).width(this.compactRows ? 50 : 62).height(this.compactRows ? 52 : 67)
          .objectFit(ImageFit.Contain).id('cat-perch').opacity(this.feedingId === '' ? 1 : 0)
          .accessibilityText('长毛虎斑猫')
      }.width(this.compactRows ? 118 : 134).height(this.compactRows ? 68 : 88)
    }.width('100%').padding({ left: 4 }).height(this.compactRows ? 72 : 96)
  }

  @Builder
  private CollectionBar() {
    Row() {
      ForEach(this.collections, (label: string) => {
        Button() {
          Column({ space: 5 }) {
            Text(label).fontSize(14)
              .fontWeight(label === this.collection ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(label === this.collection ? $r('app.color.accent') : $r('app.color.text_secondary'))
            Row().width(16).height(3).backgroundColor(label === this.collection ? $r('app.color.accent') : Color.Transparent)
          }
        }.type(ButtonType.Normal).layoutWeight(1).height(42).padding(0)
          .backgroundColor(Color.Transparent).accessibilityText(label === this.collection ? label + '，已选中' : label)
          .onClick(() => this.onCollection(label))
      }, (label: string) => label)
    }.width('100%')
  }

  @Builder
  private TaskMetadata(row: RepeatItem<TodoTask>) {
    Row({ space: 7 }) {
      if (row.item.due.length > 0) {
        Text(formatDueForDisplay(row.item.due))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else if (row.item.syncState === 'synced') {
        Text(row.item.description.length > 0 ? row.item.description : '随心安排')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      if (VTodoCodec.detectReminder(row.item.rawIcs, row.item.due) !== '无') {
        SymbolGlyph($r('sys.symbol.bell'))
          .fontSize(12)
          .fontColor([$r('app.color.accent')])
          .accessibilityText('已设置提醒')
      }
      if (row.item.syncState !== 'synced') {
        Text(this.syncLabel(row.item))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(row.item.syncState === 'conflict' || row.item.syncState === 'error' ?
            $r('app.color.danger_text') : $r('app.color.warning_text'))
          .maxLines(1)
      }
    }
    .width('100%')
    .height(18)
  }

  private taskMenuOptions(taskId: string, completed: boolean): ContextMenuOptions {
    const options: ContextMenuOptions = {
      onDisappear: () => {
        if (this.menuTaskId === taskId) this.menuTaskId = '';
      }
    };
    if (deviceInfo.apiAvailable('26.0.0')) {
      const columns = completed ? 2 : 3;
      options.gridStyle = { count: columns, horizontalSize: columns };
    }
    return options;
  }

  private taskActions(task: TodoTask, completed: boolean): MenuElement[] {
    const items: MenuElement[] = [{
      icon: completed ? $r('app.media.bowl_empty') : $r('app.media.bowl_full'),
      value: completed ? '恢复' : '喂猫完成',
      action: () => {
        if (completed) this.onToggleTask(task, false);
        else this.animateComplete(task);
      }
    }];
    if (!completed) {
      items.push({ symbolIcon: new SymbolGlyphModifier($r('sys.symbol.doc_plaintext_and_pencil_fill')),
        value: '编辑', action: () => this.onEditTask(task) });
    }
    items.push({ symbolIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
      value: '删除', action: () => this.onDeleteTask(task) });
    return items;
  }

  @Builder
  private TaskMenuButton(task: TodoTask, completed: boolean) {
    Button('···').type(ButtonType.Normal).borderRadius(2).width(40).height(44).padding(0)
      .fontWeight(FontWeight.Bold).fontColor($r('app.color.text_secondary')).backgroundColor(Color.Transparent)
      .accessibilityText('更多操作：' + task.title)
      .onClick(() => { this.menuTaskId = task.id; })
      .bindMenu(this.menuTaskId === task.id, this.taskActions(task, completed), this.taskMenuOptions(task.id, completed))
  }

  @Builder
  private ActiveTaskRow(row: RepeatItem<TodoTask>) {
    Row({ space: 8 }) {
      Button() {
        Image(this.feedingId === row.item.id && this.bowlEmpty ? $r('app.media.bowl_empty') : $r('app.media.bowl_full'))
          .width(36).height(36).id('bowl-' + row.item.id)
      }.type(ButtonType.Normal).width(46).height(46).padding(0).borderRadius(2)
        .backgroundColor(Color.Transparent).accessibilityText('完成并喂猫：' + row.item.title)
        .onClick(() => this.animateComplete(row.item))

      Column({ space: this.compactRows ? 2 : 4 }) {
        Text((row.item.priority > 0 && row.item.priority < 5 ? '★ ' : '') + row.item.title)
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .attributeModifier(this.titleLayout)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        this.TaskMetadata(row)
        SnackStrip({ taskId: row.item.id, bites: this.feedingId === row.item.id ? this.bites : 0 })
          .id('snack-' + row.item.id)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        .onClick(() => {
          if (!this.menuTaskId) this.onEditTask(row.item);
        })
        .priorityGesture(LongPressGesture({ duration: 450 }).onAction(() => { this.menuTaskId = row.item.id; }))
      this.TaskMenuButton(row.item, false)
    }.width('100%').padding({ top: this.compactRows ? 5 : 10, bottom: this.compactRows ? 5 : 10 })
  }

  @Builder
  private CompletedTaskRow(row: RepeatItem<TodoTask>) {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Button() {
          Image($r('app.media.bowl_empty')).width(32).height(32)
        }.type(ButtonType.Normal).width(40).height(44).padding(0)
          .backgroundColor(Color.Transparent).accessibilityText('恢复 ' + row.item.title)
          .onClick(() => this.onToggleTask(row.item, false))
      }
      .width(40)
      .height(64)

      Column({ space: 5 }) {
        Text(row.item.title)
          .attributeModifier(this.titleLayout)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .decoration({
            type: TextDecorationType.LineThrough,
            color: $r('app.color.text_tertiary')
          })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (row.item.due.length > 0) {
          Text(formatDueForDisplay(row.item.due))
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ top: 12, bottom: 12, right: 10 })
      .priorityGesture(LongPressGesture({ duration: 450 }).onAction(() => { this.menuTaskId = row.item.id; }))
      this.TaskMenuButton(row.item, true)
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 4 })
  }

  @Builder
  private DeleteSwipeAction(row: RepeatItem<TodoTask>) {
    Button('删除')
      .type(ButtonType.Normal)
      .fontSize(14)
      .fontColor($r('app.color.on_accent'))
      .fontWeight(FontWeight.Medium)
      .width(72)
      .height('100%')
      .backgroundColor($r('app.color.danger'))
      .borderRadius(2)
      .accessibilityText(`删除 ${row.item.title}`)
      .onClick(() => this.onDeleteTask(row.item))
  }

  @Builder
  private EmptyTasks() {
    Scroll() {
      Column({ space: 8 }) {
        Image($r('app.media.bowl_empty'))
          .width(88)
          .height(88)
          .objectFit(ImageFit.Contain)
          .accessibilityLevel('no')
        Text(this.searchActive ? '没有找到相关待办' : this.collection === '全部' ? '碗洗好啦' : '这个清单是空的')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
        Text(this.searchActive ? '试试其他关键词，也可以查看已完成事项' : '想到什么就记下来，小猫在这里陪你。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
        if (!this.searchActive) {
          Button('记下一件事')
            .type(ButtonType.Normal)
            .height(40)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
            .backgroundColor(Color.Transparent)
            .padding({ left: 22, right: 22 })
            .margin({ top: 4 })
            .onClick(() => this.onAddTask())
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 16, left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Center)
  }

  @Builder
  private ActiveTasksCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.searchActive ? '搜索结果' : '待办清单')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.activeTasks.length}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))

        Blank()
        Text('点碗完成 · 长按管理')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height(30)
      .padding({ left: 5, right: 5 })

      if (this.activeTasks.length === 0) {
        this.EmptyTasks()
      } else {
        List({ space: 3 }) {
          Repeat(this.activeTasks).each((row: RepeatItem<TodoTask>) => {
            ListItem() {
              this.ActiveTaskRow(row)
            }
            .swipeAction({
              end: {
                builder: () => {
                  this.DeleteSwipeAction(row)
                },
                onAction: () => this.onDeleteTask(row.item)
              }
            })
          }).key((task: TodoTask) => taskRenderKey(task))
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 54, endMargin: 8 })
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private CompletedTasksCard() {
    Button() {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(20)
          .fontColor([$r('app.color.accent')])
        Text('已完成')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(this.searchActive ?
          `${this.completedTasks.length} / ${this.completedTotalCount}` : `${this.completedTotalCount} 项`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
    }
    .type(ButtonType.Normal)
    .layoutWeight(1)
    .height(46)
    .padding({ left: 4, right: 10 })
    .backgroundColor(Color.Transparent)
    .onClick(() => this.showCompletedSheet = true)
  }

  @Builder
  private CompletedTasksSheetContent() {
    Column({ space: 18 }) {
      Row() {
        Column({ space: 4 }) {
          Text('小猫的空碗收藏')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.searchActive ?
            `找到 ${this.completedTasks.length} 项已完成事项` : `已完成 ${this.completedTotalCount} 项，继续保持`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Normal)
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.surface_input'))
        .accessibilityText('关闭已完成事项')
        .onClick(() => this.showCompletedSheet = false)
      }
      .width('100%')

      if (this.completedTasks.length === 0) {
        Column({ space: 12 }) {
          Image($r('app.media.bowl_empty'))
            .width(112)
            .height(112)
            .objectFit(ImageFit.Contain)
            .accessibilityLevel('no')
          Text(this.searchActive ? '没有匹配的已完成事项' : '完成的事项会收纳在这里')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 3 }) {
          Repeat(this.completedTasks).each((row: RepeatItem<TodoTask>) => {
            ListItem() {
              this.CompletedTaskRow(row)
            }
            .swipeAction({
              end: {
                builder: () => {
                  this.DeleteSwipeAction(row)
                },
                onAction: () => this.onDeleteTask(row.item)
              }
            })
          }).key((task: TodoTask) => taskRenderKey(task))
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 54, endMargin: 8 })
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 28 })
  }

  @Builder
  private AddButton() {
    Button('+').type(ButtonType.Circle).width(46).height(46).fontSize(27)
      .padding(0).fontColor($r('app.color.on_accent')).backgroundColor($r('app.color.accent'))
      .accessibilityText('添加待办').onClick(() => this.onAddTask())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 8 }) {
        this.CatPerch()
        this.CollectionBar()
        this.ActiveTasksCard()
        Row({ space: 8 }) {
          if (this.addOnLeft) { this.AddButton() }
          this.CompletedTasksCard()
          if (!this.addOnLeft) { this.AddButton() }
        }.width('100%')
        Text(this.statusText).fontSize(10).fontColor($r('app.color.text_tertiary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.width('100%').height('100%').enabled(this.feedingId.length === 0)
      if (this.feedingId.length > 0) {
        Image(this.landed ? $r('app.media.cat_eat') : $r('app.media.cat_jump'))
          .width(62).height(50).objectFit(ImageFit.Contain)
          .position({ x: this.catX, y: this.catY }).hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }
    }
    .width('100%').height('100%').id('feeding-stage')
    .bindSheet($$this.showCompletedSheet, this.CompletedTasksSheetContent(), this.completedSheetOptions())
  }
}
