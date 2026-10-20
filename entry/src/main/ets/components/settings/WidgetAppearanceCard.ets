import { WidgetBlurStyle } from '../../model/TaskModels';

export function widgetBlurLabel(style: WidgetBlurStyle): string {
  if (style === 'none') return '通透';
  if (style === 'thin') return '轻雾';
  if (style === 'thick') return '凝脂';
  return '磨砂';
}

function previewBlurStyle(style: WidgetBlurStyle): BlurStyle {
  if (style === 'thin') return BlurStyle.COMPONENT_ULTRA_THIN;
  if (style === 'regular') return BlurStyle.COMPONENT_REGULAR;
  if (style === 'thick') return BlurStyle.COMPONENT_THICK;
  return BlurStyle.NONE;
}

@Component
export struct WidgetAppearanceCard {
  @Prop selectedStyle: WidgetBlurStyle = 'thin';
  onStyleChange: (style: WidgetBlurStyle) => void = (_style: WidgetBlurStyle): void => {};
  private styles: WidgetBlurStyle[] = ['none', 'thin', 'regular', 'thick'];

  private styleDescription(): string {
    if (this.selectedStyle === 'none') return '让壁纸自然透过，保留轻盈文字。';
    if (this.selectedStyle === 'thin') return '薄雾般的背景，让文字与壁纸都清晰。';
    if (this.selectedStyle === 'thick') return '更柔和的厚实背景，适合色彩丰富的壁纸。';
    return '平衡通透与对比，专注眼前的每件小事。';
  }

  @Builder
  private MaterialPreview(style: WidgetBlurStyle) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height(68)
        .linearGradient({
          angle: 135,
          colors: [[$r('app.color.accent_soft'), 0], [$r('app.color.accent'), 1]]
        })
        .borderRadius(14)

      Column({ space: 5 }) {
        Row({ space: 4 }) {
          Column()
            .width(5)
            .height(5)
            .backgroundColor($r('app.color.text_secondary'))
            .borderRadius(3)
          Column()
            .height(3)
            .layoutWeight(1)
            .backgroundColor($r('app.color.text_secondary'))
            .borderRadius(2)
        }
        .width('100%')
        .opacity(0.72)
        Row({ space: 4 }) {
          Column()
            .width(5)
            .height(5)
            .backgroundColor($r('app.color.text_secondary'))
            .borderRadius(3)
          Column()
            .height(3)
            .width('50%')
            .backgroundColor($r('app.color.text_secondary'))
            .borderRadius(2)
        }
        .width('100%')
        .opacity(0.48)
      }
      .justifyContent(FlexAlign.Center)
      .width('78%')
      .height(42)
      .padding(8)
      .backgroundColor(style === 'none' ? Color.Transparent :
        style === 'thick' ? $r('app.color.surface') : $r('app.color.glass_fill'))
      .backgroundBlurStyle(previewBlurStyle(style))
      .border({ width: 0.6, color: $r('app.color.glass_edge') })
      .borderRadius(10)
    }
    .width('100%')
    .height(68)
    .clip(true)
    .borderRadius(14)
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text('桌面卡片')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(widgetBlurLabel(this.selectedStyle))
          .fontSize(12)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')

      Row({ space: 8 }) {
        ForEach(this.styles, (style: WidgetBlurStyle) => {
          Button() {
            Column({ space: 8 }) {
              this.MaterialPreview(style)
              Text(widgetBlurLabel(style))
                .fontSize(12)
                .fontWeight(this.selectedStyle === style ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.selectedStyle === style ?
                  $r('app.color.accent') : $r('app.color.text_secondary'))
            }
            .width('100%')
          }
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .padding(4)
          .backgroundColor(this.selectedStyle === style ?
            $r('app.color.accent_soft') : Color.Transparent)
          .border({
            width: this.selectedStyle === style ? 1.5 : 0.5,
            color: this.selectedStyle === style ? $r('app.color.accent') : $r('app.color.divider')
          })
          .borderRadius(18)
          .accessibilityText(`${widgetBlurLabel(style)}${this.selectedStyle === style ? '，已选择' : ''}`)
          .onClick(() => this.onStyleChange(style))
        }, (style: WidgetBlurStyle) => style)
      }
      .width('100%')

      Text(this.styleDescription())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .lineHeight(18)
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(24)
  }
}
