import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'folder_picker.dart';

Future<List<PickedCurriculumFile>> pickCurriculumFolderImpl({
  required List<String> allowedExtensions,
}) async {
  final dirPath = await getDirectoryPath();
  if (dirPath == null || dirPath.isEmpty) return [];

  final root = Directory(dirPath);
  if (!await root.exists()) return [];

  final extSet = allowedExtensions.map((e) => '.${e.toLowerCase()}').toSet();
  final results = <PickedCurriculumFile>[];
  final rootLen = root.path.endsWith(Platform.pathSeparator)
      ? root.path.length
      : root.path.length + 1;

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final lower = entity.path.toLowerCase();
    final filename = entity.uri.pathSegments.isNotEmpty
        ? entity.uri.pathSegments.last
        : entity.path;
    if (filename.startsWith('.') || filename.startsWith(r'~$')) continue;
    if (!extSet.any(lower.endsWith)) continue;

    final rel = entity.path.length > rootLen
        ? entity.path.substring(rootLen).replaceAll('\\', '/')
        : filename;
    results.add((
      name: rel,
      readBytes: () => entity.readAsBytes(),
    ));
  }
  return results;
}

Future<List<PickedCurriculumFile>> pickCurriculumFilesImpl({
  required List<String> allowedExtensions,
}) async {
  final group = XTypeGroup(
    label: 'Program & Progression Files',
    extensions: allowedExtensions,
  );
  final files = await openFiles(acceptedTypeGroups: [group]);
  return [
    for (final f in files)
      (name: f.name, readBytes: () => f.readAsBytes()),
  ];
}

void Function() listenForDroppedFoldersImpl({
  required List<String> allowedExtensions,
  required void Function(List<PickedFolderBundle> folders) onFoldersDropped,
}) {
  return () {};
}
