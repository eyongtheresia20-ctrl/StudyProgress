# Update ApiService timeout to 35s
with open('mobile/lib/services/api_service.dart', 'r', encoding='utf-8') as f:
    text = f.read().replace('\r\n', '\n')

old_timeout = ".timeout(const Duration(seconds: 12));"
new_timeout = ".timeout(const Duration(seconds: 35));"
if old_timeout in text:
    text = text.replace(old_timeout, new_timeout)
    with open('mobile/lib/services/api_service.dart', 'w', encoding='utf-8') as f:
        f.write(text)
    print("Updated api_service.dart timeout to 35s!")

# Update ai_tutor_screen.dart
with open('mobile/lib/screens/ai_tutor_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read().replace('\r\n', '\n')

# 1. Add _translating state variable if not present
if 'bool _translating = false;' not in text:
    text = text.replace(
        'String? _activeLanguage;',
        'String? _activeLanguage;\n  bool _translating = false;'
    )

# 2. Add _translateAllActiveContent method
trans_method = """  Future<void> _translateAllActiveContent(StudyProvider provider, String targetLang) async {
    final hasSummary = _summaryOutput != null && _summaryOutput!.trim().isNotEmpty;
    final hasAsk = _askOutput != null && _askOutput!.trim().isNotEmpty;
    if (!hasSummary && !hasAsk) return;
    if (_translating) return;

    if (mounted) setState(() => _translating = true);

    try {
      if (hasSummary) {
        final translated = await provider.api.translateText(
          text: _summaryOutput!,
          targetLanguage: targetLang,
        );
        if (mounted && translated.trim().isNotEmpty) {
          setState(() {
            _summaryOutput = translated;
          });
        }
      }
      if (hasAsk) {
        final translated = await provider.api.translateText(
          text: _askOutput!,
          targetLanguage: targetLang,
        );
        if (mounted && translated.trim().isNotEmpty) {
          setState(() {
            _askOutput = translated;
          });
        }
      }
    } catch (_) {
      // Keep existing content if translation encounters network issue
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }
"""

if '_translateAllActiveContent' not in text:
    text = text.replace(
        '  Widget _buildHistoryDrawer(AppStrings s) {',
        trans_method + '\n  Widget _buildHistoryDrawer(AppStrings s) {'
    )

# 3. Replace the language check in build() to call _translateAllActiveContent
old_build_lang = """    if (_activeLanguage != null && _activeLanguage != currentLang) {
      _activeLanguage = currentLang;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (_summaryOutput != null && _summaryOutput!.trim().isNotEmpty) {
          final translated = await provider.api.translateText(
            text: _summaryOutput!,
            targetLanguage: currentLang,
          );
          if (mounted) setState(() => _summaryOutput = translated);
        } else if (_askOutput != null && _askOutput!.trim().isNotEmpty) {
          final translated = await provider.api.translateText(
            text: _askOutput!,
            targetLanguage: currentLang,
          );
          if (mounted) setState(() => _askOutput = translated);
        }
      });
    } else {
      _activeLanguage = currentLang;
    }"""

new_build_lang = """    if (_activeLanguage != null && _activeLanguage != currentLang) {
      _activeLanguage = currentLang;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _translateAllActiveContent(provider, currentLang);
        }
      });
    } else {
      _activeLanguage = currentLang;
      // Auto-detect language mismatch and translate immediately
      if (!_translating) {
        final hasSummary = _summaryOutput != null && _summaryOutput!.trim().isNotEmpty;
        final hasAsk = _askOutput != null && _askOutput!.trim().isNotEmpty;
        if (hasSummary || hasAsk) {
          final sample = hasSummary ? _summaryOutput! : _askOutput!;
          final isFrenchContent = RegExp(r'\\b(le|la|les|dans|nous|cours|avec|pour|est|sont|bonjour|chapitre)\\b', caseSensitive: false).allMatches(sample).length >= 3;
          final isEnglishContent = RegExp(r'\\b(the|and|with|this|lesson|chapter|are|for|sound|waves|good morning)\\b', caseSensitive: false).allMatches(sample).length >= 3;
          if (currentLang == 'en' && isFrenchContent && !isEnglishContent) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _translateAllActiveContent(provider, 'en');
            });
          } else if (currentLang == 'fr' && isEnglishContent && !isFrenchContent) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _translateAllActiveContent(provider, 'fr');
            });
          }
        }
      }
    }"""

assert old_build_lang in text, "old_build_lang not found"
text = text.replace(old_build_lang, new_build_lang)

# 4. Add translation banner indicator above output when _translating is true
old_summary_card = """                  if (_summaryOutput != null) ...[
                    Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: ["""

new_summary_card = """                  if (_translating)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1D4ED8)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              s.isFr
                                  ? 'Traduction automatique en français...'
                                  : 'Translating everything to English...',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_summaryOutput != null) ...[
                    Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: ["""

assert old_summary_card in text, "old_summary_card not found"
text = text.replace(old_summary_card, new_summary_card)

with open('mobile/lib/screens/ai_tutor_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print("Updated ai_tutor_screen.dart for instant automatic translation successfully!")

