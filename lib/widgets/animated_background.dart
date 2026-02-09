import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AnimatedBackground chooses between an animated gradient (default)
/// or a muted looping video if the user enables it in Settings and a video asset exists.
class AnimatedBackground extends StatefulWidget {
  final Widget child;
  final bool isOverlay; // when true, renders a semi-transparent overlay for content contrast

  const AnimatedBackground({super.key, required this.child, this.isOverlay = true});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> {
  VideoPlayerController? _controller;
  bool _useVideo = false;
  bool _useGradient = true;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('enable_background_video') ?? false;
    final gradientEnabled = prefs.getBool('enable_animated_gradient') ?? true;
    _useGradient = gradientEnabled;
    if (enabled) {
      // try to load a bundled asset video
      try {
        _controller = VideoPlayerController.asset('assets/videos/background.mp4');
        await _controller!.initialize();
        _controller!
          ..setLooping(true)
          ..setVolume(0.0)
          ..play();
        setState(() {
          _useVideo = true;
        });
      } catch (_) {
        // if asset missing, fallback to gradient
        _controller?.dispose();
        _controller = null;
        setState(() => _useVideo = false);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_useVideo && _controller != null && _controller!.value.isInitialized)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          )
        else if (_useGradient)
          const _AnimatedGradient()
        else
          Container(color: Theme.of(context).colorScheme.surface),
        if (widget.isOverlay)
          Container(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
          ),
        widget.child,
      ],
    );
  }
}

class _AnimatedGradient extends StatefulWidget {
  const _AnimatedGradient({super.key});

  @override
  State<_AnimatedGradient> createState() => _AnimatedGradientState();
}

class _AnimatedGradientState extends State<_AnimatedGradient> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + _anim.value, -1),
              end: Alignment(1 - _anim.value, 1),
              colors: const [
                Color(0xFF00695C),
                Color(0xFF3F51B5),
                Color(0xFF00BFA5),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
