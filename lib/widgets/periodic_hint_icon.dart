import 'dart:async';
import 'package:flutter/material.dart';

class PeriodicHintIcon extends StatefulWidget {
  const PeriodicHintIcon({super.key});
  @override
  State<PeriodicHintIcon> createState() => _PeriodicHintIconState();
}

class _PeriodicHintIconState extends State<PeriodicHintIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 600));
  late final Animation<double> opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: .15).chain(CurveTween(curve: Curves.easeInOut)), weight: 1),
    TweenSequenceItem(tween: Tween(begin: .15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 1),
  ]).animate(controller);
  Timer? timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    timer?.cancel();
    controller.stop();
    controller.value = 0;
    if (TickerMode.of(context) && !MediaQuery.disableAnimationsOf(context)) {
      timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) controller.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: opacity,
    child: const Icon(Icons.touch_app_rounded, size: 22, color: Color(0xFF8A4B08)),
  );
}
