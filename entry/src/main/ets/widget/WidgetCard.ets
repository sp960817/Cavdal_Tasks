interface CardTask {
  id: string;
  title: string;
  due: string;
  syncState: string;
  hasReminder: boolean;
}

// Non-virtual Repeat updates retained rows only when their content key changes.
function cardTaskRenderKey(task: CardTask): string {
  return JSON.stringify([
    task.id, task.title, task.due, task.syncState, task.hasReminder ? '1' : '0'
  ]);
}

function parseTasks(value: string): CardTask[] {
  try {
    return JSON.parse(value) as CardTask[];
  } catch (_err) {
    return [];
  }
}

function blurStyleFor(style: string): BlurStyle {
  if (style === 'thin') {
    return BlurStyle.BACKGROUND_THIN;
  }
  if (style === 'regular') {
    return BlurStyle.BACKGROUND_REGULAR;
  }
  if (style === 'thick') {
    return BlurStyle.BACKGROUND_THICK;
  }
  return BlurStyle.NONE;
}

function isLightHostColor(color: string): boolean {
  let value = color.toUpperCase();
  if (value.length === 9 && value.startsWith('#')) {
    value = `#${value.slice(3)}`;
  }
  if (value.length !== 7 || !value.startsWith('#')) {
    return false;
  }
  const red = Number.parseInt(value.slice(1, 3), 16);
  const green = Number.parseInt(value.slice(3, 5), 16);
  const blue = Number.parseInt(value.slice(5, 7), 16);
  return red * 299 + green * 587 + blue * 114 > 160000;
}

// FormKit supplies the inverse of the host background color. A dark inverse
// therefore means the host background is light, and vice versa.
function hasLightHostBackground(inverseHostColor: string): boolean {
  return !isLightHostColor(inverseHostColor);
}

function foregroundColorFor(inverseHostColor: string): string {
  // Keep the host's light/dark decision, without inheriting a translucent or
  // tinted foreground that becomes hard to read over a detailed wallpaper.
  return hasLightHostBackground(inverseHostColor) ? '#FF17232E' : '#FFF7F9FC';
}

function backgroundColorFor(style: string, inverseHostColor: string): string {
  const lightHost = hasLightHostBackground(inverseHostColor);
  if (style === 'none') {
    return '#00000000';
  }
  if (style === 'thin') {
    return lightHost ? '#35FFFEFB' : '#3B10171D';
  }
  if (style === 'regular') {
    return lightHost ? '#78FFFEFB' : '#851B252E';
  }
  if (style === 'thick') {
    return lightHost ? '#D9FFFEFB' : '#E01B252E';
  }
  return '#00000000';
}

function borderColorFor(style: string, inverseHostColor: string): string {
  const lightHost = hasLightHostBackground(inverseHostColor);
  if (style === 'none') {
    return '#00000000';
  }
  return lightHost ? '#24000000' : '#33FFFFFF';
}

let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('tasksJson') @Watch('onTasksJsonChange') tasksJson: string = '[]';
  @LocalStorageProp('pendingCount') pendingCount: string = '0';
  @LocalStorageProp('lastSyncText') lastSyncText: string = '未同步';
  @LocalStorageProp('widgetBlurStyle') @Watch('onBlurStyleChange') widgetBlurStyle: string = 'thin';
  @LocalStorageProp('textColor') @Watch('onTextColorChange') textColor: string = '#E6000000';
  @LocalStorageProp('formDimension') formDimension: string = '2';
  @State completingId: string = '';
  @State cardTasks: CardTask[] = [];
  @State taskListHeight: number = 0;

  aboutToAppear(): void {
    this.cardTasks = parseTasks(this.tasksJson);
  }

  private onTextColorChange(): void {
  }

  private onBlurStyleChange(): void {
  }

  private onTasksJsonChange(): void {
    this.cardTasks = parseTasks(this.tasksJson);
    this.completingId = '';
  }

  private tc(): string {
    return foregroundColorFor(this.textColor);
  }

  private pendingLabel(): string {
    const count = Number(this.pendingCount);
    if (Number.isFinite(count) && count > 0) {
      return `${count} 项待同步`;
    }
    return this.lastSyncText;
  }

  private usesCompactVisual(): boolean {
    return this.formDimension === '1' || this.formDimension === '2';
  }

  private isMini(): boolean {
    return this.formDimension === '1';
  }

  private isSquare(): boolean {
    return this.formDimension === '2';
  }

  private isWide(): boolean {
    return this.formDimension === '3';
  }

  private isLarge(): boolean {
    return this.formDimension === '4';
  }

  private taskRowHeight(): number {
    if (this.isMini()) {
      return 28;
    }
    if (this.isWide()) {
      return 34;
    }
    if (this.isLarge()) {
      return 44;
    }
    // Three complete rows on the square card, including the two 2vp gaps.
    // onSizeChange also handles launcher resizing without rebuilding the form.
    return this.taskListHeight > 0 ? Math.max(26, Math.floor((this.taskListHeight - 4) / 3)) : 32;
  }

  private completeTask(task: CardTask): void {
    if (this.completingId === task.id) {
      return;
    }
    this.completingId = task.id;
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

  build() {
    Column({ space: this.usesCompactVisual() ? 3 : 5 }) {
      Row({ space: 6 }) {
        Text('拾序')
          .fontSize(this.usesCompactVisual() ? 14 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tc())
        Text(`${this.cardTasks.length} 件事`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tc())
          .opacity(0.86)
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.tc()])
          .opacity(0.86)
      }
      .width('100%')
      .height(this.usesCompactVisual() ? 22 : 26)
      .padding({ left: 3, right: 3 })
      .onClick(() => this.openApp())

      if (this.cardTasks.length === 0) {
        Column({ space: 5 }) {
          if (!this.isMini()) {
            Image($r('app.media.material_empty_tray'))
              .width(this.isLarge() ? 64 : 48)
              .height(this.isLarge() ? 64 : 48)
              .objectFit(ImageFit.Contain)
              .accessibilityLevel('no')
          }
          Text('今天，从容一点')
            .fontSize(this.isMini() ? 12 : 14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tc())
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.openApp())
      } else {
        List({ space: this.isSquare() ? 2 : 3 }) {
          Repeat(this.cardTasks).each((row: RepeatItem<CardTask>) => {
            ListItem() {
              Row({ space: this.isSquare() ? 4 : 5 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Text('')
                    .width(18)
                    .height(18)
                    .borderRadius(9)
                    .border({ width: 1.4, color: this.tc() })
                    .backgroundColor(this.completingId === row.item.id ?
                      '#4C6D8D' : '#00000000')
                    .animation({ duration: 400, curve: Curve.EaseOut })

                  Text('✓')
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFFFF')
                    .opacity(this.completingId === row.item.id ? 1 : 0)
                    .scale({
                      x: this.completingId === row.item.id ? 1 : 0.3,
                      y: this.completingId === row.item.id ? 1 : 0.3
                    })
                    .animation({ duration: 500, curve: Curve.EaseOut })
                }
                .width(this.isSquare() ? 28 : 30)
                .height(this.taskRowHeight())
                .accessibilityText(`完成 ${row.item.title}`)
                .onClick(() => this.completeTask(row.item))

                Text(row.item.title)
                  .fontSize(this.isMini() ? 12 : 13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tc())
                  .opacity(this.completingId === row.item.id ? 0 : 1)
                  .animation({ duration: 600, curve: Curve.EaseOut })
                  .maxLines(this.isLarge() ? 2 : 1)
                  .lineHeight(this.isMini() ? 16 : 18)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .onClick(() => this.openApp())

                if (row.item.hasReminder && !this.usesCompactVisual()) {
                  SymbolGlyph($r('sys.symbol.bell'))
                    .fontSize(11)
                    .fontColor([this.tc()])
                    .opacity(this.completingId === row.item.id ? 0 : 0.85)
                    .animation({ duration: 600, curve: Curve.EaseOut })
                    .onClick(() => this.openApp())
                }
              }
              .width('100%')
              .height(this.taskRowHeight())
              .padding({
                left: this.isWide() ? 1 : 0,
                right: this.isWide() ? 4 : 2
              })
            }
          }).key((task: CardTask) => cardTaskRenderKey(task))
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
          if (this.isSquare() && typeof newValue.height === 'number' &&
            newValue.height > 0 && Math.abs(this.taskListHeight - newValue.height) > 0.5) {
            this.taskListHeight = newValue.height;
          }
        })
      }

      if (!this.isMini()) {
        Row() {
          Text(this.pendingLabel())
            .fontSize(this.isSquare() ? 10 : 11)
            .fontColor(this.tc())
            .opacity(0.86)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
        }
        .width('100%')
        .height(this.isSquare() ? 12 : 16)
        .padding({ left: 3, right: 3 })
        .onClick(() => this.openApp())
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.usesCompactVisual() ? 8 : 12,
      right: this.usesCompactVisual() ? 8 : 12,
      top: this.usesCompactVisual() ? 6 : 10,
      bottom: this.usesCompactVisual() ? 6 : 10
    })
    .backgroundColor(backgroundColorFor(this.widgetBlurStyle, this.textColor))
    .backgroundBlurStyle(blurStyleFor(this.widgetBlurStyle))
    .border({ width: 0.6, color: borderColorFor(this.widgetBlurStyle, this.textColor) })
    .borderRadius(24)
  }
}
