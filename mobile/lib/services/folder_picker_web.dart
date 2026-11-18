import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'folder_picker.dart';

Future<List<int>> _readWebFile(web.File file) async {
  final buffer = await file.arrayBuffer().toDart;
  return Uint8List.fromList(buffer.toDart.asUint8List());
}

Future<void> _walkDirectoryHandle(
  JSObject dirHandle,
  String pathPrefix,
  Set<String> extSet,
  List<PickedCurriculumFile> out,
) async {
  final iter = dirHandle.callMethod<JSObject>('values'.toJS);
  final subdirs = <(JSObject, String)>[];

  while (true) {
    final step = await iter.callMethod<JSPromise<JSObject>>('next'.toJS).toDart;
    final doneVal = step.getProperty('done'.toJS);
    final isDone = doneVal.isA<JSBoolean>() && (doneVal as JSBoolean).toDart;
    if (isDone) break;

    final handle = step.getProperty('value'.toJS);
    if (handle == null || !handle.isA<JSObject>()) continue;
    final hObj = handle as JSObject;
    final kindVal = hObj.getProperty('kind'.toJS);
    final nameVal = hObj.getProperty('name'.toJS);
    if (!kindVal.isA<JSString>() || !nameVal.isA<JSString>()) continue;

    final kind = (kindVal as JSString).toDart;
    final name = (nameVal as JSString).toDart;
    if (name.startsWith('.') || name.startsWith(r'~$')) continue;

    final nextPath = pathPrefix.isEmpty ? name : '$pathPrefix/$name';
    if (kind == 'directory') {
      subdirs.add((hObj, nextPath));
    } else if (kind == 'file') {
      if (!extSet.any(name.toLowerCase().endsWith)) continue;
      out.add((
        name: nextPath,
        readBytes: () async {
          try {
            final file =
                await hObj.callMethod<JSPromise<web.File>>('getFile'.toJS).toDart;
            return _readWebFile(file);
          } catch (_) {
            return const [];
          }
        },
      ));
    }
  }

  // Walk subdirectories in small parallel groups to load nested folders quickly.
  const dirConcurrency = 6;
  for (var i = 0; i < subdirs.length; i += dirConcurrency) {
    final end = (i + dirConcurrency < subdirs.length)
        ? i + dirConcurrency
        : subdirs.length;
    await Future.wait([
      for (var j = i; j < end; j++)
        _walkDirectoryHandle(subdirs[j].$1, subdirs[j].$2, extSet, out)
            .catchError((_) {}),
    ]);
  }
}

Future<List<PickedCurriculumFile>> pickCurriculumFilesImpl({
  required List<String> allowedExtensions,
}) async {
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..multiple = true
    ..accept = allowedExtensions.map((e) => '.${e.toLowerCase()}').join(',');
  input.style.display = 'none';
  web.document.body?.append(input);

  final completer = Completer<List<PickedCurriculumFile>>();
  var finished = false;
  late StreamSubscription<web.Event> changeSub;
  late StreamSubscription<web.Event> cancelSub;

  void cleanup() {
    changeSub.cancel();
    cancelSub.cancel();
    input.remove();
  }

  void finishWithFiles() {
    if (finished) return;
    finished = true;
    try {
      final fileList = input.files;
      final out = <PickedCurriculumFile>[];
      if (fileList != null) {
        for (var i = 0; i < fileList.length; i++) {
          final file = fileList.item(i);
          if (file == null) continue;
          final rawName = file.name;
          if (rawName.startsWith('.') || rawName.startsWith(r'~$')) continue;
          out.add((name: rawName, readBytes: () => _readWebFile(file)));
        }
      }
      cleanup();
      if (!completer.isCompleted) completer.complete(out);
    } catch (e) {
      cleanup();
      if (!completer.isCompleted) completer.completeError(e);
    }
  }

  changeSub = input.onChange.listen((_) => finishWithFiles());

  cancelSub = const web.EventStreamProvider<web.Event>('cancel')
      .forTarget(input)
      .listen((_) {
    if (!finished) {
      finished = true;
      cleanup();
      if (!completer.isCompleted) completer.complete([]);
    }
  });

  input.click();
  return completer.future;
}

Future<List<PickedCurriculumFile>> _pickViaLegacyFolderInput(
  Set<String> extSet,
) async {
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..multiple = true;
  input.setAttribute('webkitdirectory', '');
  input.setAttribute('directory', '');
  input.style.display = 'none';
  web.document.body?.append(input);

  final completer = Completer<List<PickedCurriculumFile>>();
  var finished = false;
  late StreamSubscription<web.Event> changeSub;
  late StreamSubscription<web.Event> cancelSub;

  void cleanup() {
    changeSub.cancel();
    cancelSub.cancel();
    input.remove();
  }

  void finishWithFiles() {
    if (finished) return;
    finished = true;
    try {
      final fileList = input.files;
      final out = <PickedCurriculumFile>[];
      if (fileList != null) {
        for (var i = 0; i < fileList.length; i++) {
          final file = fileList.item(i);
          if (file == null) continue;
          final rawName = file.name;
          if (rawName.startsWith('.') || rawName.startsWith(r'~$')) continue;
          if (!extSet.any(rawName.toLowerCase().endsWith)) continue;

          final rel = file.webkitRelativePath.isNotEmpty
              ? file.webkitRelativePath
              : rawName;
          out.add((name: rel, readBytes: () => _readWebFile(file)));
        }
      }
      cleanup();
      if (!completer.isCompleted) completer.complete(out);
    } catch (e) {
      cleanup();
      if (!completer.isCompleted) completer.completeError(e);
    }
  }

  changeSub = input.onChange.listen((_) => finishWithFiles());

  cancelSub = const web.EventStreamProvider<web.Event>('cancel')
      .forTarget(input)
      .listen((_) {
    if (!finished) {
      finished = true;
      cleanup();
      if (!completer.isCompleted) completer.complete([]);
    }
  });

  input.click();
  return completer.future;
}

Future<List<PickedCurriculumFile>> pickCurriculumFolderImpl({
  required List<String> allowedExtensions,
}) async {
  final extSet = allowedExtensions.map((e) => '.${e.toLowerCase()}').toSet();

  final pickerFn = globalContext.getProperty('showDirectoryPicker'.toJS);
  if (pickerFn != null && pickerFn.isA<JSFunction>()) {
    try {
      final dirHandle = await globalContext
          .callMethod<JSPromise<JSObject>>('showDirectoryPicker'.toJS)
          .toDart;
      final rootNameVal = dirHandle.getProperty('name'.toJS);
      final rootName =
          rootNameVal.isA<JSString>() ? (rootNameVal as JSString).toDart : '';
      final out = <PickedCurriculumFile>[];
      await _walkDirectoryHandle(dirHandle, rootName, extSet, out);
      return out;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('AbortError')) {
        return [];
      }
      if (msg.contains('NotAllowedError')) {
        throw Exception(
          'Folder permission was denied in Chrome. Click "Autoriser" in Chrome\'s popup, or use Upload Files / Drag & Drop.',
        );
      }
    }
  }

  return _pickViaLegacyFolderInput(extSet);
}

Future<web.File?> _entryToFile(web.FileSystemFileEntry entry) {
  final completer = Completer<web.File?>();
  entry.file(
    ((web.File f) {
      if (!completer.isCompleted) completer.complete(f);
    }).toJS,
    ((web.DOMException _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
  );
  return completer.future;
}

Future<List<web.FileSystemEntry>> _readDirOnce(
  web.FileSystemDirectoryReader reader,
) {
  final completer = Completer<List<web.FileSystemEntry>>();
  reader.readEntries(
    ((JSArray<web.FileSystemEntry> entries) {
      if (!completer.isCompleted) completer.complete(entries.toDart);
    }).toJS,
    ((web.DOMException _) {
      if (!completer.isCompleted) completer.complete([]);
    }).toJS,
  );
  return completer.future;
}

Future<void> _collectEntryFiles(
  web.FileSystemEntry entry,
  String prefix,
  Set<String> extSet,
  List<PickedCurriculumFile> out,
) async {
  if (entry.isFile) {
    final name = entry.name;
    if (name.startsWith('.') || name.startsWith(r'~$')) return;
    if (!extSet.any(name.toLowerCase().endsWith)) return;
    final rel = prefix.isEmpty ? name : '$prefix/$name';
    final fileEntry = entry as web.FileSystemFileEntry;
    out.add((
      name: rel,
      readBytes: () async {
        final f = await _entryToFile(fileEntry);
        return f == null ? const [] : _readWebFile(f);
      },
    ));
  } else if (entry.isDirectory) {
    final dir = entry as web.FileSystemDirectoryEntry;
    final reader = dir.createReader();
    final nextPrefix = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
    while (true) {
      final batch = await _readDirOnce(reader);
      if (batch.isEmpty) break;
      for (final child in batch) {
        await _collectEntryFiles(child, nextPrefix, extSet, out);
      }
    }
  }
}

void Function() listenForDroppedFoldersImpl({
  required List<String> allowedExtensions,
  required void Function(List<PickedFolderBundle> folders) onFoldersDropped,
}) {
  final extSet = allowedExtensions.map((e) => '.${e.toLowerCase()}').toSet();

  final dragOverSub = const web.EventStreamProvider<web.DragEvent>('dragover')
      .forTarget(web.document)
      .listen((e) {
    e.preventDefault();
  });

  final dropSub = const web.EventStreamProvider<web.DragEvent>('drop')
      .forTarget(web.document)
      .listen((e) async {
    e.preventDefault();
    final items = e.dataTransfer?.items;
    if (items == null || items.length == 0) return;

    final entries = <web.FileSystemEntry>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      try {
        final rawEntry = item.callMethod('webkitGetAsEntry'.toJS);
        if (rawEntry != null && rawEntry.isA<web.FileSystemEntry>()) {
          entries.add(rawEntry as web.FileSystemEntry);
        }
      } catch (_) {}
    }
    if (entries.isEmpty) return;

    final bundles = <PickedFolderBundle>[];
    for (final entry in entries) {
      final collected = <PickedCurriculumFile>[];
      await _collectEntryFiles(entry, '', extSet, collected);
      if (collected.isNotEmpty) {
        bundles.add((label: entry.name, files: collected));
      }
    }
    if (bundles.isNotEmpty) {
      onFoldersDropped(bundles);
    }
  });

  return () {
    dragOverSub.cancel();
    dropSub.cancel();
  };
}
