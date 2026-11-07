enum GuangyaFileKind { folder, video, audio, image, document, archive, torrent, other }

class GuangyaFile {
  const GuangyaFile({
    required this.id,
    required this.parentId,
    required this.name,
    required this.size,
    required this.kind,
    this.ext,
  });

  final String id;
  final String parentId;
  final String name;
  final int size;
  final GuangyaFileKind kind;
  final String? ext;

  bool get isFolder => kind == GuangyaFileKind.folder;
  bool get isPlayable =>
      kind == GuangyaFileKind.video || kind == GuangyaFileKind.audio;

  factory GuangyaFile.fromJson(Map<String, dynamic> json) {
    final resType = (json['resType'] as num?)?.toInt();
    final fileType = (json['fileType'] as num?)?.toInt();
    return GuangyaFile(
      id: '${json['fileId']}',
      parentId: '${json['parentId'] ?? ''}',
      name: '${json['fileName'] ?? ''}',
      size: (json['fileSize'] as num?)?.toInt() ?? 0,
      ext: json['ext'] as String?,
      kind: _kind(resType, fileType),
    );
  }

  static GuangyaFileKind _kind(int? resType, int? fileType) {
    if (resType == 2) return GuangyaFileKind.folder;
    switch (fileType ?? -1) {
      case 2:
        return GuangyaFileKind.video;
      case 3:
        return GuangyaFileKind.audio;
      case 1:
        return GuangyaFileKind.image;
      case 4:
        return GuangyaFileKind.document;
      case 5:
        return GuangyaFileKind.archive;
      case 9:
        return GuangyaFileKind.torrent;
      default:
        return GuangyaFileKind.other;
    }
  }
}

class GuangyaPage {
  const GuangyaPage({required this.total, required this.items});

  final int total;
  final List<GuangyaFile> items;

  bool hasMore({required int pageSize}) => items.length >= pageSize && items.length < total;
}
