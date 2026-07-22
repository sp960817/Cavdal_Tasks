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
  onToggleTask: (task: TodoTask, done: boolean) => void =
    (_task: TodoTask, _done: boolean): void => {};
  onEditTask: (task: TodoTask) => void = (_task: TodoTask): void => {};
  onDeleteTask: (task: TodoTask) => void = (_task: TodoTask): void => {};
  onCompletedOpenChange: (open: boolean) => void = (_open: boolean): void => {};

  @Builder
  private ActiveTaskRow(task: TodoTask) {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          Toggle({ type: ToggleType.Checkbox, isOn: false })
            .onChange((isOn: boolean) => {
              if (isOn) {
                this.onToggleTask(task, true);
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
      .onClick(() => this.onEditTask(task))

      if (task.syncState !== 'synced') {
        Row() {
          Blank()
            .layoutWeight(1)
          Text(task.syncState === 'pending' ? '待同步' : task.syncState)
            .fontSize(12)
            .fontColor(task.syncState === 'conflict' ?
              $r('app.color.danger_text') : $r('app.color.warning_text'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .height(task.syncState !== 'synced' ? 58 : 44)
    .padding({ left: 0, right: 12 })
    .justifyContent(FlexAlign.Center)
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
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
        Text(`${this.activeTasks.length}`)
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
        Blank()
      }
      .width('100%')
      .height(30)
      .padding({ left: 4, right: 8 })

      if (this.activeTasks.length === 0) {
        Text('没有进行中的待办')
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        List({ space: 0 }) {
          ForEach(this.activeTasks, (task: TodoTask) => {
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
          .fontSize(20)
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
          Text('暂无已完成事项')
            .fontSize(15)
            .fontColor($r('app.color.text_disabled'))
            .width('100%')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
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
