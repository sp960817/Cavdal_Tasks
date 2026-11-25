import { CatSnack } from '../common/CatSnack';
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
      Column({ space: 3 }) {
        Image($r('app.media.cat_idle')).width(24).height(24).objectFit(ImageFit.Contain)
        CatSnack({ taskId: style }).width(32).height(6)
      }
      .justifyContent(FlexAlign.Center)
      .width('78%')
      .height(48)
      .backgroundColor(style === 'none' ? Color.Transparent :
        style === 'thick' ? $r('app.color.surface') : $r('app.color.glass_fill'))
      .backgroundBlurStyle(previewBlurStyle(style))
      .borderRadius(10)
    }
    .width('100%')
    .height(68)

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

      Stack({ alignContent: Alignment.Top }) {
        Image($r('app.media.cat_meadow')).width('100%').height(68).objectFit(ImageFit.Cover)
          .borderRadius(12).accessibilityLevel('no')
        Row() {
          ForEach(this.styles, (style: WidgetBlurStyle) => {
            Button() {
              Column({ space: 6 }) {
                this.MaterialPreview(style)
                Text(widgetBlurLabel(style)).fontSize(12)
                  .fontWeight(this.selectedStyle === style ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.selectedStyle === style ? $r('app.color.accent') : $r('app.color.text_secondary'))
                Row().width(16).height(2)
                  .backgroundColor(this.selectedStyle === style ? $r('app.color.accent') : Color.Transparent)
              }.width('100%')
            }.type(ButtonType.Normal).layoutWeight(1).padding(0)
              .backgroundColor(Color.Transparent)
              .accessibilityText(widgetBlurLabel(style) + (this.selectedStyle === style ? '，已选择' : ''))
              .onClick(() => this.onStyleChange(style))
          }, (style: WidgetBlurStyle) => style)
        }.width('100%')
      }.width('100%')

      Text(this.styleDescription())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .lineHeight(18)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 8, bottom: 8 })
  }
}
