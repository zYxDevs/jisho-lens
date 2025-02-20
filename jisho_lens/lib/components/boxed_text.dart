import 'package:flutter/material.dart';
import 'package:jisho_lens/extensions/radius_extensions.dart';

class BoxedText extends StatelessWidget {
  const BoxedText({
    super.key,
    required this.text,
    required this.tooltipText,
    this.backgroundColor,
    this.textStyle,
  });

  final String text;
  final String tooltipText;
  final Color? backgroundColor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltipText,
      triggerMode: TooltipTriggerMode.tap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 20,
          minHeight: 14,
        ),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: 4.circular,
          ),
          child: Center(child: Text(text, style: textStyle)),
        ),
      ),
    );
  }
}
