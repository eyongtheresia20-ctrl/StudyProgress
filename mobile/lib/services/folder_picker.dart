import 'folder_picker_io.dart'
    if (dart.library.js_interop) 'folder_picker_web.dart' as impl;

typedef PickedCurriculumFile = ({
  String name,
  Future<List<int>> Function() readBytes,
});
typedef PickedFolderBundle = ({String label, List<PickedCurriculumFile> files});

const List<String> kDefaultCurriculumExtensions = [
  'csv',
  'xlsx',
  'xlsm',
  'xls',
  'json',
  'txt',
  'zip',
  'pdf',
  'doc',
  'docx',
];

Future<List<PickedCurriculumFile>> pickCurriculumFolder({
  List<String> allowedExtensions = kDefaultCurriculumExtensions,
}) =>
    impl.pickCurriculumFolderImpl(allowedExtensions: allowedExtensions);

Future<List<PickedCurriculumFile>> pickCurriculumFiles({
  List<String> allowedExtensions = kDefaultCurriculumExtensions,
}) =>
    impl.pickCurriculumFilesImpl(allowedExtensions: allowedExtensions);

void Function() listenForDroppedFolders({
  List<String> allowedExtensions = kDefaultCurriculumExtensions,
  required void Function(List<PickedFolderBundle> folders) onFoldersDropped,
}) =>
    impl.listenForDroppedFoldersImpl(
      allowedExtensions: allowedExtensions,
      onFoldersDropped: onFoldersDropped,
    );
