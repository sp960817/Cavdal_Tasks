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
export struct TaskCards {
  @Prop activeTasks: TodoTask[] = [];
  @Prop completedTasks: TodoTask[] = [];
  @Prop completedTotalCount: number = 0;
  // Retained for callers that still calculate legacy card metrics.
  @Prop activeHeight: number = 108;
  @Prop searchActive: boolean = false;
  @State completingIds: string[] = [];
  @State removedIds: string[] = [];
  @State showCompletedSheet: boolean = false;
  onToggleTask: (task: TodoTask, done: boolean) => void =
    (_task: TodoTask, _done: boolean): void => {};
  onEditTask: (task: TodoTask) => void = (_task: TodoTask): void => {};
  onDeleteTask: (task: TodoTask) => void = (_task: TodoTask): void => {};
  onAddTask: () => void = (): void => {};

  private isCompleting(taskId: string): boolean {
    return this.completingIds.indexOf(taskId) >= 0;
  }

  private isRemoved(taskId: string): boolean {
    return this.removedIds.indexOf(taskId) >= 0;
  }

  private visibleActiveTasks(): TodoTask[] {
    return this.activeTasks.filter((task: TodoTask) => !this.isRemoved(task.id));
  }

  private syncLabel(task: TodoTask): string {
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

  private animateComplete(task: TodoTask): void {
    if (this.isCompleting(task.id) || this.isRemoved(task.id)) {
      return;
    }
    this.completingIds = this.completingIds.concat(task.id);
    // Keep persistence independent of platform animation-finish callbacks.
    setTimeout(() => {
      if (!this.isCompleting(task.id)) {
        return;
      }
      this.removedIds = this.removedIds.concat(task.id);
      this.completingIds = this.completingIds.filter((id: string) => id !== task.id);
      this.onToggleTask(task, true);
      // Restore the row if persistence fails.
      setTimeout(() => {
        this.removedIds = this.removedIds.filter((id: string) => id !== task.id);
      }, 2000);
    }, 260);
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

  @Builder
  private ActiveTaskRow(row: RepeatItem<TodoTask>) {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Toggle({ type: ToggleType.Checkbox, isOn: this.isCompleting(row.item.id) })
          .selectedColor($r('app.color.accent'))
          .width(28)
          .height(28)
          .accessibilityText(`完成 ${row.item.title}`)
          .onChange((isOn: boolean) => {
            if (isOn) {
              this.animateComplete(row.item);
            }
          })
      }
      .width(40)
      .height(64)

      Column({ space: 5 }) {
        Text(row.item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isCompleting(row.item.id) ?
            $r('app.color.text_tertiary') : $r('app.color.text_primary'))
          .decoration(this.isCompleting(row.item.id) ? {
            type: TextDecorationType.LineThrough,
            color: $r('app.color.text_tertiary')
          } : { type: TextDecorationType.None })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        this.TaskMetadata(row)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ top: 12, bottom: 12, right: 10 })
      .onClick(() => this.onEditTask(row.item))
    }
    .width('100%')
    .constraintSize({ minHeight: 72 })
    .padding({ left: 4 })
    .borderRadius(18)
    .backgroundColor(row.item.syncState === 'conflict' ?
      $r('app.color.danger_soft') : $r('app.color.surface'))
    .opacity(this.isCompleting(row.item.id) ? 0 : 1)
    .translate({ x: 0, y: this.isCompleting(row.item.id) ? 6 : 0 })
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  @Builder
  private CompletedTaskRow(row: RepeatItem<TodoTask>) {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Toggle({ type: ToggleType.Checkbox, isOn: true })
          .selectedColor($r('app.color.accent'))
          .width(28)
          .height(28)
          .accessibilityText(`恢复 ${row.item.title}`)
          .onChange((isOn: boolean) => {
            if (!isOn) {
              this.onToggleTask(row.item, false);
            }
          })
      }
      .width(40)
      .height(64)

      Column({ space: 5 }) {
        Text(row.item.title)
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
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 4 })
    .borderRadius(18)
    .backgroundColor($r('app.color.surface'))
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
      .borderRadius(18)
      .accessibilityText(`删除 ${row.item.title}`)
      .onClick(() => this.onDeleteTask(row.item))
  }

  @Builder
  private EmptyTasks() {
    Scroll() {
      Column({ space: 8 }) {
        Image($r('app.media.material_empty_tray'))
          .width(88)
          .height(88)
          .objectFit(ImageFit.Contain)
          .accessibilityLevel('no')
        Text(this.searchActive ? '没有找到相关待办' : '给今天留一点从容')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
        Text(this.searchActive ? '试试其他关键词，也可以查看已完成事项' : '把想到的事记下来，再一件件完成。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
        if (!this.searchActive) {
          Button('记下一件事')
            .type(ButtonType.Capsule)
            .height(40)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.accent_soft'))
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
        Text(`${this.visibleActiveTasks().length}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.accent_soft'))
          .borderRadius(10)
        Blank()
        Text('左滑管理')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height(30)
      .padding({ left: 5, right: 5 })

      if (this.visibleActiveTasks().length === 0) {
        this.EmptyTasks()
      } else {
        List({ space: 8 }) {
          Repeat(this.visibleActiveTasks()).each((row: RepeatItem<TodoTask>) => {
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
    .width('100%')
    .height(52)
    .padding({ left: 17, right: 17 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(20)
    .onClick(() => this.showCompletedSheet = true)
  }

  @Builder
  private CompletedTasksSheetContent() {
    Column({ space: 18 }) {
      Row() {
        Column({ space: 4 }) {
          Text('做过的每一件小事')
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
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.surface_input'))
        .accessibilityText('关闭已完成事项')
        .onClick(() => this.showCompletedSheet = false)
      }
      .width('100%')

      if (this.completedTasks.length === 0) {
        Column({ space: 12 }) {
          Image($r('app.media.material_empty_tray'))
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
        List({ space: 8 }) {
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
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 28 })
  }

  build() {
    Column({ space: 12 }) {
      this.ActiveTasksCard()
      this.CompletedTasksCard()
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showCompletedSheet, this.CompletedTasksSheetContent(), this.completedSheetOptions())
  }
}
