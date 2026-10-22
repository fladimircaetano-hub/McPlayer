enum StreamType {
  live,
  movie,
  series,
}

class StreamItem {
  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String category;
  final StreamType streamType;
  final String? rating;
  final String? releaseDate;
  /// Id do canal na grade XMLTV (tvg-id / epg_channel_id). Separado de [id]
  /// porque no Xtream o [id] é `xtream_live_<stream_id>`, que nunca casa
  /// com o `programme@channel` do XMLTV.
  final String? epgId;
  final int? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  bool isFavorite;

  StreamItem({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    required this.category,
    required this.streamType,
    this.rating,
    this.releaseDate,
    this.epgId,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'streamUrl': streamUrl,
      'logoUrl': logoUrl,
      'category': category,
      'streamType': streamType.name,
      'rating': rating,
      'releaseDate': releaseDate,
      'epgId': epgId,
      'seriesId': seriesId,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'isFavorite': isFavorite,
    };
  }

  factory StreamItem.fromJson(Map<String, dynamic> json) {
    return StreamItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Sem Nome',
      streamUrl: json['streamUrl'] as String? ?? '',
      logoUrl: json['logoUrl'] as String?,
      category: json['category'] as String? ?? 'Geral',
      streamType: StreamType.values.firstWhere(
        (e) => e.name == json['streamType'],
        orElse: () => StreamType.live,
      ),
      rating: json['rating'] as String?,
      releaseDate: json['releaseDate'] as String?,
      epgId: json['epgId'] as String?,
      seriesId: json['seriesId'] as int?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }

  StreamItem copyWith({
    String? id,
    String? name,
    String? streamUrl,
    String? logoUrl,
    String? category,
    StreamType? streamType,
    String? rating,
    String? releaseDate,
    String? epgId,
    int? seriesId,
    int? seasonNumber,
    int? episodeNumber,
    bool? isFavorite,
  }) {
    return StreamItem(
      id: id ?? this.id,
      name: name ?? this.name,
      streamUrl: streamUrl ?? this.streamUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      category: category ?? this.category,
      streamType: streamType ?? this.streamType,
      rating: rating ?? this.rating,
      releaseDate: releaseDate ?? this.releaseDate,
      epgId: epgId ?? this.epgId,
      seriesId: seriesId ?? this.seriesId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
