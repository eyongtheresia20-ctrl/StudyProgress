import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/study_models.dart';
import '../providers/study_provider.dart';
import '../services/folder_picker.dart';
import '../widgets/app_logo.dart';
import 'admin_profile_screen.dart';
import 'notifications_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const Color _deepNavy = Color(0xFF13346B);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _growthGreen = Color(0xFF10B981);

  int _tabIndex = 0;
  bool _uploading = false;
  bool _folderDialogOpen = false;
  String? _uploadProgressText;
  void Function()? _stopPageDropListener;
  String _userSearchQuery = '';
  String _userRoleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _stopPageDropListener = listenForDroppedFolders(
      allowedExtensions: kDefaultCurriculumExtensions,
      onFoldersDropped: (bundles) {
        if (!mounted || _folderDialogOpen || _uploading || bundles.isEmpty) {
          return;
        }
        final provider = context.read<StudyProvider>();
        final isFr = provider.languageCode == 'fr';
        final combined = [for (final b in bundles) ...b.files];
        if (combined.isNotEmpty) {
          _uploadPayloadInBatches(provider, combined, isFr);
        }
      },
    );
  }

  @override
  void dispose() {
    _stopPageDropListener?.call();
    super.dispose();
  }

  String _formattedToday(bool isFr) {
    final now = DateTime.now();
    const wdEn = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    const wdFr = [
      'LUNDI',
      'MARDI',
      'MERCREDI',
      'JEUDI',
      'VENDREDI',
      'SAMEDI',
      'DIMANCHE',
    ];
    const moEn = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    const moFr = [
      'JANVIER',
      'FÉVRIER',
      'MARS',
      'AVRIL',
      'MAI',
      'JUIN',
      'JUILLET',
      'AOÛT',
      'SEPTEMBRE',
      'OCTOBRE',
      'NOVEMBRE',
      'DÉCEMBRE',
    ];
    final wd = isFr ? wdFr[now.weekday - 1] : wdEn[now.weekday - 1];
    final mo = isFr ? moFr[now.month - 1] : moEn[now.month - 1];
    return '$wd, ${now.day} $mo';
  }

  void _openNotificationsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          onOpenTab: (tab) => setState(() => _tabIndex = tab),
        ),
      ),
    );
  }

  String _extractRootFolderName(List<PickedCurriculumFile> files) {
    final first = files.first.name.replaceAll('\\', '/');
    if (first.contains('/')) {
      return first.split('/').first;
    }
    return 'Selected Folder';
  }

  Future<void> _pickFilesDirectlyAndUpload(
    StudyProvider provider,
    bool isFr,
  ) async {
    try {
      final files = await pickCurriculumFiles(
        allowedExtensions: kDefaultCurriculumExtensions,
      );
      if (!mounted || files.isEmpty) return;
      await _uploadPayloadInBatches(provider, files, isFr);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload files: $e')),
      );
    }
  }

  Future<void> _pickFoldersDirectlyAndUpload(
    StudyProvider provider,
    bool isFr,
  ) async {
    try {
      final firstBatch = await pickCurriculumFolder(
        allowedExtensions: kDefaultCurriculumExtensions,
      );
      if (!mounted) return;
      if (firstBatch.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFr
                  ? 'Aucun fichier compatible trouvé (CSV, XLSX, XLS, PDF, DOCX, JSON, ZIP).'
                  : 'No supported files found in that folder (CSV, XLSX, XLS, PDF, DOCX, JSON, ZIP).',
            ),
          ),
        );
        return;
      }

      final queued = <PickedFolderBundle>[
        (label: _extractRootFolderName(firstBatch), files: firstBatch),
      ];

      void Function()? stopDropListener;
      _folderDialogOpen = true;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            stopDropListener ??= listenForDroppedFolders(
              allowedExtensions: kDefaultCurriculumExtensions,
              onFoldersDropped: (bundles) {
                if (ctx.mounted && bundles.isNotEmpty) {
                  setDialogState(() => queued.addAll(bundles));
                }
              },
            );

            final totalFiles = queued.fold<int>(
              0,
              (sum, f) => sum + f.files.length,
            );
            return AlertDialog(
              title: Text(
                isFr
                    ? 'Dossiers sélectionnés (${queued.length})'
                    : 'Selected Folders (${queued.length})',
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(queued.length, (i) {
                            final entry = queued[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.folder_outlined,
                                    color: _deepNavy,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        Text(
                                          '${entry.files.length} ${isFr ? 'fichier(s)' : 'file(s)'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (queued.length > 1)
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => setDialogState(
                                        () => queued.removeAt(i),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final more = await pickCurriculumFolder(
                            allowedExtensions: kDefaultCurriculumExtensions,
                          );
                          if (!ctx.mounted) return;
                          if (more.isNotEmpty) {
                            setDialogState(() {
                              queued.add((
                                label: _extractRootFolderName(more),
                                files: more,
                              ));
                            });
                          }
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: Text(
                          isFr
                              ? 'Ajouter un autre dossier'
                              : 'Add Another Folder',
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isFr
                          ? 'Astuce : Glissez-déposez plusieurs dossiers ici à la fois, ou ajoutez-en un par un.'
                          : 'Tip: Drag & drop multiple folders here at once, or add more one by one.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(isFr ? 'Annuler' : 'Cancel'),
                ),
                FilledButton(
                  onPressed:
                      totalFiles == 0 ? null : () => Navigator.pop(ctx, true),
                  child: Text(
                    isFr ? 'Importer ($totalFiles)' : 'Upload ($totalFiles)',
                  ),
                ),
              ],
            );
          },
        ),
      );
      stopDropListener?.call();
      _folderDialogOpen = false;

      if (confirmed == true && mounted) {
        final combined = [
          for (final q in queued) ...q.files,
        ];
        if (combined.isNotEmpty) {
          await _uploadPayloadInBatches(provider, combined, isFr);
        }
      }
    } catch (e) {
      _folderDialogOpen = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open folder: $e')),
      );
    }
  }

  Future<void> _uploadPayloadInBatches(
    StudyProvider provider,
    List<PickedCurriculumFile> payload,
    bool isFr,
  ) async {
    const chunkSize = 35;
    var progAdded = 0;
    var schedAdded = 0;
    var skipped = 0;
    final errors = <String>[];

    setState(() {
      _uploading = true;
      _uploadProgressText = '0 / ${payload.length}';
    });

    try {
      for (var i = 0; i < payload.length; i += chunkSize) {
        final end = (i + chunkSize < payload.length) ? i + chunkSize : payload.length;
        final batchHandles = payload.sublist(i, end);
        if (mounted) {
          setState(() => _uploadProgressText = '$end / ${payload.length}');
        }
        final resolved = await Future.wait(
          batchHandles.map((f) async => (name: f.name, bytes: await f.readBytes())),
        );
        final nonEmpty = resolved.where((e) => e.bytes.isNotEmpty).toList();
        if (nonEmpty.isEmpty) continue;
        final res = await provider.uploadCurriculumFiles(nonEmpty, refresh: false);
        progAdded += (res['programs_inserted'] as num?)?.toInt() ?? 0;
        schedAdded += (res['progressions_inserted'] as num?)?.toInt() ?? 0;
        skipped += (res['skipped_count'] as num?)?.toInt() ?? 0;
        for (final e in (res['errors'] as List<dynamic>? ?? [])) {
          if (errors.length < 15) errors.add(e.toString());
        }
      }
      await provider.refreshDashboard();

      if (!mounted) return;
      final previewNames = payload.take(5).map((e) => e.name).join(', ');
      final moreCount = payload.length > 5 ? ' (+${payload.length - 5} more)' : '';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isFr ? 'Importation terminée' : 'Upload Complete'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isFr ? 'Fichiers traités' : 'Files processed'}: ${payload.length}\n'
                  '$previewNames$moreCount',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                Text(
                  'Program topics added: $progAdded\n'
                  'Progression schedule slots added: $schedAdded\n'
                  'Skipped rows: $skipped',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...errors.map(
                    (e) => Text(
                      '• $e',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadProgressText = null;
        });
      }
    }
  }

  Future<void> _confirmDeleteFolder(
    BuildContext context,
    String folderName,
    bool isFr,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFr ? 'Supprimer le dossier ?' : 'Delete Folder?'),
        content: Text(
          isFr
              ? 'Voulez-vous supprimer "$folderName" ? Les métadonnées et fichiers seront retirés pour vous permettre de téléverser une version propre.'
              : 'Do you want to delete "$folderName"? Logs and stored files will be removed so you can upload a clean replacement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFr ? 'Annuler' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFr ? 'Supprimer' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await context.read<StudyProvider>().deleteUploadedFolder(folderName);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isFr
                    ? 'Dossier "$folderName" supprimé avec succès.'
                    : 'Folder "$folderName" deleted successfully.',
              ),
              backgroundColor: _growthGreen,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _toggleBlockUser(
    BuildContext context,
    StudyProvider provider,
    Map<String, dynamic> user,
    bool isFr,
  ) async {
    final userId = (user['id'] as num?)?.toInt() ?? 0;
    final userName = user['full_name']?.toString() ?? 'User';
    final isActive = user['is_active'] != false;
    final targetActive = !isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          targetActive
              ? (isFr ? 'Débloquer l\'utilisateur ?' : 'Unblock User?')
              : (isFr ? 'Bloquer l\'utilisateur ?' : 'Block User?'),
        ),
        content: Text(
          targetActive
              ? (isFr
                  ? 'Voulez-vous débloquer "$userName" ? Il pourra de nouveau se connecter et étudier.'
                  : 'Do you want to unblock "$userName"? They will be able to log in and study again.')
              : (isFr
                  ? 'Voulez-vous bloquer "$userName" ? Son compte sera désactivé et l\'accès à l\'application sera suspendu.'
                  : 'Do you want to block "$userName"? Their account will be deactivated and app access suspended.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFr ? 'Annuler' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  targetActive ? _growthGreen : Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              targetActive
                  ? (isFr ? 'Débloquer' : 'Unblock')
                  : (isFr ? 'Bloquer' : 'Block'),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await provider.updateUserStatus(userId, targetActive);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                targetActive
                    ? (isFr ? '$userName débloqué(e).' : '$userName unblocked.')
                    : (isFr ? '$userName bloqué(e).' : '$userName blocked.'),
              ),
              backgroundColor:
                  targetActive ? _growthGreen : Colors.orange.shade800,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteUser(
    BuildContext context,
    StudyProvider provider,
    Map<String, dynamic> user,
    bool isFr,
  ) async {
    final userId = (user['id'] as num?)?.toInt() ?? 0;
    final userName = user['full_name']?.toString() ?? 'User';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFr ? 'Supprimer l\'utilisateur ?' : 'Delete User?'),
        content: Text(
          isFr
              ? 'Voulez-vous supprimer définitivement le compte de "$userName" ? Cette action est irréversible.'
              : 'Do you want to permanently delete "$userName"? All their study progress and profile data will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFr ? 'Annuler' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFr ? 'Supprimer' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await provider.deleteAdminUser(userId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isFr ? 'Compte supprimé.' : 'User deleted.'),
              backgroundColor: _growthGreen,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _openAddUserDialog(
    BuildContext context,
    StudyProvider provider,
    bool isFr,
  ) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'student';
    int? selectedSubsystemId =
        provider.subsystems.isNotEmpty ? provider.subsystems.first.id : null;
    int? selectedClassId = provider.subsystems.isNotEmpty &&
            provider.subsystems.first.classes.isNotEmpty
        ? provider.subsystems.first.classes.first.id
        : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final currentSubsystem = provider.subsystems.firstWhere(
            (s) => s.id == selectedSubsystemId,
            orElse: () => provider.subsystems.isNotEmpty
                ? provider.subsystems.first
                : Subsystem(
                    id: 0,
                    code: '',
                    name: '',
                    description: '',
                    classes: [],
                  ),
          );
          final availableClasses = currentSubsystem.classes;

          return AlertDialog(
            title: Text(isFr ? 'Ajouter un Nouvel Élève' : 'Add New Student'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: isFr ? 'Nom complet' : 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: isFr ? 'Adresse Email' : 'Email Address',
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: isFr
                            ? 'Mot de passe (min 6 caractères)'
                            : 'Password (min 6 chars)',
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: isFr ? 'Rôle' : 'Role',
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'student',
                          child: Text(
                            isFr ? 'Élève (Student)' : 'Student',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text(
                            isFr ? 'Administrateur (Admin)' : 'Admin',
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setDlgState(() => role = v ?? 'student'),
                    ),
                    if (role == 'student' &&
                        provider.subsystems.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        initialValue: selectedSubsystemId,
                        decoration: InputDecoration(
                          labelText: isFr ? 'Sous-système' : 'Subsystem',
                          prefixIcon: const Icon(Icons.account_balance_outlined),
                        ),
                        items: provider.subsystems.map((sub) {
                          return DropdownMenuItem<int>(
                            value: sub.id,
                            child: Text(sub.name),
                          );
                        }).toList(),
                        onChanged: (subId) {
                          setDlgState(() {
                            selectedSubsystemId = subId;
                            final nextSub = provider.subsystems.firstWhere(
                              (s) => s.id == subId,
                              orElse: () => provider.subsystems.first,
                            );
                            selectedClassId = nextSub.classes.isNotEmpty
                                ? nextSub.classes.first.id
                                : null;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        initialValue: selectedClassId,
                        decoration: InputDecoration(
                          labelText: isFr ? 'Classe' : 'Class',
                          prefixIcon: const Icon(Icons.school_outlined),
                        ),
                        items: availableClasses.map((cls) {
                          return DropdownMenuItem<int>(
                            value: cls.id,
                            child: Text(cls.name),
                          );
                        }).toList(),
                        onChanged: (clsId) =>
                            setDlgState(() => selectedClassId = clsId),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(isFr ? 'Annuler' : 'Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final email = emailCtrl.text.trim();
                  final pass = passCtrl.text;
                  if (name.isEmpty || email.isEmpty || pass.length < 6) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          isFr
                              ? 'Veuillez remplir tous les champs (mot de passe 6+ car).'
                              : 'Please enter valid details (password min 6 chars).',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await provider.createAdminUser(
                      fullName: name,
                      email: email,
                      password: pass,
                      role: role,
                      subsystemId:
                          role == 'student' ? selectedSubsystemId : null,
                      classId: role == 'student' ? selectedClassId : null,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isFr
                                ? 'Utilisateur "$name" créé avec succès.'
                                : 'User "$name" created successfully.',
                          ),
                          backgroundColor: _growthGreen,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: Text(isFr ? 'Créer l\'Élève' : 'Create Student'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudyProvider>();
    final dash = provider.adminDashboard;
    final isFr = provider.languageCode == 'fr';
    final adminName =
        provider.user?.fullName ?? dash?.admin.fullName ?? 'Admin';
    final initial =
        adminName.trim().isNotEmpty ? adminName.trim()[0].toUpperCase() : 'A';

    final pages = [
      dash == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: provider.refreshDashboard,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                children: [
                  Text(
                    _formattedToday(isFr),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFr
                        ? 'Bonjour, $adminName ! 👋'
                        : 'Hello, $adminName! 👋',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isFr
                        ? 'Gérez les programmes officiels et les élèves.'
                        : 'Manage official programmes, progressions and students.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Direct Upload buttons: Multi-File picker (0 Chrome popups) + Multi-Folder picker
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _uploading
                            ? null
                            : () => _pickFilesDirectlyAndUpload(provider, isFr),
                        style: FilledButton.styleFrom(
                          backgroundColor: _deepNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _uploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.upload_file_rounded, size: 18),
                        label: Text(
                          _uploading
                              ? (isFr
                                  ? 'Importation (${_uploadProgressText ?? ""})...'
                                  : 'Uploading (${_uploadProgressText ?? ""})...')
                              : (isFr
                                  ? 'Importer Programme & Progression'
                                  : 'Upload Program & Progression'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _uploading
                            ? null
                            : () =>
                                _pickFoldersDirectlyAndUpload(provider, isFr),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _deepNavy,
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: Text(
                          isFr ? 'Importer Dossier(s)' : 'Upload Folder(s)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.55,
                    children: [
                      _AdminGlanceCard(
                        icon: Icons.account_tree_outlined,
                        iconColor: _primaryBlue,
                        value: '${dash.subsystemsCount}',
                        label: isFr ? 'Sous-systèmes' : 'Subsystems',
                      ),
                      _AdminGlanceCard(
                        icon: Icons.class_outlined,
                        iconColor: const Color(0xFF7C3AED),
                        value: '${dash.classesCount}',
                        label: isFr ? 'Classes' : 'Classes',
                      ),
                      _AdminGlanceCard(
                        icon: Icons.people_outline,
                        iconColor: _growthGreen,
                        value: '${dash.studentsCount}',
                        label: isFr ? 'Élèves inscrits' : 'Students',
                      ),
                      _AdminGlanceCard(
                        icon: Icons.menu_book_outlined,
                        iconColor: const Color(0xFFD97706),
                        value: '${dash.progressionsCount}',
                        label:
                            isFr ? 'Sujets programmés' : 'Scheduled Topics',
                      ),
                    ],
                  ),
                  if (dash.programTopicsCount > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.library_books_outlined,
                            color: _deepNavy,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isFr
                                  ? 'Programme par classe : ${dash.programTopicsCount} chapitre(s) & matière(s) prêts'
                                  : 'Class Program Library: ${dash.programTopicsCount} subject topic(s) active',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _deepNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isFr ? 'Dossiers importés' : 'Imported Folders',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _deepNavy,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _uploading
                            ? null
                            : () =>
                                _pickFoldersDirectlyAndUpload(provider, isFr),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEFF6FF),
                          foregroundColor: _primaryBlue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFFBFDBFE)),
                          ),
                        ),
                        icon: const Icon(Icons.create_new_folder_outlined,
                            size: 16),
                        label: Text(
                          isFr ? '+ Ajouter Dossier' : '+ Add Folder',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (dash.uploadedFolders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFCBD5E1),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.folder_open_outlined,
                              size: 36,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isFr
                                  ? 'Aucun dossier importé pour l\'instant.'
                                  : 'No imported curriculum folders yet.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isFr
                                  ? 'Cliquez sur "+ Ajouter Dossier" ci-dessus pour importer un dossier complet.'
                                  : 'Click "+ Add Folder" above to import a curriculum folder container.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...dash.uploadedFolders.map((folder) {
                      final fname = folder['folder_name']?.toString() ?? 'Folder';
                      final fcount = (folder['files_count'] as num?)?.toInt() ?? 0;
                      final tcount = (folder['topics_added'] as num?)?.toInt() ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: _deepNavy.withAlpha(20),
                              child: const Icon(
                                Icons.folder_rounded,
                                color: _deepNavy,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    isFr
                                        ? '$fcount fichier(s) · $tcount sujet(s) ajouté(s)'
                                        : '$fcount file(s) · $tcount topic(s) added',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _growthGreen.withAlpha(28),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        color: _growthGreen,
                                        size: 13,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isFr ? 'Importé' : 'Imported',
                                        style: const TextStyle(
                                          color: _growthGreen,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _confirmDeleteFolder(
                                    context,
                                    fname,
                                    isFr,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withAlpha(18),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.withAlpha(80),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 14,
                                          color: Colors.redAccent,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isFr ? 'Supprimer' : 'Delete',
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
      dash == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (ctx) {
                final allUsers = dash.recentStudents.where((u) {
                  final role = (u['role'] ?? 'student').toString().toLowerCase();
                  return role != 'admin';
                }).toList();
                final filteredUsers = allUsers.where((u) {
                  final name =
                      (u['full_name'] ?? '').toString().toLowerCase();
                  final email = (u['email'] ?? '').toString().toLowerCase();
                  final matchesSearch = _userSearchQuery.isEmpty ||
                      name.contains(_userSearchQuery) ||
                      email.contains(_userSearchQuery);
                  if (!matchesSearch) return false;

                  final isActive = u['is_active'] != false;
                  if (_userRoleFilter == 'active') return isActive;
                  if (_userRoleFilter == 'blocked') return !isActive;
                  return true;
                }).toList();

                return ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isFr
                                    ? 'Élèves Inscrits'
                                    : 'Registered Students',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                isFr
                                    ? '${filteredUsers.length} élève(s) inscrit(s)'
                                    : '${filteredUsers.length} student(s) registered',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: Text(
                            isFr ? '+ Ajouter un Élève' : '+ Add Student',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onPressed: () => _openAddUserDialog(
                            context,
                            provider,
                            isFr,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: isFr
                            ? 'Rechercher par nom ou email...'
                            : 'Search by name or email...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _userSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () =>
                                    setState(() => _userSearchQuery = ''),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      onChanged: (v) =>
                          setState(() => _userSearchQuery = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(isFr ? 'Tous' : 'All'),
                            selected: _userRoleFilter == 'all',
                            onSelected: (_) =>
                                setState(() => _userRoleFilter = 'all'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(isFr ? 'Élèves' : 'Students'),
                            selected: _userRoleFilter == 'student',
                            onSelected: (_) =>
                                setState(() => _userRoleFilter = 'student'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(isFr ? 'Admins' : 'Admins'),
                            selected: _userRoleFilter == 'admin',
                            onSelected: (_) =>
                                setState(() => _userRoleFilter = 'admin'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(isFr ? 'Actifs' : 'Active'),
                            selected: _userRoleFilter == 'active',
                            onSelected: (_) =>
                                setState(() => _userRoleFilter = 'active'),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(isFr ? 'Bloqués' : 'Blocked'),
                            selected: _userRoleFilter == 'blocked',
                            onSelected: (_) =>
                                setState(() => _userRoleFilter = 'blocked'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (filteredUsers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          isFr
                              ? 'Aucun utilisateur ne correspond à ce filtre.'
                              : 'No users matching this filter.',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      )
                    else
                      ...filteredUsers.map((s) {
                        final role = (s['role'] ?? 'student')
                            .toString()
                            .toLowerCase();
                        final isAdmin = role == 'admin';
                        final isActive = s['is_active'] != false;
                        final isSelf =
                            s['id'] == (provider.user?.id ?? dash.admin.id);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFFE2E8F0)
                                  : Colors.red.shade200,
                              width: isActive ? 1.0 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(8),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isAdmin
                                        ? const Color(0xFFEDE9FE)
                                        : const Color(0xFFDBEAFE),
                                    child: Icon(
                                      isAdmin
                                          ? Icons.admin_panel_settings_rounded
                                          : Icons.school_outlined,
                                      color: isAdmin
                                          ? Colors.deepPurple
                                          : _primaryBlue,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                s['full_name']?.toString() ?? '',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                  color: isActive
                                                      ? const Color(0xFF0F172A)
                                                      : Colors.red.shade800,
                                                  decoration: isActive
                                                      ? null
                                                      : TextDecoration.lineThrough,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isActive
                                                    ? _growthGreen.withAlpha(24)
                                                    : Colors.red.withAlpha(24),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                isActive
                                                    ? (isFr ? 'Actif' : 'Active')
                                                    : (isFr ? 'Bloqué' : 'Blocked'),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: isActive
                                                      ? _growthGreen
                                                      : Colors.red.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${s['email']} • ${isAdmin ? (isFr ? 'Admin' : 'Admin') : '${s['subsystem_name'] ?? '-'} • ${s['class_name'] ?? '-'}'}',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelf)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isFr ? 'Vous' : 'You',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (!isSelf) ...[
                                const SizedBox(height: 10),
                                const Divider(
                                  height: 1,
                                  color: Color(0xFFF1F5F9),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: isActive
                                            ? Colors.orange.shade800
                                            : _growthGreen,
                                        side: BorderSide(
                                          color: isActive
                                              ? Colors.orange.shade300
                                              : _growthGreen.withAlpha(120),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: Icon(
                                        isActive
                                            ? Icons.block_rounded
                                            : Icons.check_circle_outline_rounded,
                                        size: 15,
                                      ),
                                      label: Text(
                                        isActive
                                            ? (isFr ? 'Bloquer' : 'Block')
                                            : (isFr ? 'Débloquer' : 'Unblock'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      onPressed: () => _toggleBlockUser(
                                        context,
                                        provider,
                                        s,
                                        isFr,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.redAccent,
                                        side: BorderSide(
                                          color: Colors.redAccent.withAlpha(120),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 15,
                                      ),
                                      label: Text(
                                        isFr ? 'Supprimer' : 'Delete',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      onPressed: () => _confirmDeleteUser(
                                        context,
                                        provider,
                                        s,
                                        isFr,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
      const AdminProfileBody(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.4,
        titleSpacing: 16,
        title: const Row(
          children: [
            KivoraLogo(size: 32),
            SizedBox(width: 10),
            Text(
              'Kivora',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: ['en', 'fr'].map((code) {
                final active = provider.languageCode == code;
                return GestureDetector(
                  onTap: () => provider.setLanguage(code),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? _deepNavy : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      code.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.white : _deepNavy,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: isFr ? 'Notifications' : 'Notifications',
            onPressed: _openNotificationsScreen,
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: Color(0xFF334155),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 2),
            child: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'profile') {
                  setState(() => _tabIndex = 2);
                } else if (value == 'logout') {
                  provider.logout();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'profile',
                  child: Text(isFr ? 'Profil' : 'Profile'),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Text(isFr ? 'Déconnexion' : 'Sign Out'),
                ),
              ],
              child: CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0xFFDBEAFE),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tabIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        indicatorColor: const Color(0xFFDBEAFE),
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard, color: _primaryBlue),
            label: isFr ? 'Accueil' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people, color: _primaryBlue),
            label: isFr ? 'Élèves' : 'Students',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person, color: _primaryBlue),
            label: isFr ? 'Profil' : 'Profile',
          ),
        ],
      ),
    );
  }
}

class _AdminGlanceCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _AdminGlanceCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
