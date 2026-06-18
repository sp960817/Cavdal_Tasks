interface CardTask {
  id: string;
  title: string;
  due: string;
  syncState: string;
}

function parseTasks(value: string): CardTask[] {
  try {
    return JSON.parse(value) as CardTask[];
  } catch (_err) {
    return [];
  }
}

let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('tasksJson') tasksJson: string = '[]';
  @LocalStorageProp('pendingCount') pendingCount: string = '0';
  @LocalStorageProp('lastSyncText') lastSyncText: string = '未同步';
  @LocalStorageProp('widgetBlurStyle') widgetBlurStyle: string = 'regular';

  private blurStyle(): BlurStyle {
    if (this.widgetBlurStyle === 'none') {
      return BlurStyle.NONE;
    }
    if (this.widgetBlurStyle === 'thin') {
      return BlurStyle.BACKGROUND_THIN;
    }
    if (this.widgetBlurStyle === 'thick') {
      return BlurStyle.BACKGROUND_THICK;
    }
    return BlurStyle.BACKGROUND_REGULAR;
  }

  private completeTask(task: CardTask): void {
    postCardAction(this, {
      action: 'message',
      params: {
        operation: 'complete',
        taskId: task.id
      }
    });
  }

  private openApp(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        source: 'widget'
      }
    });
  }

  private tasks(): CardTask[] {
    return parseTasks(this.tasksJson);
  }

  build() {
    Stack() {
      Column() {
        if (this.tasks().length === 0) {
          Column({ space: 5 }) {
            Text('今日清爽')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.widget_text'))
              .textAlign(TextAlign.Center)
            Text(this.lastSyncText)
              .fontSize(10)
              .fontColor($r('app.color.widget_secondary'))
              .textAlign(TextAlign.Center)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.openApp())
        } else {
          List({ space: 6 }) {
            ForEach(this.tasks(), (task: CardTask) => {
              ListItem() {
                Row({ space: 6 }) {
                  Text('')
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .border({ width: 1.5, color: $r('app.color.widget_circle') })
                    .backgroundColor($r('app.color.transparent'))
                    .onClick(() => this.completeTask(task))

                  Text(task.title)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.widget_text'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  .layoutWeight(1)
                  .onClick(() => this.openApp())
                }
                .width('100%')
                .height(38)
                .padding({ left: 4, right: 5 })
                .backgroundColor(this.widgetBlurStyle === 'none' ?
                  $r('app.color.widget_item') : $r('app.color.widget_glass_item'))
                .borderRadius(10)
              }
            }, (task: CardTask) => task.id)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
        }

      }
      .width('100%')
      .height('100%')
      .padding(8)
      .onClick(() => this.openApp())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.widgetBlurStyle === 'none' ?
      $r('app.color.widget_background') : $r('app.color.transparent'))
    .backgroundBlurStyle(this.blurStyle())
    .borderRadius(22)
  }
}
