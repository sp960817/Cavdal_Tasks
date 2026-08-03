import { TodoTask } from '../../model/TaskModels';
import { formatDueForDisplay } from '../../formatters/DueTimeFormatter';
import { VTodoCodec } from '../../caldav/VTodoCodec';

@Component
export struct TaskCards {
  @Prop activeTasks: TodoTask[] = [];
  @Prop completedTasks: TodoTask[] = [];
  @Prop completedTotalCount: number = 0;
  @Prop activeHeight: number = 108;
  @Prop completedHeight: number = 58;
  @Prop completedOpen: boolean = false;
  // 正在播放"完成"动画的任务 id 集合，驱动删除线/淡出过渡
  @State completingIds: string[] = [];
  // 动画已结束、已从视觉列表移除（不等网络刷新）的任务 id 集合
  @State removedIds: string[] = [];
  onToggleTask: (task: TodoTask, done: boolean) => void =
    (_task: TodoTask, _done: boolean): void => {};
  onEditTask: (task: TodoTask) => void = (_task: TodoTask): void => {};
  onDeleteTask: (task: TodoTask) => void = (_task: TodoTask): void => {};
  onAddTask: () => void = (): void => {};
  onCompletedOpenChange: (open: boolean) => void = (_open: boolean): void => {};

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

  // 官方推荐：显式动画 animateTo 驱动状态变化（List 增删不自带动画）
  private animateComplete(task: TodoTask): void {
    if (this.isCompleting(task.id) || this.isRemoved(task.id)) {
      return;
    }
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.EaseInOut,
      onFinish: () => {
        // 动画结束立即从视觉列表移除该行（不等网络刷新），消除悬停等待；
        // 数据层 setTaskCompleted 在后台继续完成，refreshLists 后任务进已完成。
        this.removedIds = this.removedIds.concat(task.id);
        this.completingIds = this.completingIds.filter((id: string) => id !== task.id);
        this.onToggleTask(task, true);
        // 兜底：若同步失败任务仍在列表，2s 后恢复显示供用户重试
        setTimeout(() => {
          this.removedIds = this.removedIds.filter((id: string) => id !== task.id);
        }, 2000);
      }
    }, () => {
      // 关键：状态变更必须在 animateTo 闭包内执行，
      // ArkUI 才能捕捉"可见→透明"的差异并生成过渡动画。
      this.completingIds = this.completingIds.concat(task.id);
    });
  }

  @Builder
  private ActiveTaskRow(task: TodoTask) {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          Toggle({ type: ToggleType.Checkbox, isOn: false })
            .onChange((isOn: boolean) => {
              if (isOn) {
                this.animateComplete(task);
              }
            })
            .width(22)
            .height(22)
        }
        .width(40)
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
              $r('app.color.text_disabled') : $r('app.color.accent'))
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
  }

  @Builder
  private CompletedTaskRow(task: TodoTask) {
    Row({ space: 8 }) {
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
      .width(40)
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
    .borderRadius({ topRight: 16, bottomRight: 16 })
    .onClick(() => this.onDeleteTask(task))
  }

  @Builder
  private ActiveTasksCard() {
    Column() {
      Row({ space: 6 }) {
        Text('未完成')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
        Text(`${this.visibleActiveTasks().length}`)
          .fontSize(13)
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
    .padding({ left: 16, right: 8, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface_translucent'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 0.5, color: $r('app.color.bar_glass_edge') })
    .borderRadius(18)
  }

  @Builder
  private CompletedTasksCard() {
    Column() {
      Row({ space: 8 }) {
        Text('已完成')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_tertiary'))
        Text(`${this.completedTotalCount}`)
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
        SymbolGlyph(this.completedOpen ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(18)
          .fontColor([$r('app.color.text_disabled')])
      }
      .width('100%')
      .height(34)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: this.completedOpen ? 8 : 0 })
      .onClick(() => this.onCompletedOpenChange(!this.completedOpen))

      if (this.completedOpen) {
        if (this.completedTasks.length === 0) {
          Column({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(30)
              .fontColor([$r('app.color.text_disabled')])
              .opacity(0.5)
            Text('暂无已完成事项')
              .fontSize(15)
              .fontColor($r('app.color.text_disabled'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
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
    }
    .width('100%')
    .height(this.completedHeight)
    .padding({ left: 16, right: 8, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface_translucent'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 0.5, color: $r('app.color.bar_glass_edge') })
    .borderRadius(18)
  }

  build() {
    Column({ space: 14 }) {
      this.ActiveTasksCard()
      this.CompletedTasksCard()
    }
    .width('100%')
  }
}
