with open('mobile/lib/screens/student_home_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read().replace('\r\n', '\n')

old_state = """class _MyProgrammeTabState extends State<_MyProgrammeTab> {
  int _filterIndex = 0; // 0 = Daily, 1 = Weekly
  String? _selectedSubject;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final home = widget.home;
    final profile = home?.profile;
    final rawList = _filterIndex == 0
        ? (home?.todayTopics ?? [])
        : (_filterIndex == 1
            ? (home?.weeklyTopics ?? [])
            : (home?.allTopics ?? []));

    final subjects = <String>{
      for (final t in rawList)
        if (t.subjectName.isNotEmpty) t.subjectName,
    }.toList()
      ..sort();

    final list = _selectedSubject == null
        ? rawList
        : rawList.where((t) => t.subjectName == _selectedSubject).toList();"""

new_state = """class _MyProgrammeTabState extends State<_MyProgrammeTab> {
  int _filterIndex = 0; // 0 = Daily, 1 = Weekly
  String? _selectedSubject;
  int? _selectedWeekday; // null = all week, 0 = Lundi, 1 = Mardi, 2 = Mercredi, 3 = Jeudi, 4 = Vendredi, 5 = Weekend Revision

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final home = widget.home;
    final profile = home?.profile;
    var rawList = _filterIndex == 0
        ? (home?.todayTopics ?? [])
        : (home?.weeklyTopics ?? []);

    if (_filterIndex == 1 && _selectedWeekday != null) {
      if (_selectedWeekday == 5) {
        // Weekend Revision
        final rev = rawList.where((t) {
          final d = (t.studyDays ?? '').toLowerCase();
          return d.contains('samedi') || d.contains('saturday') || d.contains('révision') || d.contains('revision');
        }).toList();
        rawList = rev.isNotEmpty ? rev : rawList;
      } else {
        const dayKeys = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi'];
        final key = dayKeys[_selectedWeekday!];
        rawList = rawList.where((t) => (t.studyDays ?? '').toLowerCase().contains(key)).toList();
      }
    }

    final subjects = <String>{
      for (final t in rawList)
        if (t.subjectName.isNotEmpty) t.subjectName,
    }.toList()
      ..sort();

    final list = _selectedSubject == null
        ? rawList
        : rawList.where((t) => t.subjectName == _selectedSubject).toList();"""

assert old_state in text, "old_state not found"
text = text.replace(old_state, new_state)

# Add Day filter chips when in Weekly mode (_filterIndex == 1)
old_wrap = """                  ChoiceChip(
                    label: Text(s.tabWeekly),
                    selected: _filterIndex == 1,
                    onSelected: (_) => setState(() {
                      _filterIndex = 1;
                      _selectedSubject = null;
                    }),
                  ),
                ],
              ),"""

new_wrap = """                  ChoiceChip(
                    label: Text(s.tabWeekly),
                    selected: _filterIndex == 1,
                    onSelected: (_) => setState(() {
                      _filterIndex = 1;
                      _selectedSubject = null;
                    }),
                  ),
                ],
              ),
              if (_filterIndex == 1) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Toute la semaine' : 'All Week'),
                          selected: _selectedWeekday == null,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = null;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Lundi' : 'Monday'),
                          selected: _selectedWeekday == 0,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 0;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Mardi' : 'Tuesday'),
                          selected: _selectedWeekday == 1,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 1;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Mercredi' : 'Wednesday'),
                          selected: _selectedWeekday == 2,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 2;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Jeudi' : 'Thursday'),
                          selected: _selectedWeekday == 3,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 3;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(s.isFr ? 'Vendredi' : 'Friday'),
                          selected: _selectedWeekday == 4,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 4;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          avatar: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFFD97706)),
                          label: Text(s.isFr ? 'Sam - Dim (Révision)' : 'Sat - Sun (Revision)'),
                          selected: _selectedWeekday == 5,
                          onSelected: (_) => setState(() {
                            _selectedWeekday = 5;
                            _selectedSubject = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ],"""

assert old_wrap in text, "old_wrap not found"
text = text.replace(old_wrap, new_wrap)

# Add Day Badge on Card in _MyProgrammeTab
old_card_head = """                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${topic.subjectName} • ${s.weekLabel(topic.weekNumber)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  s.scheduled,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ],
                          ),"""

new_card_head = """                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${topic.subjectName} • ${s.weekLabel(topic.weekNumber)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  s.scheduled,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (topic.studyDays != null && topic.studyDays!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.event_note_rounded, size: 13, color: Color(0xFF1D4ED8)),
                                  const SizedBox(width: 6),
                                  Text(
                                    s.isFr
                                        ? (topic.studyDays!.contains('·') ? topic.studyDays!.split('·').first.trim() : topic.studyDays!)
                                        : (topic.studyDays!.contains('·') ? topic.studyDays!.split('·').last.trim() : topic.studyDays!),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1E40AF),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],"""

assert old_card_head in text, "old_card_head not found"
text = text.replace(old_card_head, new_card_head)

with open('mobile/lib/screens/student_home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated student_home_screen.dart successfully!")

