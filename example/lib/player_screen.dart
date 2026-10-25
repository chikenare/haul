import 'dart:io';

import 'package:flutter/material.dart';
import 'package:haul/haul.dart';
import 'package:haul/widgets.dart';
import 'package:video_player/video_player.dart';

/// Opens a finished download: its path, or its `content://` URI.
void openPlayer(BuildContext context, DownloadRecord record) {
  final locator = playableLocator(HaulScope.of(context).engine, record);
  if (locator == null) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(title: record.title, locator: locator),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.title, required this.locator});

  final String title;
  final String locator;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlayerController _controller =
      widget.locator.startsWith('content://')
      ? VideoPlayerController.contentUri(Uri.parse(widget.locator))
      : VideoPlayerController.file(File(widget.locator));
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
          _controller.play();
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: _error != null
            ? Text('$_error', style: const TextStyle(color: Colors.white))
            : value.isInitialized
            ? GestureDetector(
                onTap: () =>
                    value.isPlaying ? _controller.pause() : _controller.play(),
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
