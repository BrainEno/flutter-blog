/// The vertical rhythm the sign-in screens share.
///
/// These are the proportions of one composition - a title, a stack of fields
/// and the actions under them - not steps of `NoWaveSpacing`. Keeping them
/// here rather than in the token file is deliberate: a 60 in the global scale
/// would invite every screen to breathe this wide, while in fact only these
/// two screens do. Fields are a group (`NoWaveSpacing.medium`) and the link
/// rows an action block (`NoWaveSpacing.small`); only the three gaps that
/// make the composition keep a local name.
abstract final class AuthRhythm {
  /// Above the title and below the last link. Also what keeps the form
  /// optically centred on a tall screen without a `LayoutBuilder`: the column
  /// is inside a scroll view, so the padding scrolls with it instead of
  /// collapsing the way a `Spacer` inside a scroll view would.
  static const hero = 60.0;

  /// Between the title and the first field.
  static const title = 40.0;

  /// Between the last field and the primary action, and between that action
  /// and the link rows: the button belongs to neither group, so it gets its
  /// own gap rather than the field rhythm.
  static const action = 30.0;
}
