import 'stream_item.dart';

class IptvCategory {
  final String id;
  final String name;
  final StreamType streamType;
  final List<StreamItem> items;

  IptvCategory({
    required this.id,
    required this.name,
    required this.streamType,
    List<StreamItem>? items,
  }) : items = items ?? [];

  int get count => items.length;
}
