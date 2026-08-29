import { TodoTask } from '../../model/TaskModels';
import { formatDueForDisplay } from '../../formatters/DueTimeFormatter';
import { VTodoCodec } from '../../caldav/VTodoCodec';

@Component
export struct TaskCards {
  @Prop activeTasks: TodoTask[] = [];
  @Prop completedTasks: TodoTask[] = [];
  @Prop completedTotalCount: number = 0;
  @Prop activeHeight: number = 108;
  // 正在播放"完成"动画的任务 id 集合，驱动删除线/淡出过渡
  @State completingIds: string[] = [];
  // 动画已结束、已从视觉列表移除（不等网络刷新）的任务 id 集合
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

  // 渲染用列表：过滤掉已完成动画、等待数据层确认的任务
  private visibleActiveTasks(): TodoTask[] {
    return this.activeTasks.filter((t: TodoTask) => !this.isRemoved(t.id));
  }

  // 行级隐式动画会跟随 completingIds 的状态变化稳定执行。
  private animateComplete(task: TodoTask): void {
    if (this.isCompleting(task.id) || this.isRemoved(task.id)) {
      return;
    }
    this.completingIds = this.completingIds.concat(task.id);
    // 不依赖 animateTo 的 onFinish 回调：部分设备上该回调未触发时，
    // 任务会永久停留在当前列表。动画结束后再更新数据和视觉列表。
    setTimeout(() => {
      if (!this.isCompleting(task.id)) {
        return;
      }
      this.removedIds = this.removedIds.concat(task.id);
      this.completingIds = this.completingIds.filter((id: string) => id !== task.id);
      this.onToggleTask(task, true);
      // 若同步失败，恢复显示供用户重试。
      setTimeout(() => {
        this.removedIds = this.removedIds.filter((id: string) => id !== task.id);
      }, 2000);
    }, 260);
  }

  @Builder
  private ActiveTaskRow(task: TodoTask) {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        Stack({ alignContent: Alignment.Center }) {
          Toggle({ type: ToggleType.Checkbox, isOn: this.isCompleting(task.id) })
            .onChange((isOn: boolean) => {
              if (isOn) {
                this.animateComplete(task);
              }
            })
            .width(22)
            .height(22)
        }
        .width(36)
        .height(40)

        Text(task.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isCompleting(task.id) ?
            $r('app.color.text_tertiary') : $r('app.color.text_primary'))
          .decoration(this.isCompleting(task.id) ? {
            type: TextDecorationType.LineThrough,
            color: $r('app.color.text_tertiary')
          } : { type: TextDecorationType.None })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (task.due.length > 0) {
          Text(formatDueForDisplay(task.due))
            .fontSize(14)
            .fontColor(this.isCompleting(task.id) ?
              $r('app.color.text_disabled') : $r('app.color.text_secondary'))
        }

        if (VTodoCodec.detectReminder(task.rawIcs, task.due) !== '无') {
          SymbolGlyph($r('sys.symbol.bell'))
            .fontSize(14)
            .fontColor([this.isCompleting(task.id) ?
              $r('app.color.text_disabled') : $r('app.color.accent')])
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onEditTask(task))

      if (task.syncState !== 'synced') {
        Row({ space: 5 }) {
          Circle({ width: 6, height: 6 })
            .fill(task.syncState === 'conflict' ?
              $r('app.color.danger') : $r('app.color.warning_text'))
          Text(task.syncState === 'pending' ? '待同步' :
            task.syncState === 'conflict' ? '同步冲突' : task.syncState)
            .fontSize(12)
            .fontWeight(task.syncState === 'conflict' ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(task.syncState === 'conflict' ?
              $r('app.color.danger_text') : $r('app.color.warning_text'))
        }
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .backgroundColor(task.syncState === 'conflict' ?
          $r('app.color.danger_soft') : Color.Transparent)
        .borderRadius(8)
        .width('100%')
      }
    }
    .width('100%')
    .height(task.syncState !== 'synced' ? 60 : 44)
    .padding({ left: task.syncState === 'conflict' ? 10 : 0, right: 12 })
    .borderRadius(10)
    .backgroundColor(task.syncState === 'conflict' ?
      $r('app.color.danger_soft') : Color.Transparent)
    .opacity(this.isCompleting(task.id) ? 0 : 1)
    .translate({ x: 0, y: this.isCompleting(task.id) ? 6 : 0 })
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  @Builder
  private CompletedTaskRow(task: TodoTask) {
    Row({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        Toggle({ type: ToggleType.Checkbox, isOn: true })
          .onChange((isOn: boolean) => {
            if (!isOn) {
              this.onToggleTask(task, false);
            }
          })
          .width(22)
          .height(22)
      }
      .width(36)
      .height(40)

      Text(task.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_tertiary'))
        .decoration({
          type: TextDecorationType.LineThrough,
          color: $r('app.color.text_tertiary')
        })
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
    .height(40)
    .padding({ left: 0, right: 12 })
    .alignItems(VerticalAlign.Center)
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
    .borderRadius({ topRight: 14, bottomRight: 14 })
    .onClick(() => this.onDeleteTask(task))
  }

  @Builder
  private ActiveTasksCard() {
    Column() {
      Row({ space: 6 }) {
        Text('未完成')
        .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
        Text(`${this.visibleActiveTasks().length}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
        Blank()
      }
      .width('100%')
      .height(30)
      .padding({ left: 4, right: 8 })

      if (this.visibleActiveTasks().length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(44)
            .fontColor([$r('app.color.text_disabled')])
            .opacity(0.6)
          Text('没有进行中的待办')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('点击下方按钮，添加第一个待办事项')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(14)
                .fontColor([$r('app.color.on_accent')])
              Text('添加待办')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.on_accent'))
            }
          }
          .type(ButtonType.Normal)
          .height(38)
          .padding({ left: 20, right: 20 })
          .backgroundColor($r('app.color.accent'))
          .borderRadius(19)
          .margin({ top: 2 })
          .onClick(() => this.onAddTask())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.visibleActiveTasks(), (task: TodoTask) => {
            ListItem() {
              this.ActiveTaskRow(task)
            }
            .swipeAction({
              end: {
                builder: () => {
                  this.DeleteSwipeAction(task)
                },
                onAction: () => this.onDeleteTask(task)
              }
            })
          }, (task: TodoTask) => `${task.id}-${task.updatedAt}-${task.syncState}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart)
      }
    }
    .width('100%')
    .height(this.activeHeight)
    .padding({ left: 14, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(16)
  }

  @Builder
  private CompletedTasksCard() {
    Column() {
      Row({ space: 6 }) {
        Text('已完成')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
        Text(`${this.completedTotalCount}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
        Blank()
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([$r('app.color.text_disabled')])
      }
      .width('100%')
      .height(38)
      .justifyContent(FlexAlign.Start)
      .onClick(() => this.showCompletedSheet = true)
    }
    .width('100%')
    .height(58)
    .padding({ left: 14, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(16)
  }

  @Builder
  private CompletedTasksSheetContent() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text('已完成')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(`${this.completedTotalCount} 项已完成任务`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Normal)
        .width(38)
        .height(38)
        .backgroundColor($r('app.color.surface_input'))
        .borderRadius(19)
        .onClick(() => this.showCompletedSheet = false)
      }
      .width('100%')

      if (this.completedTasks.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(38)
            .fontColor([$r('app.color.text_disabled')])
          Text('暂无已完成事项')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.completedTasks, (task: TodoTask) => {
            ListItem() {
              this.CompletedTaskRow(task)
            }
            .swipeAction({
              end: {
                builder: () => {
                  this.DeleteSwipeAction(task)
                },
                onAction: () => this.onDeleteTask(task)
              }
            })
          }, (task: TodoTask) => `${task.id}-${task.updatedAt}-${task.syncState}`)
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
    .padding({ left: 20, right: 16, top: 20, bottom: 24 })
  }

  build() {
    Column({ space: 12 }) {
      this.ActiveTasksCard()
      this.CompletedTasksCard()
    }
    .width('100%')
    .bindSheet($$this.showCompletedSheet, this.CompletedTasksSheetContent(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      backgroundColor: $r('app.color.surface_translucent'),
      blurStyle: BlurStyle.COMPONENT_THIN,
      showClose: false
    })
  }
}
