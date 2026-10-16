import 'package:flutter/material.dart';
import '../../data/models/stream_item.dart';
import '../controllers/iptv_controller.dart';
import 'content_section/live_tv_guide.dart';
import 'content_section/vod_grid.dart';

/// Tela de seção principal.
///
/// Delega para widgets especializados:
/// - [LiveTvGuide] para TV ao vivo (layout 3 colunas)
/// - [VodGrid] para Filmes/Séries (grade de pôsteres)
class ContentSectionScreen extends StatefulWidget {
  final IptvController controller;
  final StreamType type;

  const ContentSectionScreen({
    super.key,
    required this.controller,
    required this.type,
  });

  @override
  State<ContentSectionScreen> createState() => _ContentSectionScreenState();
}

class _ContentSectionScreenState extends State<ContentSectionScreen> {
  StreamType get _type => widget.type;
  bool get _isLive => _type == StreamType.live;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (_isLive) {
          return LiveTvGuide(controller: widget.controller);
        }
        return VodGrid(controller: widget.controller, type: _type);
      },
    );
  }
}