import 'package:flutter/widgets.dart';

/// One page of the tutorial slideshow: a title, one or two caption lines,
/// and a builder for its animated demo widget (see `tutorial_demo_stage.dart`
/// and `tutorial_demo_primitives.dart` for the pieces demos are built from).
class TutorialSlide {
  const TutorialSlide({
    required this.title,
    required this.captionLines,
    required this.demoBuilder,
  });

  final String title;
  final List<String> captionLines;
  final WidgetBuilder demoBuilder;
}
