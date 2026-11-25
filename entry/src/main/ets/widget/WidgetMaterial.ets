export function widgetMaterialColor(style: string): ResourceColor {
  if (style === 'thin') return $r('app.color.widget_thin');
  if (style === 'regular') return $r('app.color.widget_regular');
  if (style === 'thick') return $r('app.color.widget_thick');
  return Color.Transparent;
}

export function widgetMaterialBlur(style: string): BlurStyle {
  if (style === 'thin') return BlurStyle.BACKGROUND_THIN;
  if (style === 'regular') return BlurStyle.BACKGROUND_REGULAR;
  if (style === 'thick') return BlurStyle.BACKGROUND_THICK;
  return BlurStyle.NONE;
}
