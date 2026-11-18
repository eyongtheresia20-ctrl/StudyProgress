import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/study_models.dart';
import '../services/link_opener.dart';
import '../services/voice_speaker.dart';

const Color _kDeepNavy = Color(0xFF0F2942);
const Color _kPrimaryBlue = Color(0xFF1E40AF);
const Color _kAiPurple = Color(0xFF7C3AED);

/// Parses teacher markdown (headings, bold/italic/code, callouts, lists, and
/// comparison tables) into clean classroom-ready widgets without raw `#`/`**`/`|`,
/// optionally interleaving verified reference images and visual diagrams in between sections.
class TeacherNotesView extends StatelessWidget {
  final String content;
  final List<Map<String, String>> inlineImages;
  final List<NoteDiagram> inlineDiagrams;
  final bool isFr;
  final String? studentName;

  const TeacherNotesView({
    super.key,
    required this.content,
    this.inlineImages = const [],
    this.inlineDiagrams = const [],
    this.isFr = false,
    this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    final cleanContent = _cleanMathNotation(content, studentName, isFr).trim();
    final blocks = _parseBlocks(cleanContent, studentName, isFr);
    if (blocks.isEmpty) {
      if (cleanContent.isEmpty ||
          cleanContent.startsWith('{') ||
          cleanContent.contains('"sprite":') ||
          cleanContent.contains('"scale":')) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            isFr
                ? 'Génération des notes complètes du cours... Cliquez sur Actualiser si besoin.'
                : 'Generating complete lesson notes... Click refresh if needed.',
            style: const TextStyle(
              height: 1.5,
              color: Color(0xFF64748B),
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      }
      return SelectableText(cleanContent, style: const TextStyle(height: 1.5));
    }

    final validImages = inlineImages.where((item) {
      final img = (item['image_url'] ?? '').trim();
      final uri = Uri.tryParse(img);
      return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
    }).toList();

    final children = <Widget>[];
    var h2Count = 0;
    var imgCursor = 0;
    var diagCursor = 0;
    final shownGates = <String>{};

    for (final b in blocks) {
      if (b.type == _BlockType.h2) {
        if (h2Count > 0) {
          if (imgCursor < validImages.length) {
            children.add(_buildInlineImageCard(validImages[imgCursor++]));
          }
          if (diagCursor < inlineDiagrams.length) {
            children.add(DiagramCard(diagram: inlineDiagrams[diagCursor++]));
          }
        }
        h2Count++;
      }
      children.add(_buildBlock(context, b));
      final gate = _detectLogicGate(b.text);
      if (gate != null && shownGates.add(gate)) {
        children.add(_LogicGateDiagramCard(gateType: gate));
      }
    }

    // Append any remaining visual figures/diagrams cleanly at the end.
    while (imgCursor < validImages.length) {
      children.add(_buildInlineImageCard(validImages[imgCursor++]));
    }
    while (diagCursor < inlineDiagrams.length) {
      children.add(DiagramCard(diagram: inlineDiagrams[diagCursor++]));
    }

    final validLinks = inlineImages.where((item) {
      final u = (item['url'] ?? '').trim();
      final uri = Uri.tryParse(u);
      return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
    }).toList();

    if (validLinks.isNotEmpty) {
      children.add(_buildEnlightenSection(validLinks));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildEnlightenSection(List<Map<String, String>> links) {
    return Container(
      margin: const EdgeInsets.only(top: 18, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.menu_book_rounded,
                size: 18,
                color: Color(0xFF15803D),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFr
                      ? 'Pour approfondir ce sujet — Liens de référence vérifiés'
                      : 'Enlighten Yourself More — Verified Reference Links',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...links.map((src) {
            final title = (src['title'] ?? '').trim();
            final url = (src['url'] ?? '').trim();
            final sourceName =
                (src['source'] ?? src['provider'] ?? 'Source').trim();
            final snippet = (src['snippet'] ?? '').trim();

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDCFCE7)),
              ),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                leading: const CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(0xFFDCFCE7),
                  child: Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: Color(0xFF15803D),
                  ),
                ),
                title: Text(
                  title.isNotEmpty ? title : url,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  '$sourceName${snippet.isNotEmpty ? ' • $snippet' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF475569),
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: Color(0xFF15803D),
                ),
                onTap: () => openExternalUrl(url),
              ),
            );
          }),
        ],
      ),
    );
  }

  String? _detectLogicGate(String text) {
    final t = text.toUpperCase();
    // Only detect if this is genuinely a lesson discussing digital logic gates or boolean circuits
    final isExplicitLogicCircuit = RegExp(
      r'\b(LOGIC\s+GATE|PORTE\s+LOGIQUE|BOOLEAN\s+CIRCUIT|DIGITAL\s+LOGIC|CIRCUIT\s+LOGIQUE)\b',
    ).hasMatch(t);
    if (!isExplicitLogicCircuit) {
      return null;
    }
    if (RegExp(r'\bNAND\s+GATE\b|\bPORTE\s+NAND\b').hasMatch(t)) return 'NAND';
    if (RegExp(r'\bNOR\s+GATE\b|\bPORTE\s+NOR\b').hasMatch(t)) return 'NOR';
    if (RegExp(r'\bXNOR\s+GATE\b|\bPORTE\s+XNOR\b').hasMatch(t)) return 'XNOR';
    if (RegExp(r'\bXOR\s+GATE\b|\bPORTE\s+XOR\b').hasMatch(t)) return 'XOR';
    if (RegExp(r'\bNOT\s+GATE\b|\bINVERTER\s+GATE\b|\bPORTE\s+NON\b').hasMatch(t)) return 'NOT';
    if (RegExp(r'\bAND\s+GATE\b|\bPORTE\s+ET\b').hasMatch(t)) return 'AND';
    if (RegExp(r'\bOR\s+GATE\b|\bPORTE\s+OU\b').hasMatch(t)) return 'OR';
    return null;
  }

  Widget _buildInlineImageCard(Map<String, String> item) {
    final imgUrl = (item['image_url'] ?? '').trim();
    final pageUrl = (item['url'] ?? '').trim();
    final title = (item['title'] ?? '').trim();
    final source = (item['source'] ?? item['provider'] ?? '').trim();
    final pageUri = Uri.tryParse(pageUrl);
    final canOpen = pageUri != null &&
        (pageUri.isScheme('http') || pageUri.isScheme('https'));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: MouseRegion(
        cursor: canOpen ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: canOpen ? () => openExternalUrl(pageUrl) : null,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                  child: Image.network(
                    imgUrl,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 90,
                      color: const Color(0xFFE2E8F0),
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        size: 16,
                        color: _kPrimaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          source.isNotEmpty && title.isNotEmpty
                              ? '$title · $source'
                              : (title.isNotEmpty ? title : pageUrl),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _kDeepNavy,
                          ),
                        ),
                      ),
                      if (canOpen) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 15,
                          color: _kPrimaryBlue,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(BuildContext context, _NoteBlock block) {
    switch (block.type) {
      case _BlockType.h1:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kDeepNavy, _kPrimaryBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.school_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _stripOuterBold(block.text),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );

      case _BlockType.h2:
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: _kPrimaryBlue,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _stripOuterBold(block.text),
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: _kDeepNavy,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );

      case _BlockType.h3:
        return Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 5),
          child: Text(
            _stripOuterBold(block.text),
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: _kPrimaryBlue,
              height: 1.35,
            ),
          ),
        );

      case _BlockType.divider:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
        );

      case _BlockType.callout:
        final isWarning = block.calloutLabel.toLowerCase().contains('watch') ||
            block.calloutLabel.toLowerCase().contains('exam') ||
            block.calloutLabel.toLowerCase().contains('attention') ||
            block.calloutLabel.toLowerCase().contains('mistake');
        final isFormula = block.calloutLabel.toLowerCase().contains('formula') ||
            block.calloutLabel.toLowerCase().contains('rule');
        final bg = isWarning
            ? const Color(0xFFFFFBEB)
            : (isFormula ? const Color(0xFFF5F3FF) : const Color(0xFFECFDF5));
        final border = isWarning
            ? const Color(0xFFFDE68A)
            : (isFormula ? const Color(0xFFDDD6FE) : const Color(0xFFA7F3D0));
        final accent = isWarning
            ? const Color(0xFFB45309)
            : (isFormula ? _kAiPurple : const Color(0xFF047857));
        final icon = isWarning
            ? Icons.warning_amber_rounded
            : (isFormula
                ? Icons.functions_rounded
                : Icons.lightbulb_outline_rounded);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 13.8,
                      color: Color(0xFF1E293B),
                      height: 1.48,
                    ),
                    children: [
                      if (block.calloutLabel.isNotEmpty)
                        TextSpan(
                          text: '${block.calloutLabel} ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ..._parseInlineSpans(
                        block.text,
                        const TextStyle(
                          fontSize: 13.8,
                          color: Color(0xFF1E293B),
                          height: 1.48,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

      case _BlockType.bullet:
        return Padding(
          padding: const EdgeInsets.only(left: 4, top: 3, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: block.marker.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _kPrimaryBlue.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          block.marker,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: _kPrimaryBlue,
                          ),
                        ),
                      )
                    : Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: _kPrimaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1E293B),
                      height: 1.5,
                    ),
                    children: _parseInlineSpans(
                      block.text,
                      const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1E293B),
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

      case _BlockType.table:
        return _buildMarkdownTable(block.tableRows);

      case _BlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 7),
          child: SelectableText.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 14.2,
                color: Color(0xFF1E293B),
                height: 1.55,
              ),
              children: _parseInlineSpans(
                block.text,
                const TextStyle(
                  fontSize: 14.2,
                  color: Color(0xFF1E293B),
                  height: 1.55,
                ),
              ),
            ),
          ),
        );
    }
  }

  Widget _buildMarkdownTable(List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.fold<int>(
      1,
      (prev, r) => r.length > prev ? r.length : prev,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        color: Colors.white,
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: colCount == 2 ? 320 : 420,
          ),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
            border: const TableBorder.symmetric(
              inside: BorderSide(color: Color(0xFFE2E8F0)),
            ),
            children: List.generate(rows.length, (rIdx) {
              final isHeader = rIdx == 0;
              final row = rows[rIdx];
              return TableRow(
                decoration: BoxDecoration(
                  color: isHeader
                      ? _kDeepNavy
                      : (rIdx.isOdd ? Colors.white : const Color(0xFFF8FAFC)),
                ),
                children: List.generate(colCount, (cIdx) {
                  final cellText = cIdx < row.length ? row[cIdx] : '';
                  final style = TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: isHeader ? FontWeight.w800 : FontWeight.w500,
                    color: isHeader ? Colors.white : const Color(0xFF1E293B),
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: isHeader
                        ? Text(_stripOuterBold(cellText), style: style)
                        : Text.rich(
                            TextSpan(
                              style: style,
                              children: _parseInlineSpans(cellText, style),
                            ),
                          ),
                  );
                }),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Visual diagram card for side-by-side comparisons and node-arrow concept/flow maps.
class DiagramCard extends StatelessWidget {
  final NoteDiagram diagram;

  const DiagramCard({super.key, required this.diagram});

  @override
  Widget build(BuildContext context) {
    final isComparison = diagram.diagramType == 'comparison' &&
        diagram.comparisonRows.isNotEmpty;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: (isComparison ? _kPrimaryBlue : _kAiPurple)
                        .withAlpha(24),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    isComparison
                        ? Icons.compare_arrows_rounded
                        : Icons.account_tree_outlined,
                    size: 19,
                    color: isComparison ? _kPrimaryBlue : _kAiPurple,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diagram.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: _kDeepNavy,
                        ),
                      ),
                      if (diagram.subtitle.isNotEmpty)
                        Text(
                          diagram.subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isComparison) _buildComparisonBoard() else _buildFlowDiagram(),
            if (diagram.takeaway.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                      color: Color(0xFF047857),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        diagram.takeaway,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _kDeepNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonBoard() {
    final leftTitle =
        diagram.leftLabel.isNotEmpty ? diagram.leftLabel : 'Concept A';
    final rightTitle =
        diagram.rightLabel.isNotEmpty ? diagram.rightLabel : 'Concept B';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: _kPrimaryBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  leftTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
              child: const Text(
                'VS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _kDeepNavy,
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: _kAiPurple,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  rightTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...diagram.comparisonRows.map(
          (row) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              color: const Color(0xFFF8FAFC),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(9)),
                  ),
                  child: Text(
                    row.criterion,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _kDeepNavy,
                    ),
                  ),
                ),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            row.leftValue,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            row.rightValue,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlowDiagram() {
    if (diagram.nodes.isEmpty) {
      return const SizedBox.shrink();
    }

    final edgeByFrom = <String, DiagramEdge>{};
    for (final e in diagram.edges) {
      edgeByFrom.putIfAbsent(e.fromId, () => e);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: List.generate(diagram.nodes.length, (i) {
          final node = diagram.nodes[i];
          final edge = edgeByFrom[node.id] ??
              (i < diagram.edges.length ? diagram.edges[i] : null);
          final isStart = node.role == 'start' || i == 0;
          final isEnd =
              node.role == 'outcome' || i == diagram.nodes.length - 1;
          final borderColor = isStart
              ? const Color(0xFF059669)
              : (isEnd ? _kAiPurple : _kPrimaryBlue);
          final bgColor = isStart
              ? const Color(0xFFECFDF5)
              : (isEnd ? const Color(0xFFF5F3FF) : const Color(0xFFEFF6FF));

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Column(
                  children: [
                    Text(
                      node.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: borderColor,
                      ),
                    ),
                    if (node.detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        node.detail,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.2,
                          color: Color(0xFF334155),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (i < diagram.nodes.length - 1)
                _FlowArrowConnector(label: edge?.label ?? ''),
            ],
          );
        }),
      ),
    );
  }
}

class _FlowArrowConnector extends StatelessWidget {
  final String label;

  const _FlowArrowConnector({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(24, 28),
            painter: _ArrowPainter(),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kPrimaryBlue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    canvas.drawLine(Offset(cx, 2), Offset(cx, size.height - 6), paint);

    final head = Path()
      ..moveTo(cx - 5, size.height - 10)
      ..lineTo(cx, size.height - 2)
      ..lineTo(cx + 5, size.height - 10);
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Interactive in-app AI-created animated explainer / video simulation player.
class AiVideoExplainerPlayer extends StatefulWidget {
  final SimulationData simulation;
  final bool isFr;

  const AiVideoExplainerPlayer({
    super.key,
    required this.simulation,
    required this.isFr,
  });

  @override
  State<AiVideoExplainerPlayer> createState() => _AiVideoExplainerPlayerState();
}

class _AiVideoExplainerPlayerState extends State<AiVideoExplainerPlayer>
    with SingleTickerProviderStateMixin {
  int _sceneIndex = 0;
  bool _playing = false;
  bool _voiceEnabled = true;
  bool _speaking = false;
  double _speed = 1.0;
  double _simIntensity = 0.75;
  Offset? _highlightNorm;
  String? _inspectedInfo;
  int _playSession = 0;
  Timer? _sceneTimer;
  late final VoiceSpeaker _speaker;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _speaker = createVoiceSpeaker();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant AiVideoExplainerPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.simulation.title != widget.simulation.title ||
        oldWidget.simulation.steps.length != widget.simulation.steps.length) {
      _stopPlayback(resetIndex: true);
    }
  }

  @override
  void dispose() {
    _playSession++;
    _sceneTimer?.cancel();
    _sceneTimer = null;
    _speaker.stop();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _stopPlayback({bool resetIndex = false}) {
    _playSession++;
    _sceneTimer?.cancel();
    _sceneTimer = null;
    _speaker.stop();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _speaking = false;
      if (resetIndex) _sceneIndex = 0;
    });
  }

  String _narrationForStep(SimulationStep step, int idx, int total) {
    final prefix = widget.isFr
        ? 'Scène ${idx + 1} sur $total. ${step.title}.'
        : 'Scene ${idx + 1} of $total. ${step.title}.';
    final outcome = step.outcome.trim();
    if (outcome.isEmpty) {
      return '$prefix ${step.action}';
    }
    return '$prefix ${step.action} $outcome';
  }

  void _advanceAfterScene(int session) {
    if (!mounted || session != _playSession || !_playing) return;
    final total = widget.simulation.steps.length;
    if (_sceneIndex >= total - 1) {
      _stopPlayback();
      return;
    }
    final nextIdx = _sceneIndex + 1;
    setState(() => _sceneIndex = nextIdx);
    _playScene(nextIdx, autoAdvance: true);
  }

  Future<void> _playScene(int idx, {required bool autoAdvance}) async {
    final steps = widget.simulation.steps;
    if (steps.isEmpty) return;
    final safeIdx = idx.clamp(0, steps.length - 1);
    final step = steps[safeIdx];

    final session = ++_playSession;
    _sceneTimer?.cancel();
    _sceneTimer = null;
    await _speaker.stop();
    if (!mounted || session != _playSession) return;

    final narration = _narrationForStep(step, safeIdx, steps.length);
    var speechStarted = false;

    if (_voiceEnabled && _speaker.isSupported) {
      setState(() => _speaking = true);
      speechStarted = await _speaker.speak(
        narration,
        isFr: widget.isFr,
        rate: _speed,
        onComplete: () {
          if (!mounted || session != _playSession) return;
          setState(() => _speaking = false);
          if (autoAdvance && _playing) {
            // Brief natural pause before next scene so student sees transition.
            _sceneTimer?.cancel();
            _sceneTimer = Timer(const Duration(milliseconds: 650), () {
              _advanceAfterScene(session);
            });
          }
        },
      );
      if (!mounted || session != _playSession) return;
      if (!speechStarted) {
        setState(() => _speaking = false);
      }
    } else {
      setState(() => _speaking = false);
    }

    if (autoAdvance && _playing) {
      // Generous fallback timeout in case browser speech doesn't emit 'end' or is muted.
      final fallbackMs = speechStarted
          ? ((narration.length * 80 + 2500) / _speed).round().clamp(4500, 14000)
          : (4200 / _speed).round();
      _sceneTimer?.cancel();
      _sceneTimer = Timer(Duration(milliseconds: fallbackMs), () {
        if (!mounted || session != _playSession) return;
        setState(() => _speaking = false);
        _advanceAfterScene(session);
      });
    }
  }

  void _togglePlay() {
    if (widget.simulation.steps.isEmpty) return;
    if (_playing) {
      _stopPlayback();
      return;
    }
    setState(() => _playing = true);
    _playScene(_sceneIndex, autoAdvance: true);
  }

  void _selectScene(int idx) {
    final total = widget.simulation.steps.length;
    if (total == 0) return;
    final safeIdx = idx.clamp(0, total - 1);
    setState(() {
      _sceneIndex = safeIdx;
      _highlightNorm = null;
      _inspectedInfo = null;
    });
    if (_playing || _voiceEnabled) {
      _playScene(safeIdx, autoAdvance: _playing);
    } else {
      _stopPlayback();
    }
  }

  String _sliderLabel(SimulationScene scene, SimulationStep step, String simTitle) {
    final env = scene.environment.toLowerCase();
    final txt = '$simTitle ${step.title} ${step.action}'.toLowerCase();
    if (_VirtualSimulationPainter._plantWordRe.hasMatch(txt) &&
        (env == 'nature' || env == 'biology' || env == 'dark' || env == 'classroom' || env.isEmpty)) {
      return widget.isFr ? 'Humidité du sol & Soleil' : 'Soil Water & Sunlight';
    }
    if (_VirtualSimulationPainter._waveWordRe.hasMatch(txt) || env == 'sound') {
      return widget.isFr ? 'Fréquence & Amplitude (Hauteur / Volume)' : 'Frequency & Amplitude (Pitch / Volume)';
    }
    if (env == 'circuit') {
      return widget.isFr ? 'Tension (V) & Courant' : 'Battery Voltage (1V – 12V)';
    }
    if (env == 'chemistry' || env == 'lab') {
      return widget.isFr ? 'Température / Réaction' : 'Heat & Reaction Rate';
    }
    if (env == 'math') {
      return widget.isFr ? 'Facteur / Pente' : 'Equation Factor / Slope';
    }
    if (env == 'geography') {
      return widget.isFr ? 'Chaleur solaire & Pluie' : 'Solar Heat & Rainfall';
    }
    return widget.isFr ? 'Intensité / Vitesse' : 'Simulation Activity';
  }

  String _liveConditionSummary(SimulationScene scene, SimulationStep step, String simTitle) {
    if (_inspectedInfo != null && _inspectedInfo!.isNotEmpty) {
      return _inspectedInfo!;
    }
    final pct = (_simIntensity * 100).round();
    final env = scene.environment.toLowerCase();
    final txt = '$simTitle ${step.title} ${step.action}'.toLowerCase();
    if (_VirtualSimulationPainter._plantWordRe.hasMatch(txt) &&
        (env == 'nature' || env == 'biology' || env == 'dark' || env == 'classroom' || env.isEmpty)) {
      if (_simIntensity < 0.35) {
        return widget.isFr
            ? 'Sol sec ($pct%) : faible turgescence, la tige s’incline et la sève monte lentement.'
            : 'Dry soil ($pct%): low turgor pressure causes slight wilting and slow xylem flow.';
      }
      return widget.isFr
          ? 'Bien hydraté ($pct%) : forte pression de turgescence, la plante reste droite et l’eau monte vite.'
          : 'Well hydrated ($pct%): strong turgor keeps the plant upright with fast xylem water flow.';
    }
    if (env == 'math') {
      final isBalance = txt.contains('scale') ||
          txt.contains('balance') ||
          txt.contains('equation') ||
          txt.contains('solve');
      if (isBalance) {
        if ((_simIntensity - 0.5).abs() <= 0.12) {
          return widget.isFr
              ? 'Équilibre atteint ($pct%) : le côté gauche égale le côté droit (=).'
              : 'Balanced ($pct%): Left side equals Right side — both sides stay equal when you apply the same operation!';
        }
        return _simIntensity < 0.5
            ? (widget.isFr
                ? 'Côté gauche plus léger ($pct%) : ajoutez ou ajustez x pour rétablir l’équilibre.'
                : 'Left side lighter ($pct%): increase x or restore the same value on both sides to balance.')
            : (widget.isFr
                ? 'Côté gauche plus lourd ($pct%) : retirez ou divisez des deux côtés pour équilibrer.'
                : 'Left side heavier ($pct%): subtract or divide both sides equally to restore balance.');
      }
      return widget.isFr
          ? 'Facteur/Pente à $pct% : observez comment l’inclinaison et la sortie f(x) changent en direct.'
          : 'Factor / Slope at $pct%: watch how changing the input shifts the output f(x) step by step.';
    }
    if (env == 'chemistry' || env == 'lab') {
      return _simIntensity < 0.4
          ? (widget.isFr
              ? 'Chaleur faible ($pct%) : les particules vibrent lentement et les liaisons restent stables.'
              : 'Low heat ($pct%): particles vibrate slowly and chemical bonds stay intact.')
          : (widget.isFr
              ? 'Chaleur élevée ($pct%) : les particules accélèrent, les collisions augmentent et les liaisons se rompent.'
              : 'High heat ($pct%): particles move faster, collisions increase, and bonds break/react.');
    }
    if (env == 'circuit') {
      final volts = (1 + _simIntensity * 11).toStringAsFixed(1);
      return widget.isFr
          ? 'Tension = ${volts}V : plus de tension pousse plus d’électrons et éclaire davantage la lampe.'
          : 'Voltage = ${volts}V: higher voltage pushes more electrons through the circuit, brightening the bulb.';
    }
    if (env == 'geography') {
      return widget.isFr
          ? 'Chaleur solaire ($pct%) : active l’évaporation, la formation des nuages et la pluie sur le relief.'
          : 'Solar heat ($pct%): drives evaporation from water, cloud condensation, and rainfall over land.';
    }
    return widget.isFr
        ? 'Activité ($pct%) : ${step.outcome.isNotEmpty ? step.outcome : "touchez un élément ci-dessus pour l’inspecter."}'
        : 'Activity ($pct%): ${step.outcome.isNotEmpty ? step.outcome : "tap any part of the scene above to inspect it."}';
  }

  void _handleCanvasTap(
    Offset localPos,
    Size boxSize,
    SimulationScene scene,
    SimulationStep step,
    String simTitle,
  ) {
    if (boxSize.width <= 0 || boxSize.height <= 0) return;
    final nx = (localPos.dx / boxSize.width).clamp(0.05, 0.95);
    final ny = (localPos.dy / boxSize.height).clamp(0.05, 0.95);

    String info;
    final txt = '$simTitle ${step.title} ${step.action}'.toLowerCase();
    if (scene.environment.toLowerCase() == 'nature' ||
        txt.contains('plant') ||
        txt.contains('xylem') ||
        txt.contains('soil')) {
      if (ny > 0.70) {
        info = widget.isFr
            ? 'Racines & Sol : l’eau entre dans les poils absorbants par osmose.'
            : 'Roots & Soil: water enters root hairs from moist soil by osmosis.';
      } else if (nx < 0.25 && ny < 0.35) {
        info = widget.isFr
            ? 'Soleil : fournit l’énergie lumineuse pour la photosynthèse et la transpiration.'
            : 'Sunlight: supplies energy driving leaf transpiration pull and food making.';
      } else if (ny < 0.42) {
        info = widget.isFr
            ? 'Feuilles : utilisent l’eau et le CO2 tout en libérant la vapeur par les stomates.'
            : 'Leaves: use water + CO2 with sunlight and release water vapour upward.';
      } else {
        info = widget.isFr
            ? 'Tige & Xylème : les vaisseaux du xylème transportent l’eau vers le haut et maintiennent la turgescence.'
            : 'Stem & Xylem: blue xylem tubes carry water upward while turgor pressure keeps the stem upright.';
      }
    } else if (scene.objects.isNotEmpty) {
      SceneObject nearest = scene.objects.first;
      var bestDist = double.infinity;
      for (final o in scene.objects) {
        final d = (o.x - nx) * (o.x - nx) + (o.y - ny) * (o.y - ny);
        if (d < bestDist) {
          bestDist = d;
          nearest = o;
        }
      }
      info = '${nearest.label.isNotEmpty ? nearest.label : nearest.sprite}: ${step.action}';
    } else {
      info = step.action;
    }

    setState(() {
      _highlightNorm = Offset(nx, ny);
      _inspectedInfo = info;
    });
  }

  Future<void> _toggleVoice() async {
    final next = !_voiceEnabled;
    setState(() => _voiceEnabled = next);
    if (!next) {
      await _speaker.stop();
      if (mounted) setState(() => _speaking = false);
      if (_playing) {
        _playScene(_sceneIndex, autoAdvance: true);
      }
    } else {
      _playScene(_sceneIndex, autoAdvance: _playing);
    }
  }

  void _toggleSpeed() {
    setState(() {
      _speed = _speed == 1.0 ? 1.5 : 1.0;
    });
    if (_playing || _speaking) {
      _playScene(_sceneIndex, autoAdvance: _playing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sim = widget.simulation;
    if (sim.steps.isEmpty) return const SizedBox.shrink();
    final safeIdx = _sceneIndex.clamp(0, sim.steps.length - 1);
    final step = sim.steps[safeIdx];
    final scene = step.scene ?? _inferSceneForStep(step, sim.title);

    return Card(
      color: const Color(0xFFFAFAF9),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _kAiPurple.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kAiPurple.withAlpha(28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.smart_display_rounded,
                    color: _kAiPurple,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isFr
                            ? 'VIDÉO ANIMÉE & PARLANTE — KIVORA IA'
                            : 'NARRATED AI ANIMATED SIMULATION',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                          color: _kAiPurple,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sim.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _kDeepNavy,
                        ),
                      ),
                      if (sim.hobbyConnection.isNotEmpty)
                        Text(
                          widget.isFr
                              ? 'Adapté à vos goûts : ${sim.hobbyConnection}'
                              : 'Tailored to your interest: ${sim.hobbyConnection}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kAiPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _toggleVoice,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _voiceEnabled
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _voiceEnabled
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _voiceEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          size: 16,
                          color: _voiceEnabled
                              ? const Color(0xFF15803D)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _speaking
                              ? (widget.isFr ? 'Parle...' : 'Speaking')
                              : (_voiceEnabled
                                  ? (widget.isFr ? 'Voix' : 'Voice')
                                  : (widget.isFr ? 'Muet' : 'Muted')),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _voiceEnabled
                                ? const Color(0xFF15803D)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _toggleSpeed,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_speed == 1.0 ? "1" : "1.5"}x',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: _kAiPurple,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (sim.scenario.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                sim.scenario,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Visual Animated Canvas Stage
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Column(
                  key: ValueKey<int>(safeIdx),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _kAiPurple,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.isFr
                                ? 'Scène ${safeIdx + 1}/${sim.steps.length}'
                                : 'Scene ${safeIdx + 1}/${sim.steps.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step.title,
                            style: const TextStyle(
                              color: Color(0xFFE2E8F0),
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (_speaking)
                          const Icon(
                            Icons.graphic_eq_rounded,
                            color: Color(0xFF34D399),
                            size: 18,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 280,
                        child: LayoutBuilder(
                          builder: (_, constraints) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) => _handleCanvasTap(
                              details.localPosition,
                              constraints.biggest,
                              scene,
                              step,
                              sim.title,
                            ),
                            child: AnimatedBuilder(
                              animation: _pulseCtrl,
                              builder: (_, _) => CustomPaint(
                                painter: _VirtualSimulationPainter(
                                  scene: scene,
                                  step: step,
                                  simTitle: sim.title,
                                  t: _pulseCtrl.value,
                                  intensity: _simIntensity,
                                  highlightNorm: _highlightNorm,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withAlpha(210),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _kAiPurple.withAlpha(110),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.tune_rounded,
                                size: 15,
                                color: Color(0xFFA78BFA),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _sliderLabel(scene, step, sim.title),
                                  style: const TextStyle(
                                    color: Color(0xFFE2E8F0),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '${(_simIntensity * 100).round()}%',
                                style: const TextStyle(
                                  color: Color(0xFF34D399),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              value: _simIntensity,
                              min: 0.1,
                              max: 1.0,
                              activeColor: const Color(0xFF34D399),
                              inactiveColor: Colors.white24,
                              onChanged: (v) =>
                                  setState(() => _simIntensity = v),
                            ),
                          ),
                          Text(
                            _liveConditionSummary(scene, step, sim.title),
                            style: const TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(80),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        step.action,
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontSize: 13,
                          height: 1.42,
                        ),
                      ),
                    ),
                    if (step.outcome.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: Color(0xFF34D399),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              step.outcome,
                              style: const TextStyle(
                                color: Color(0xFF6EE7B7),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Progress Timeline Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: (safeIdx + 1) / sim.steps.length,
                backgroundColor: const Color(0xFFE2E8F0),
                color: _kAiPurple,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: List.generate(sim.steps.length, (idx) {
                final active = idx == safeIdx;
                return ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  selected: active,
                  label: Text('${idx + 1}'),
                  onSelected: (_) => _selectScene(idx),
                );
              }),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.outlined(
                  onPressed:
                      safeIdx > 0 ? () => _selectScene(safeIdx - 1) : null,
                  tooltip: widget.isFr ? 'Précédent' : 'Previous',
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kAiPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: _togglePlay,
                    icon: Icon(
                      _playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _playing
                          ? (widget.isFr ? 'Pause' : 'Pause')
                          : (widget.isFr ? 'Lire Vidéo IA' : 'Play AI Video'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: safeIdx < sim.steps.length - 1
                      ? () => _selectScene(safeIdx + 1)
                      : () {
                          setState(() {
                            _sceneIndex = 0;
                            _playing = true;
                          });
                          _playScene(0, autoAdvance: true);
                        },
                  tooltip: safeIdx < sim.steps.length - 1
                      ? (widget.isFr ? 'Suivant' : 'Next')
                      : (widget.isFr ? 'Rejouer' : 'Replay'),
                  icon: Icon(
                    safeIdx < sim.steps.length - 1
                        ? Icons.chevron_right_rounded
                        : Icons.replay_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
            if (sim.keyTakeaway.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Takeaway: ${sim.keyTakeaway}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _kDeepNavy,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _BlockType { h1, h2, h3, divider, callout, bullet, table, paragraph }

class _NoteBlock {
  final _BlockType type;
  final String text;
  final String marker;
  final String calloutLabel;
  final List<List<String>> tableRows;

  _NoteBlock({
    required this.type,
    this.text = '',
    this.marker = '',
    this.calloutLabel = '',
    this.tableRows = const [],
  });
}

String _stripOuterBold(String s) {
  var t = s.trim();
  if (t.startsWith('**') && t.endsWith('**') && t.length > 4) {
    t = t.substring(2, t.length - 2).trim();
  }
  return t.replaceAll('**', '');
}

String _cleanMathNotation(String raw, [String? studentName, bool isFr = false]) {
  var s = raw;
  final richIdx = s.indexOf('<!--KIVORA_RICH_V1:');
  if (richIdx != -1) {
    s = s.substring(0, richIdx).trimRight();
  }
  // Strip any leaked raw JSON simulation or schema fragments cleanly
  for (final marker in const [
    '"scale":',
    '"sprite":',
    '"motions":',
    '"visual_model":',
    '"step_number":',
    '"environment":',
    '"diagram_type":',
    '===SIMULATION_JSON===',
  ]) {
    final idx = s.indexOf(marker);
    if (idx != -1) {
      s = s.substring(0, idx).trimRight();
      if (s.endsWith('{') || s.endsWith(',') || s.endsWith('"') || s.endsWith('[')) {
        s = s.substring(0, s.length - 1).trimRight();
      }
    }
  }

  // Clean up any repeated name or greeting stutters like "!Yanne !Yanne !" or multiple "Bonjour ..."
  s = s.replaceAll(RegExp(r'(?:!\s*[A-Za-zÀ-ÿ]+\s*)+!', caseSensitive: false), '!');
  s = s.replaceAll(RegExp(r'((?:Bonjour|Good morning|Hello)[^!\n]+!)\s*(?:Bonjour|Good morning|Hello)[^!\n]+!', caseSensitive: false), r'$1');

  // Personalize greeting if studentName is supplied
  final name = (studentName ?? '').trim();
  if (name.isNotEmpty && name.toLowerCase() != 'student') {
    final firstName = name.split(RegExp(r'\s+')).first;
    final capName = firstName[0].toUpperCase() + firstName.substring(1);
    final target = isFr ? 'Bonjour $capName !' : 'Good morning, $capName!';
    // Only replace explicitly generic classroom targets, never lone "Bonjour"
    s = s.replaceAll(
      RegExp(r'\b(Good morning|Welcome|Hello),?\s+(?:class|everyone|students)\s*!?', caseSensitive: false),
      target,
    );
    s = s.replaceAll(
      RegExp(r'\b(Bonjour|Bienvenue)\s+(?:la classe|à tous|chers élèves)\s*!?', caseSensitive: false),
      target,
    );
  }
  // Convert common LaTeX commands before stripping $ delimiters.
  s = s.replaceAllMapped(
    RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}'),
    (m) => '(${m.group(1)} / ${m.group(2)})',
  );
  s = s.replaceAllMapped(
    RegExp(r'\\sqrt\{([^{}]+)\}'),
    (m) => '√(${m.group(1)})',
  );
  const replacements = {
    r'\times': '×',
    r'\cdot': '·',
    r'\div': '÷',
    r'\pm': '±',
    r'\leq': '≤',
    r'\le': '≤',
    r'\geq': '≥',
    r'\ge': '≥',
    r'\neq': '≠',
    r'\ne': '≠',
    r'\approx': '≈',
    r'\pi': 'π',
    r'\theta': 'θ',
    r'\alpha': 'α',
    r'\beta': 'β',
    r'\Rightarrow': '⇒',
    r'\rightarrow': '→',
    r'\to': '→',
    r'\left(': '(',
    r'\right)': ')',
    r'\left[': '[',
    r'\right]': ']',
  };
  replacements.forEach((k, v) {
    s = s.replaceAll(k, v);
  });
  // Convert simple exponents (^2, ^3, ^{2}, etc.) to clean Unicode superscripts.
  const supMap = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    'n': 'ⁿ',
  };
  s = s.replaceAllMapped(RegExp(r'\^\{([0-9n])\}|\^([0-9n])'), (m) {
    final key = m.group(1) ?? m.group(2) ?? '';
    return supMap[key] ?? '^$key';
  });
  // Remove LaTeX inline/display $...$ / $$...$$ delimiters cleanly.
  s = s.replaceAll(r'$$', '');
  s = s.replaceAllMapped(
    RegExp(r'\$([^$\n]{1,160})\$'),
    (m) => m.group(1) ?? '',
  );
  s = s.replaceAll(r'$', '');
  // Clean markdown checkboxes into neat symbols.
  s = s.replaceAll('[ ] ', '☐ ');
  s = s.replaceAll('[x] ', '☑ ');
  s = s.replaceAll('[X] ', '☑ ');
  return s;
}

List<_NoteBlock> _parseBlocks(String raw, [String? studentName, bool isFr = false]) {
  final lines = _cleanMathNotation(raw, studentName, isFr).replaceAll('\r\n', '\n').split('\n');
  final blocks = <_NoteBlock>[];
  var i = 0;

  bool isTableRow(String line) {
    final t = line.trim();
    return t.startsWith('|') && t.endsWith('|') && t.split('|').length >= 3;
  }

  bool isSeparatorRow(String line) {
    final cells = line
        .trim()
        .split('|')
        .where((c) => c.trim().isNotEmpty)
        .toList();
    return cells.isNotEmpty &&
        cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c.trim()));
  }

  final calloutRegex = RegExp(
    r'^(?:\*\*)?(Teacher Tip|Exam Watch-Out|Exam Mistake|Watch Out|Key Formula|Core Rule|Rule|Remember|Comparison Note|Astuce du prof|Attention|À retenir|Formule cl[ée])\s*:?(?:\*\*)?\s*(.*)$',
    caseSensitive: false,
  );
  final bulletRegex = RegExp(r'^[-*•]\s+(.*)$');
  final numberedRegex = RegExp(r'^(\d+\.)\s+(.*)$');

  while (i < lines.length) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      i++;
      continue;
    }

    if (RegExp(r'^[-*_]{3,}$').hasMatch(line)) {
      blocks.add(_NoteBlock(type: _BlockType.divider));
      i++;
      continue;
    }

    if (line.startsWith('# ')) {
      blocks.add(_NoteBlock(type: _BlockType.h1, text: line.substring(2).trim()));
      i++;
      continue;
    }
    if (line.startsWith('## ')) {
      blocks.add(_NoteBlock(type: _BlockType.h2, text: line.substring(3).trim()));
      i++;
      continue;
    }
    if (line.startsWith('### ') || line.startsWith('#### ')) {
      final clean = line.replaceFirst(RegExp(r'^#{3,4}\s*'), '').trim();
      blocks.add(_NoteBlock(type: _BlockType.h3, text: clean));
      i++;
      continue;
    }

    // Markdown table block
    if (isTableRow(line)) {
      final tableRows = <List<String>>[];
      while (i < lines.length && isTableRow(lines[i])) {
        final current = lines[i].trim();
        if (!isSeparatorRow(current)) {
          final cells = current
              .substring(1, current.length - 1)
              .split('|')
              .map((c) => c.trim())
              .toList();
          if (cells.isNotEmpty) tableRows.add(cells);
        }
        i++;
      }
      if (tableRows.isNotEmpty) {
        blocks.add(_NoteBlock(type: _BlockType.table, tableRows: tableRows));
      }
      continue;
    }

    final calloutMatch = calloutRegex.firstMatch(line);
    if (calloutMatch != null) {
      final label = '${calloutMatch.group(1)!.trim()}:';
      final body = calloutMatch.group(2)!.trim();
      blocks.add(
        _NoteBlock(
          type: _BlockType.callout,
          calloutLabel: label,
          text: body,
        ),
      );
      i++;
      continue;
    }

    final bulletMatch = bulletRegex.firstMatch(line);
    if (bulletMatch != null) {
      blocks.add(
        _NoteBlock(type: _BlockType.bullet, text: bulletMatch.group(1)!.trim()),
      );
      i++;
      continue;
    }

    final numMatch = numberedRegex.firstMatch(line);
    if (numMatch != null) {
      blocks.add(
        _NoteBlock(
          type: _BlockType.bullet,
          marker: numMatch.group(1)!,
          text: numMatch.group(2)!.trim(),
        ),
      );
      i++;
      continue;
    }

    // Combine contiguous plain lines into one clean paragraph.
    final paraLines = <String>[line];
    i++;
    while (i < lines.length) {
      final next = lines[i].trim();
      if (next.isEmpty ||
          next.startsWith('#') ||
          RegExp(r'^[-*_]{3,}$').hasMatch(next) ||
          isTableRow(next) ||
          calloutRegex.hasMatch(next) ||
          bulletRegex.hasMatch(next) ||
          numberedRegex.hasMatch(next)) {
        break;
      }
      paraLines.add(next);
      i++;
    }
    blocks.add(_NoteBlock(type: _BlockType.paragraph, text: paraLines.join(' ')));
  }

  return blocks;
}

List<InlineSpan> _parseInlineSpans(String input, TextStyle baseStyle) {
  final spans = <InlineSpan>[];
  final tokenRegex = RegExp(
    r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`|\[Source\s+\d+\])',
  );
  var cursor = 0;

  for (final match in tokenRegex.allMatches(input)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: input.substring(cursor, match.start)));
    }
    final tok = match.group(0)!;
    if (tok.startsWith('**') && tok.endsWith('**') && tok.length > 4) {
      spans.add(
        TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w800,
            color: _kDeepNavy,
          ),
        ),
      );
    } else if (tok.startsWith('*') && tok.endsWith('*') && tok.length > 2) {
      spans.add(
        TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    } else if (tok.startsWith('`') && tok.endsWith('`') && tok.length > 2) {
      spans.add(
        TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            backgroundColor: const Color(0xFFEFF6FF),
            color: _kPrimaryBlue,
          ),
        ),
      );
    } else {
      // [Source N] citation highlight
      spans.add(
        TextSpan(
          text: ' $tok ',
          style: baseStyle.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: _kPrimaryBlue,
            backgroundColor: const Color(0xFFEFF6FF),
          ),
        ),
      );
    }
    cursor = match.end;
  }

  if (cursor < input.length) {
    spans.add(TextSpan(text: input.substring(cursor)));
  }
  if (spans.isEmpty) {
    spans.add(TextSpan(text: input));
  }
  return spans;
}

SimulationScene _inferSceneForStep(SimulationStep step, String simTitle) {
  final text =
      '$simTitle ${step.title} ${step.action} ${step.visualModel} ${step.outcome}'
          .toLowerCase();

  if (text.contains('xylem') ||
      text.contains('root') ||
      text.contains('leaf') ||
      text.contains('water') ||
      text.contains('transpir') ||
      text.contains('photosynth') ||
      text.contains('plant') ||
      text.contains('chloroplast')) {
    return SimulationScene(
      environment: 'nature',
      objects: [
        SceneObject(sprite: 'sun', label: 'Sunlight', x: 0.16, y: 0.22, color: 'amber'),
        SceneObject(sprite: 'root', label: 'Roots / Soil', x: 0.26, y: 0.80, color: 'amber'),
        SceneObject(sprite: 'stem', label: 'Xylem Vessel', x: 0.50, y: 0.55, color: 'teal'),
        SceneObject(sprite: 'leaf', label: 'Leaf Cells', x: 0.78, y: 0.32, color: 'green'),
      ],
      motions: [
        SceneMotion(fromX: 0.28, fromY: 0.78, toX: 0.50, toY: 0.55, particle: 'drop', color: 'cyan', label: 'H2O'),
        SceneMotion(fromX: 0.50, fromY: 0.55, toX: 0.74, toY: 0.34, particle: 'drop', color: 'cyan', label: 'Sap'),
        SceneMotion(fromX: 0.22, fromY: 0.24, toX: 0.72, toY: 0.30, particle: 'photon', color: 'amber', label: 'Energy'),
      ],
    );
  }

  if (text.contains('cell') ||
      text.contains('nucleus') ||
      text.contains('mitosis') ||
      text.contains('metabolism') ||
      text.contains('organ') ||
      text.contains('osmosis') ||
      text.contains('diffus')) {
    return SimulationScene(
      environment: 'biology',
      objects: [
        SceneObject(sprite: 'drop', label: 'Nutrients', x: 0.18, y: 0.50, color: 'cyan'),
        SceneObject(sprite: 'cell', label: 'Living Cell', x: 0.52, y: 0.50, color: 'green', scale: 1.25),
        SceneObject(sprite: 'heart', label: 'ATP / Growth', x: 0.84, y: 0.48, color: 'red'),
      ],
      motions: [
        SceneMotion(fromX: 0.24, fromY: 0.50, toX: 0.46, toY: 0.50, particle: 'drop', color: 'cyan'),
        SceneMotion(fromX: 0.58, fromY: 0.50, toX: 0.80, toY: 0.48, particle: 'spark', color: 'green'),
      ],
    );
  }

  if (text.contains('sole') ||
      text.contains('business') ||
      text.contains('shop') ||
      text.contains('profit') ||
      text.contains('capital') ||
      text.contains('bank') ||
      text.contains('owner') ||
      text.contains('market') ||
      text.contains('liability') ||
      text.contains('trade')) {
    return SimulationScene(
      environment: 'commerce',
      objects: [
        SceneObject(sprite: 'person', label: 'Owner / Buyer', x: 0.18, y: 0.56, color: 'blue'),
        SceneObject(sprite: 'shop', label: 'Enterprise', x: 0.50, y: 0.52, color: 'purple', scale: 1.15),
        SceneObject(sprite: 'coin', label: 'Profit / Cash', x: 0.82, y: 0.54, color: 'amber'),
      ],
      motions: [
        SceneMotion(fromX: 0.24, fromY: 0.56, toX: 0.44, toY: 0.52, particle: 'coin', color: 'amber', label: 'Capital'),
        SceneMotion(fromX: 0.56, fromY: 0.52, toX: 0.78, toY: 0.54, particle: 'coin', color: 'green', label: 'Revenue'),
      ],
    );
  }

  if (text.contains('circuit') ||
      text.contains('current') ||
      text.contains('voltage') ||
      text.contains('battery') ||
      text.contains('bulb') ||
      text.contains('electron')) {
    return SimulationScene(
      environment: 'circuit',
      objects: [
        SceneObject(sprite: 'battery', label: 'Power Cell', x: 0.20, y: 0.55, color: 'red'),
        SceneObject(sprite: 'bulb', label: 'Lamp Load', x: 0.80, y: 0.45, color: 'amber', scale: 1.2),
      ],
      motions: [
        SceneMotion(fromX: 0.26, fromY: 0.48, toX: 0.74, toY: 0.42, particle: 'electron', color: 'cyan', label: 'e-'),
        SceneMotion(fromX: 0.74, fromY: 0.55, toX: 0.26, toY: 0.62, particle: 'electron', color: 'amber'),
      ],
    );
  }

  if (text.contains('sulfur') ||
      text.contains('acid') ||
      text.contains('reaction') ||
      text.contains('beaker') ||
      text.contains('heat') ||
      text.contains('crystal') ||
      text.contains('boil') ||
      text.contains('melt') ||
      text.contains('molecule')) {
    return SimulationScene(
      environment: 'lab',
      objects: [
        SceneObject(sprite: 'flame', label: 'Heat Source', x: 0.34, y: 0.82, color: 'red'),
        SceneObject(sprite: 'beaker', label: 'Reaction Vessel', x: 0.34, y: 0.52, color: 'blue', scale: 1.15),
        SceneObject(sprite: 'crystal', label: 'Product Structure', x: 0.76, y: 0.48, color: 'amber'),
      ],
      motions: [
        SceneMotion(fromX: 0.34, fromY: 0.74, toX: 0.34, toY: 0.46, particle: 'spark', color: 'red'),
        SceneMotion(fromX: 0.42, fromY: 0.50, toX: 0.70, toY: 0.48, particle: 'bubble', color: 'amber'),
      ],
    );
  }

  if (text.contains('geog') ||
      text.contains('rain') ||
      text.contains('evapor') ||
      text.contains('condens') ||
      text.contains('mountain') ||
      text.contains('river') ||
      text.contains('volcan') ||
      text.contains('climate') ||
      text.contains('tecton')) {
    return SimulationScene(
      environment: 'geography',
      objects: [
        SceneObject(sprite: 'sun', label: 'Solar Heat', x: 0.16, y: 0.22, color: 'amber'),
        SceneObject(sprite: 'cloud', label: 'Clouds & Rain', x: 0.52, y: 0.24, color: 'blue'),
        SceneObject(sprite: 'mountain', label: 'Land / River', x: 0.80, y: 0.60, color: 'green'),
      ],
      motions: [
        SceneMotion(fromX: 0.22, fromY: 0.65, toX: 0.48, toY: 0.28, particle: 'drop', color: 'cyan', label: 'Vapour'),
        SceneMotion(fromX: 0.56, fromY: 0.28, toX: 0.76, toY: 0.55, particle: 'drop', color: 'cyan', label: 'Rain'),
      ],
    );
  }

  if (text.contains('math') ||
      text.contains('equat') ||
      text.contains('algebr') ||
      text.contains('geomet') ||
      text.contains('trigon') ||
      text.contains('parabol') ||
      text.contains('quadratic') ||
      text.contains('function') ||
      text.contains('angle') ||
      text.contains('calcul')) {
    return SimulationScene(
      environment: 'math',
      objects: [
        SceneObject(sprite: 'axes', label: 'Inputs (x)', x: 0.20, y: 0.50, color: 'blue'),
        SceneObject(sprite: 'triangle', label: 'Rule / Relation', x: 0.52, y: 0.48, color: 'purple'),
        SceneObject(sprite: 'chart', label: 'Solution f(x)', x: 0.82, y: 0.50, color: 'green'),
      ],
      motions: [
        SceneMotion(fromX: 0.25, fromY: 0.50, toX: 0.48, toY: 0.48, particle: 'spark', color: 'cyan', label: 'Map'),
        SceneMotion(fromX: 0.56, fromY: 0.48, toX: 0.78, toY: 0.50, particle: 'photon', color: 'green', label: 'Solve'),
      ],
    );
  }

  if (text.contains('comput') ||
      text.contains('algorithm') ||
      text.contains('binary') ||
      text.contains('cpu') ||
      text.contains('database') ||
      text.contains('network') ||
      text.contains('program') ||
      text.contains('ict')) {
    return SimulationScene(
      environment: 'cs',
      objects: [
        SceneObject(sprite: 'document', label: 'Input Data', x: 0.18, y: 0.50, color: 'blue'),
        SceneObject(sprite: 'cpu', label: 'CPU / Logic', x: 0.50, y: 0.48, color: 'purple'),
        SceneObject(sprite: 'database', label: 'Storage', x: 0.82, y: 0.50, color: 'teal'),
      ],
      motions: [
        SceneMotion(fromX: 0.24, fromY: 0.50, toX: 0.44, toY: 0.48, particle: 'electron', color: 'cyan', label: '0101'),
        SceneMotion(fromX: 0.56, fromY: 0.48, toX: 0.76, toY: 0.50, particle: 'spark', color: 'green', label: 'Save'),
      ],
    );
  }

  if (text.contains('history') ||
      text.contains('citizen') ||
      text.contains('civic') ||
      text.contains('essay') ||
      text.contains('literature') ||
      text.contains('grammar') ||
      text.contains('constitution') ||
      text.contains('law') ||
      text.contains('rights')) {
    return SimulationScene(
      environment: 'humanities',
      objects: [
        SceneObject(sprite: 'book', label: 'Core Source', x: 0.20, y: 0.50, color: 'amber'),
        SceneObject(sprite: 'scale', label: 'Key Principle', x: 0.52, y: 0.48, color: 'purple'),
        SceneObject(sprite: 'globe', label: 'Society Impact', x: 0.82, y: 0.50, color: 'teal'),
      ],
      motions: [
        SceneMotion(fromX: 0.26, fromY: 0.50, toX: 0.46, toY: 0.48, particle: 'photon', color: 'amber', label: 'Facts'),
        SceneMotion(fromX: 0.58, fromY: 0.48, toX: 0.76, toY: 0.50, particle: 'spark', color: 'green', label: 'Impact'),
      ],
    );
  }

  return SimulationScene(
    environment: 'physics',
    objects: [
      SceneObject(sprite: 'atom', label: 'Core Principle', x: 0.22, y: 0.52, color: 'blue'),
      SceneObject(sprite: 'wave', label: 'Interaction', x: 0.52, y: 0.52, color: 'purple'),
      SceneObject(sprite: 'chart', label: 'Result', x: 0.82, y: 0.50, color: 'green'),
    ],
    motions: [
      SceneMotion(fromX: 0.28, fromY: 0.52, toX: 0.46, toY: 0.52, particle: 'photon', color: 'cyan'),
      SceneMotion(fromX: 0.58, fromY: 0.52, toX: 0.76, toY: 0.50, particle: 'spark', color: 'green'),
    ],
  );
}

class _VirtualSimulationPainter extends CustomPainter {
  final SimulationScene scene;
  final SimulationStep step;
  final String simTitle;
  final double t;
  final double intensity;
  final Offset? highlightNorm;

  _VirtualSimulationPainter({
    required this.scene,
    required this.step,
    required this.simTitle,
    required this.t,
    this.intensity = 0.75,
    this.highlightNorm,
  });

  final List<Rect> _placedLabels = <Rect>[];

  Color _palette(String name) {
    switch (name.toLowerCase()) {
      case 'green':
        return const Color(0xFF22C55E);
      case 'amber':
      case 'yellow':
      case 'gold':
        return const Color(0xFFF59E0B);
      case 'red':
      case 'orange':
        return const Color(0xFFEF4444);
      case 'purple':
        return const Color(0xFFA855F7);
      case 'teal':
      case 'cyan':
        return const Color(0xFF06B6D4);
      case 'slate':
        return const Color(0xFF94A3B8);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  static final RegExp _waveWordRe = RegExp(
    r'\b(wave|waves|sound|sonore|sonores|vibration|vibrations|amplitude|frequency|fréquence|pitch|wavelength|longueur|compression|rarefaction|raréfaction|acoustique|acoustic|tuning|diapason|loudness|hertz|decibel)\b',
    caseSensitive: false,
  );

  static final RegExp _plantWordRe = RegExp(
    r'\b(plant|plants|soil|xylem|phloem|leaf|leaves|transpiration|turgor|chloroplast|photosynthesis|stomata)\b',
  );

  bool _isPlantTopic() {
    final env = scene.environment.toLowerCase();
    const nonPlantEnvs = {
      'chemistry',
      'lab',
      'circuit',
      'math',
      'geography',
      'space',
      'history',
      'economy',
      'city',
      'humanities',
      'commerce',
      'cs',
      'physics',
      'civics',
      'citizenship',
    };
    if (nonPlantEnvs.contains(env)) return false;

    final joined = [
      simTitle,
      step.title,
      step.action,
      step.visualModel,
      step.outcome,
      ...scene.objects.map((o) => '${o.sprite} ${o.label}'),
    ].join(' ').toLowerCase();

    // Never paint plant biology for social sciences, governance, civic topics, or non-botany subjects
    const nonPlantWords = [
      'nation',
      'citizen',
      'civic',
      'governance',
      'constitution',
      'cameroon',
      'assembly',
      'symbol',
      'president',
      'democracy',
      'court',
      'justice',
      'history',
      'colonial',
      'trade',
      'market',
      'argument',
      'logic',
      'syllogism',
      'gate',
      'algorithm',
    ];
    for (final w in nonPlantWords) {
      if (joined.contains(w)) return false;
    }

    final hasPlantObject = scene.objects.any((o) =>
        o.sprite == 'plant' ||
        o.sprite == 'leaf' ||
        o.sprite == 'root' ||
        o.sprite == 'stem');
    if (!hasPlantObject && env != 'biology') return false;

    return _plantWordRe.hasMatch(joined);
  }

  bool _isGeographyCycleTopic() {
    final env = scene.environment.toLowerCase();
    if (env == 'geography') return true;
    const nonGeoEnvs = {
      'chemistry',
      'lab',
      'circuit',
      'math',
      'nature',
      'space',
      'history',
      'economy',
      'city',
    };
    if (nonGeoEnvs.contains(env)) return false;
    final joined = [
      simTitle,
      step.title,
      step.action,
      step.outcome,
    ].join(' ').toLowerCase();
    return joined.contains('water cycle') ||
        joined.contains('evaporat') ||
        joined.contains('condensat') ||
        joined.contains('precipitat') ||
        (joined.contains('rain') && joined.contains('mountain'));
  }

  List<SceneObject> _arrangeObjects(List<SceneObject> raw) {
    if (raw.isEmpty) return raw;
    // Detect if two or more objects overlap closely on the stage.
    var hasCollision = false;
    for (int i = 0; i < raw.length && !hasCollision; i++) {
      for (int j = i + 1; j < raw.length; j++) {
        if ((raw[i].x - raw[j].x).abs() < 0.22 &&
            (raw[i].y - raw[j].y).abs() < 0.20) {
          hasCollision = true;
          break;
        }
      }
    }

    final n = raw.length.clamp(1, 6);
    final spaced = <SceneObject>[];
    for (int i = 0; i < raw.length; i++) {
      final obj = raw[i];
      double nx = obj.x.clamp(0.15, 0.85);
      double ny = obj.y.clamp(0.20, 0.76);
      if (hasCollision) {
        nx = raw.length == 1
            ? 0.50
            : (0.16 + (0.68 * i / (n - 1))).clamp(0.15, 0.85);
        final sp = obj.sprite.toLowerCase();
        if (sp == 'sun' || sp == 'bulb') {
          ny = 0.22;
        } else if (sp == 'root' || sp == 'flame') {
          ny = 0.68;
        } else {
          ny = (i.isEven ? 0.44 : 0.56);
        }
      }
      spaced.add(
        SceneObject(
          sprite: obj.sprite,
          label: obj.label,
          x: nx,
          y: ny,
          color: obj.color,
          scale: obj.scale,
        ),
      );
    }
    return spaced;
  }

  List<SceneMotion> _arrangeMotions(
    List<SceneMotion> rawMotions,
    List<SceneObject> arrangedObjs,
  ) {
    if (rawMotions.isNotEmpty) {
      var collapsed = false;
      for (final m in rawMotions) {
        if ((m.fromX - m.toX).abs() < 0.12 &&
            (m.fromY - m.toY).abs() < 0.12) {
          collapsed = true;
          break;
        }
      }
      if (!collapsed) return rawMotions;
    }
    if (arrangedObjs.length < 2) return rawMotions;
    final generated = <SceneMotion>[];
    for (int i = 0; i < arrangedObjs.length - 1; i++) {
      final a = arrangedObjs[i];
      final b = arrangedObjs[i + 1];
      final base = i < rawMotions.length ? rawMotions[i] : null;
      generated.add(
        SceneMotion(
          fromX: a.x,
          fromY: a.y,
          toX: b.x,
          toY: b.y,
          particle: base?.particle ?? 'spark',
          color: base?.color ?? 'cyan',
          label: base?.label ?? '',
        ),
      );
    }
    return generated;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _placedLabels.clear();

    if (_isPlantTopic()) {
      _paintFullPlantStage(canvas, size);
      return;
    }
    if (_isWaveSoundTopic()) {
      _paintWaveSoundStage(canvas, size);
      return;
    }
    if (_isGeographyCycleTopic()) {
      _paintGeographyCycleStage(canvas, size);
      return;
    }
    if (_isEquationBalanceTopic()) {
      _paintMathBalanceStage(canvas, size);
      return;
    }

    _paintEnvironment(canvas, size);

    final objs = _arrangeObjects(scene.objects);
    final motions = _arrangeMotions(scene.motions, objs);

    // Draw glowing connector rails & large animated particles beneath objects.
    for (final m in motions) {
      final p0 = Offset(m.fromX * size.width, m.fromY * size.height);
      final p1 = Offset(m.toX * size.width, m.toY * size.height);
      final col = _palette(m.color);
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..color = col.withAlpha(110)
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round,
      );
      _paintMotionParticles(canvas, size, m, p0, p1, col);
    }

    // Draw crystal-clear illustrated scene objects with non-overlapping pills.
    for (final obj in objs) {
      final center = Offset(obj.x * size.width, obj.y * size.height);
      final color = _palette(obj.color);
      final r = 30.0 * obj.scale.clamp(0.85, 1.35);
      canvas.drawCircle(
        center,
        r * (1.05 + 0.35 * intensity),
        Paint()..color = color.withAlpha((24 + 34 * intensity).round()),
      );
      _paintSprite(canvas, obj.sprite, center, r, color);
      if (obj.label.isNotEmpty) {
        _drawLabel(
          canvas,
          size,
          obj.label,
          Offset(center.dx, center.dy + r + 15),
          Colors.white,
          borderColor: color,
        );
      }
    }

    if (highlightNorm != null) {
      final hp = Offset(
        highlightNorm!.dx * size.width,
        highlightNorm!.dy * size.height,
      );
      final pulseR = 22.0 + 7.0 * math.sin(t * 2 * math.pi).abs();
      canvas.drawCircle(
        hp,
        pulseR,
        Paint()
          ..color = const Color(0xFF34D399).withAlpha(180)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
    }
  }

  void _paintFullPlantStage(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final soilY = h * 0.72;
    final stemX = w * 0.48;
    final stepText =
        '${step.title} ${step.action} ${step.outcome}'.toLowerCase();
    final focusRoots = stepText.contains('soil') ||
        stepText.contains('root') ||
        stepText.contains('absorb') ||
        stepText.contains('osmosis');
    final focusTurgor = stepText.contains('turgor') ||
        stepText.contains('pressure') ||
        stepText.contains('rigid') ||
        stepText.contains('upright') ||
        stepText.contains('balance');
    final focusLeaf = stepText.contains('leaf') ||
        stepText.contains('leaves') ||
        stepText.contains('transpir') ||
        stepText.contains('sun') ||
        stepText.contains('photosynth');

    // 1. Bright clear daytime sky + soft horizon glow.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, soilY),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF7DD3FC), Color(0xFFE0F2FE)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, w, soilY)),
    );

    // Subtle fluffy clouds for depth.
    final cloudPaint = Paint()..color = Colors.white.withAlpha(185);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.78, h * 0.14), width: 66, height: 22), cloudPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.83, h * 0.12), width: 42, height: 22), cloudPaint);

    // 2. Radiant animated Sun top-left.
    _paintSprite(
      canvas,
      'sun',
      Offset(w * 0.14, h * 0.18),
      26,
      const Color(0xFFF59E0B),
    );

    // 3. Green grass rim & rich layered soil cross-section.
    canvas.drawRect(
      Rect.fromLTWH(0, soilY - 6, w, 11),
      Paint()..color = const Color(0xFF16A34A),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, soilY + 4, w, h - soilY),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF78350F), Color(0xFF451A03)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, soilY, w, h - soilY)),
    );

    // Blue glowing water reservoirs inside the soil (scale dynamically with Moisture slider).
    final pocketScale = (0.55 + 0.65 * intensity) * (1.0 + 0.08 * math.sin(t * 2 * math.pi));
    final soilPockets = [
      Offset(stemX - 72, soilY + (h - soilY) * 0.45),
      Offset(stemX + 68, soilY + (h - soilY) * 0.52),
      Offset(stemX - 24, soilY + (h - soilY) * 0.72),
    ];
    for (final sp in soilPockets) {
      canvas.drawOval(
        Rect.fromCenter(
          center: sp,
          width: (focusRoots ? 42 : 34) * pocketScale,
          height: 17 * pocketScale,
        ),
        Paint()..color = const Color(0xFF0EA5E9).withAlpha((80 + 95 * intensity).round()),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: sp,
          width: (focusRoots ? 42 : 34) * pocketScale,
          height: 17 * pocketScale,
        ),
        Paint()
          ..color = const Color(0xFFBAE6FD)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    // 4. Strong branching Roots dipping into the wet soil pockets.
    final rootPaint = Paint()
      ..color = focusRoots ? const Color(0xFFFDE68A) : const Color(0xFFD97706)
      ..strokeWidth = focusRoots ? 4.8 : 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final rootOutline = Paint()
      ..color = const Color(0xFF451A03)
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final rootPaths = [
      Path()
        ..moveTo(stemX, soilY)
        ..quadraticBezierTo(stemX - 18, soilY + 26, stemX - 66, soilY + (h - soilY) * 0.48),
      Path()
        ..moveTo(stemX, soilY)
        ..quadraticBezierTo(stemX + 18, soilY + 28, stemX + 64, soilY + (h - soilY) * 0.52),
      Path()
        ..moveTo(stemX, soilY)
        ..quadraticBezierTo(stemX - 6, soilY + 38, stemX - 20, soilY + (h - soilY) * 0.78),
      Path()
        ..moveTo(stemX + 6, soilY + 12)
        ..quadraticBezierTo(stemX + 26, soilY + 44, stemX + 34, soilY + (h - soilY) * 0.74),
    ];
    for (final rp in rootPaths) {
      canvas.drawPath(rp, rootOutline);
      canvas.drawPath(rp, rootPaint);
    }

    // 5. Crisp Tall Plant Stem with Twin Inner Blue Xylem Vessels.
    final stemTopY = h * 0.23;
    final stemWidth = focusTurgor ? 26.0 : 22.0;
    final stemRect = Rect.fromLTRB(
      stemX - stemWidth / 2,
      stemTopY,
      stemX + stemWidth / 2,
      soilY + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(stemRect, const Radius.circular(11)),
      Paint()..color = const Color(0xFF22C55E),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(stemRect, const Radius.circular(11)),
      Paint()
        ..color = const Color(0xFF14532D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );
    // Twin sky-blue Xylem channels inside the stem
    for (final dx in [-4.5, 4.5]) {
      canvas.drawLine(
        Offset(stemX + dx, soilY - 2),
        Offset(stemX + dx, stemTopY + 14),
        Paint()
          ..color = const Color(0xFF0284C7)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Turgor Pressure outward cell-wall arrows inside stem when highlighted!
    if (focusTurgor) {
      final arrowPulse = 4.0 + 3.0 * math.sin(t * 2 * math.pi);
      for (final yFrac in [0.40, 0.56]) {
        final ay = h * yFrac;
        for (final dir in [-1.0, 1.0]) {
          final sx = stemX + dir * 10;
          final ex = stemX + dir * (22 + arrowPulse);
          canvas.drawLine(
            Offset(sx, ay),
            Offset(ex, ay),
            Paint()
              ..color = const Color(0xFF0284C7)
              ..strokeWidth = 3.2
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawCircle(
            Offset(ex, ay),
            4.2,
            Paint()..color = const Color(0xFF38BDF8),
          );
        }
      }
    }

    // 6. Four Lush Detailed Green Leaves attached to the Stem.
    void drawLeafBranch(
      Offset base,
      Offset tip,
      Offset ctrlUp,
      Offset ctrlDown,
    ) {
      final leaf = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(ctrlUp.dx, ctrlUp.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(ctrlDown.dx, ctrlDown.dy, base.dx, base.dy)
        ..close();
      canvas.drawPath(
        leaf,
        Paint()
          ..color = focusLeaf ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
      );
      canvas.drawPath(
        leaf,
        Paint()
          ..color = const Color(0xFF14532D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
      canvas.drawLine(
        base,
        Offset.lerp(base, tip, 0.85)!,
        Paint()
          ..color = const Color(0xFFBBF7D0)
          ..strokeWidth = 2.0,
      );
    }

    drawLeafBranch(
      Offset(stemX - 8, h * 0.47),
      Offset(stemX - 92, h * 0.34),
      Offset(stemX - 48, h * 0.25),
      Offset(stemX - 54, h * 0.50),
    );
    drawLeafBranch(
      Offset(stemX + 8, h * 0.43),
      Offset(stemX + 94, h * 0.30),
      Offset(stemX + 52, h * 0.21),
      Offset(stemX + 56, h * 0.47),
    );
    drawLeafBranch(
      Offset(stemX - 6, h * 0.31),
      Offset(stemX - 74, h * 0.17),
      Offset(stemX - 38, h * 0.11),
      Offset(stemX - 42, h * 0.32),
    );
    drawLeafBranch(
      Offset(stemX + 6, h * 0.28),
      Offset(stemX + 76, h * 0.15),
      Offset(stemX + 42, h * 0.09),
      Offset(stemX + 46, h * 0.30),
    );

    // 7. Continuous Animated Blue Water Drops: Soil -> Roots -> Xylem Stem -> Leaves -> Sky!
    void drawWaterPath(List<Offset> waypoints, int count, double phaseShift) {
      for (int i = 0; i < count; i++) {
        final u = ((t + phaseShift + i / count) % 1.0);
        final segFloat = u * (waypoints.length - 1);
        final segIdx = segFloat.floor().clamp(0, waypoints.length - 2);
        final localT = segFloat - segIdx;
        final pos = Offset.lerp(waypoints[segIdx], waypoints[segIdx + 1], localT)!;
        final dp = Path()
          ..moveTo(pos.dx, pos.dy - 9)
          ..quadraticBezierTo(pos.dx + 7, pos.dy + 2, pos.dx, pos.dy + 8)
          ..quadraticBezierTo(pos.dx - 7, pos.dy + 2, pos.dx, pos.dy - 9);
        canvas.drawPath(dp, Paint()..color = const Color(0xFF0284C7));
        canvas.drawPath(
          dp,
          Paint()
            ..color = const Color(0xFFE0F2FE)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }

    drawWaterPath([
      soilPockets[0],
      Offset(stemX - 20, soilY + 14),
      Offset(stemX - 4, soilY - 6),
      Offset(stemX - 4, h * 0.47),
      Offset(stemX - 58, h * 0.38),
      Offset(stemX - 88, h * 0.22),
    ], 4, 0.0);

    drawWaterPath([
      soilPockets[1],
      Offset(stemX + 20, soilY + 16),
      Offset(stemX + 4, soilY - 6),
      Offset(stemX + 4, h * 0.38),
      Offset(stemX + 56, h * 0.30),
      Offset(stemX + 86, h * 0.14),
    ], 4, 0.35);

    // 8. Clear Non-Overlapping Callout Badges on the Sides with Leader Lines!
    void drawCallout(Offset target, Offset labelPos, String text, Color accent) {
      canvas.drawLine(
        target,
        labelPos,
        Paint()
          ..color = const Color(0xFF0F172A).withAlpha(140)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(target, 3.6, Paint()..color = accent);
      _drawLabel(
        canvas,
        size,
        text,
        labelPos,
        Colors.white,
        borderColor: accent,
      );
    }

    drawCallout(
      Offset(w * 0.14, h * 0.25),
      Offset(w * 0.15, h * 0.33),
      'Sunlight',
      const Color(0xFFF59E0B),
    );
    drawCallout(
      Offset(stemX - 66, h * 0.36),
      Offset(w * 0.17, h * 0.52),
      'Leaves (H2O Vapor)',
      const Color(0xFF16A34A),
    );
    drawCallout(
      soilPockets[0],
      Offset(w * 0.18, h * 0.86),
      'Roots in Moist Soil',
      const Color(0xFF38BDF8),
    );
    drawCallout(
      Offset(stemX + 12, h * 0.50),
      Offset(w * 0.82, h * 0.52),
      focusTurgor ? 'Turgor Pressure' : 'Xylem (Water Up)',
      const Color(0xFF0284C7),
    );
    drawCallout(
      Offset(stemX + 68, h * 0.28),
      Offset(w * 0.82, h * 0.31),
      'Plant Canopy',
      const Color(0xFF22C55E),
    );
  }

  void _paintGeographyCycleStage(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Bright sky gradient
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.72),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF38BDF8), Color(0xFFE0F2FE)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.72)),
    );

    // Ocean basin on the left & green terrain / mountains on the right
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.68, w * 0.56, h * 0.32),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, h * 0.68, w * 0.56, h * 0.32)),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.45, h * 0.68, w * 0.55, h * 0.32),
      Paint()..color = const Color(0xFF15803D),
    );

    // Sun top-left & Rain Clouds top-center-right
    _paintSprite(canvas, 'sun', Offset(w * 0.15, h * 0.20), 26, const Color(0xFFF59E0B));
    _paintSprite(canvas, 'cloud', Offset(w * 0.64, h * 0.22), 34, const Color(0xFFE0F2FE));
    _paintSprite(canvas, 'mountain', Offset(w * 0.78, h * 0.54), 52, const Color(0xFF16A34A));

    // River flowing down from mountain back to sea
    final river = Path()
      ..moveTo(w * 0.73, h * 0.54)
      ..quadraticBezierTo(w * 0.62, h * 0.68, w * 0.45, h * 0.72);
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..strokeCap = StrokeCap.round,
    );

    // Rising evaporation vapour from sea -> cloud, falling rain from cloud -> mountain
    for (int i = 0; i < 4; i++) {
      final p = (t + i / 4.0) % 1.0;
      final evapPos = Offset(w * (0.20 + i * 0.05), h * (0.68 - p * 0.40));
      canvas.drawCircle(evapPos, 5.5, Paint()..color = const Color(0xFFE0F2FE).withAlpha(200));

      final rainPos = Offset(w * (0.58 + i * 0.05), h * (0.30 + p * 0.30));
      canvas.drawLine(
        rainPos,
        Offset(rainPos.dx - 2, rainPos.dy + 9),
        Paint()
          ..color = const Color(0xFF0284C7)
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      );
    }

    _drawLabel(canvas, size, 'Solar Heating', Offset(w * 0.16, h * 0.36), Colors.white, borderColor: const Color(0xFFF59E0B));
    _drawLabel(canvas, size, 'Evaporation', Offset(w * 0.28, h * 0.54), Colors.white, borderColor: const Color(0xFF38BDF8));
    _drawLabel(canvas, size, 'Clouds & Rain', Offset(w * 0.64, h * 0.11), Colors.white, borderColor: const Color(0xFF60A5FA));
    _drawLabel(canvas, size, 'River Runoff', Offset(w * 0.56, h * 0.84), Colors.white, borderColor: const Color(0xFF22C55E));
  }

  void _paintEnvironment(Canvas canvas, Size size) {
    final env = scene.environment.toLowerCase();
    final List<Color> gradColors;
    if (env == 'biology') {
      gradColors = const [Color(0xFF065F46), Color(0xFF0F172A)];
    } else if (env == 'commerce') {
      gradColors = const [Color(0xFF1E1B4B), Color(0xFF3730A3)];
    } else if (env == 'chemistry' || env == 'lab') {
      gradColors = const [Color(0xFF0F172A), Color(0xFF1E3A5F)];
    } else if (env == 'math') {
      gradColors = const [Color(0xFF0F172A), Color(0xFF1E293B)];
    } else if (env == 'cs') {
      gradColors = const [Color(0xFF0B1120), Color(0xFF0F2942)];
    } else if (env == 'humanities') {
      gradColors = const [Color(0xFF1E1B4B), Color(0xFF312E81)];
    } else if (env == 'circuit') {
      gradColors = const [Color(0xFF090D16), Color(0xFF172554)];
    } else {
      gradColors = const [Color(0xFF0F172A), Color(0xFF1E3A8A)];
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: gradColors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );

    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(env == 'math' ? 28 : 18)
      ..strokeWidth = 1;
    for (double x = 28; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 28; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (env == 'math') {
      // Subtle Cartesian cross-hairs in math mode
      final axisPaint = Paint()
        ..color = const Color(0xFF60A5FA).withAlpha(65)
        ..strokeWidth = 1.6;
      canvas.drawLine(Offset(size.width * 0.5, 16), Offset(size.width * 0.5, size.height - 16), axisPaint);
      canvas.drawLine(Offset(20, size.height * 0.5), Offset(size.width - 20, size.height * 0.5), axisPaint);
    } else if (env == 'circuit') {
      // Subtle circuit bus loop
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * 0.18, size.height * 0.25, size.width * 0.64, size.height * 0.50),
          const Radius.circular(18),
        ),
        Paint()
          ..color = const Color(0xFF38BDF8).withAlpha(65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
  }

  void _paintMotionParticles(
    Canvas canvas,
    Size size,
    SceneMotion m,
    Offset p0,
    Offset p1,
    Color col,
  ) {
    for (int idx = 0; idx < 3; idx++) {
      final phase = (t + idx / 3.0) % 1.0;
      final pos = Offset.lerp(p0, p1, phase)!;
      final kind = m.particle.toLowerCase();

      if (kind == 'drop') {
        final path = Path()
          ..moveTo(pos.dx, pos.dy - 9)
          ..quadraticBezierTo(pos.dx + 7, pos.dy + 2, pos.dx, pos.dy + 8)
          ..quadraticBezierTo(pos.dx - 7, pos.dy + 2, pos.dx, pos.dy - 9);
        canvas.drawPath(path, Paint()..color = col);
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withAlpha(190)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      } else if (kind == 'coin') {
        canvas.drawCircle(pos, 7.5, Paint()..color = const Color(0xFFFBBF24));
        canvas.drawCircle(
          pos,
          7.5,
          Paint()
            ..color = const Color(0xFFFEF3C7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      } else if (kind == 'photon' || kind == 'spark') {
        canvas.drawCircle(pos, 8.5, Paint()..color = col.withAlpha(110));
        canvas.drawCircle(pos, 4.2, Paint()..color = Colors.white);
      } else {
        canvas.drawCircle(pos, 6.2, Paint()..color = col);
      }
    }
    if (m.label.isNotEmpty) {
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2 - 14);
      _drawLabel(canvas, size, m.label, mid, Colors.white, borderColor: col);
    }
  }


  bool _isWaveSoundTopic() {
    final env = scene.environment.toLowerCase();
    if (env == 'sound') return true;
    final joined = [
      simTitle,
      step.title,
      step.action,
      step.outcome,
      ...scene.objects.map((o) => '${o.sprite} ${o.label}'),
    ].join(' ').toLowerCase();
    return _waveWordRe.hasMatch(joined);
  }

  void _paintWaveSoundStage(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Sleek oscilloscope / physics lab dark gradient background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(16)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF0B132B), Color(0xFF1C2541), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Subtle technical grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF334155).withAlpha(55)
      ..strokeWidth = 1.0;
    for (double x = 0; x < w; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y < h; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // 2. TOP SECTION: Longitudinal Wave Medium (Vibrating air particles)
    final mediumTop = h * 0.14;
    final mediumBottom = h * 0.48;
    final mediumH = mediumBottom - mediumTop;
    final speakerX = w * 0.12;
    final speakerY = mediumTop + mediumH * 0.50;

    // Speaker Cone oscillation (driven by intensity and time)
    final oscFreq = 2.0 + intensity * 3.5;
    final oscAmp = 8.0 * intensity;
    final coneShift = math.sin(t * 2 * math.pi * oscFreq) * oscAmp;

    // Speaker body & diaphragm
    final speakerBodyPaint = Paint()..color = const Color(0xFF475569);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(speakerX - 16, speakerY), width: 22, height: mediumH * 0.70),
        const Radius.circular(5),
      ),
      speakerBodyPaint,
    );
    // Vibrating cone
    final conePath = Path()
      ..moveTo(speakerX - 6, speakerY - mediumH * 0.32)
      ..lineTo(speakerX + 8 + coneShift, speakerY - mediumH * 0.42)
      ..lineTo(speakerX + 8 + coneShift, speakerY + mediumH * 0.42)
      ..lineTo(speakerX - 6, speakerY + mediumH * 0.32)
      ..close();
    canvas.drawPath(
      conePath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF64748B), Color(0xFF38BDF8)],
        ).createShader(Rect.fromLTWH(speakerX - 6, speakerY - 30, 20, 60)),
    );
    // Sound wave arcs coming from speaker
    final arcPaint = Paint()
      ..color = const Color(0xFF38BDF8).withAlpha((110 + 130 * intensity).clamp(0, 255).round())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (int a = 1; a <= 3; a++) {
      final arcR = 14.0 * a + (coneShift * 0.5);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(speakerX + 10, speakerY), radius: arcR),
        -math.pi / 3,
        2 * math.pi / 3,
        false,
        arcPaint,
      );
    }

    // Air molecules (Longitudinal wave displacement: x = x0 + A*sin(k*x0 - omega*t))
    final startX = speakerX + 32;
    final endX = w * 0.94;
    final length = endX - startX;
    const cols = 22;
    const rows = 5;
    final lambda = length * 0.42;
    final k = 2 * math.pi / lambda;
    final omega = 2 * math.pi * oscFreq;

    for (int c = 0; c < cols; c++) {
      final x0 = startX + (length * c / (cols - 1));
      final phase = k * (x0 - startX) - omega * t;
      final displacement = math.sin(phase) * (15.0 * intensity);
      final px = (x0 + displacement).clamp(startX - 5, endX + 5);

      // Local density measure: compression is when derivative of displacement < 0
      final isCompression = math.cos(phase) < -0.3;
      final particleColor = isCompression
          ? const Color(0xFF38BDF8) // bright blue compression
          : const Color(0xFF94A3B8).withAlpha(170); // spaced rarefaction

      for (int r = 0; r < rows; r++) {
        final py = mediumTop + 14 + (r * (mediumH - 28) / (rows - 1));
        canvas.drawCircle(
          Offset(px, py),
          isCompression ? 3.4 : 2.5,
          Paint()..color = particleColor,
        );
      }
    }

    // Top medium section labels
    _drawLabel(
      canvas,
      size,
      'Source (Vibration)',
      Offset(speakerX, mediumTop - 4),
      Colors.white,
      borderColor: const Color(0xFF38BDF8),
    );
    _drawLabel(
      canvas,
      size,
      'Onde Longitudinale (Compression & Raréfaction)',
      Offset(w * 0.60, mediumTop - 4),
      const Color(0xFFBAE6FD),
      borderColor: const Color(0xFF0284C7),
    );

    // Horizontal energy propagation arrow
    final arrowY = mediumBottom + 4;
    final arrowPaint = Paint()
      ..color = const Color(0xFF34D399)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(startX, arrowY), Offset(endX, arrowY), arrowPaint);
    canvas.drawLine(Offset(endX, arrowY), Offset(endX - 8, arrowY - 4), arrowPaint);
    canvas.drawLine(Offset(endX, arrowY), Offset(endX - 8, arrowY + 4), arrowPaint);
    _drawLabel(
      canvas,
      size,
      'Propagation de l\'énergie →',
      Offset(startX + length * 0.50, arrowY + 11),
      const Color(0xFFD1FAE5),
      borderColor: const Color(0xFF10B981),
    );

    // 3. BOTTOM SECTION: Transverse Pressure Wave (Oscilloscope View)
    final oscCenterY = h * 0.74;
    final oscAmpPx = (24.0 + 16.0 * intensity);

    // Baseline centerline (dotted/dashed)
    final baseLinePaint = Paint()
      ..color = const Color(0xFF64748B).withAlpha(120)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(startX, oscCenterY), Offset(endX, oscCenterY), baseLinePaint);

    // Glowing Neon Oscilloscope Sine Path
    final wavePath = Path();
    var first = true;
    for (double x = startX; x <= endX; x += 3) {
      final phase = k * (x - startX) - omega * t;
      final y = oscCenterY - math.sin(phase) * oscAmpPx;
      if (first) {
        wavePath.moveTo(x, y);
        first = false;
      } else {
        wavePath.lineTo(x, y);
      }
    }

    // Outer glow
    canvas.drawPath(
      wavePath,
      Paint()
        ..color = const Color(0xFF22C55E).withAlpha(70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0
        ..strokeCap = StrokeCap.round,
    );
    // Inner vibrant core
    canvas.drawPath(
      wavePath,
      Paint()
        ..color = const Color(0xFF4ADE80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    // Dimension marker: Amplitude A
    final crestX = startX + (lambda * 0.25);
    final markerPaint = Paint()
      ..color = const Color(0xFFFBBF24)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(crestX, oscCenterY),
      Offset(crestX, oscCenterY - oscAmpPx),
      markerPaint,
    );
    _drawLabel(
      canvas,
      size,
      'Amplitude (A)',
      Offset(crestX + 28, oscCenterY - (oscAmpPx * 0.50)),
      const Color(0xFFFEF3C7),
      borderColor: const Color(0xFFF59E0B),
    );

    // Dimension marker: Wavelength Lambda
    final crest2X = crestX + lambda;
    if (crest2X <= endX) {
      final dimY = oscCenterY - oscAmpPx - 8;
      canvas.drawLine(Offset(crestX, dimY), Offset(crest2X, dimY), markerPaint);
      canvas.drawLine(Offset(crestX, dimY - 4), Offset(crestX, dimY + 4), markerPaint);
      canvas.drawLine(Offset(crest2X, dimY - 4), Offset(crest2X, dimY + 4), markerPaint);
      _drawLabel(
        canvas,
        size,
        'Longueur d\'onde (λ)',
        Offset((crestX + crest2X) * 0.50, dimY - 11),
        const Color(0xFFFEF3C7),
        borderColor: const Color(0xFFF59E0B),
      );
    }

    // Live Readout HUD Pill bottom-right
    final fHz = (100 + intensity * 800).round();
    final lamM = (340.0 / fHz).toStringAsFixed(2);
    _drawLabel(
      canvas,
      size,
      'v = 340 m/s | f = ' + fHz.toString() + 'Hz | λ = ' + lamM + 'm',
      Offset(w * 0.50, h * 0.94),
      const Color(0xFFF1F5F9),
      borderColor: const Color(0xFF38BDF8),
    );
  }

  bool _isEquationBalanceTopic() {
    final env = scene.environment.toLowerCase();
    if (env != 'math' && env != 'algebra') {
      return false;
    }
    final joined = [
      simTitle,
      step.title,
      step.action,
      step.outcome,
      ...scene.objects.map((o) => '${o.sprite} ${o.label}'),
    ].join(' ').toLowerCase();
    return joined.contains('equation') ||
        joined.contains('solve') ||
        joined.contains(' = ') ||
        (joined.contains('balance') && joined.contains('x'));
  }

  void _paintMathBalanceStage(Canvas canvas, Size size) {
    _paintEnvironment(canvas, size);
    final w = size.width;
    final h = size.height;
    final pivot = Offset(w * 0.50, h * 0.40);
    // Beam tilts smoothly based on slider intensity (balanced near 0.5).
    final tilt = ((intensity - 0.5) * 0.28).clamp(-0.22, 0.22);
    final beamHalf = w * 0.29;
    final leftEnd = Offset(
      pivot.dx - math.cos(tilt) * beamHalf,
      pivot.dy - math.sin(tilt) * beamHalf,
    );
    final rightEnd = Offset(
      pivot.dx + math.cos(tilt) * beamHalf,
      pivot.dy + math.sin(tilt) * beamHalf,
    );

    // Pedestal & fulcrum
    final standPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(pivot.dx, h * 0.80), pivot, standPaint);
    canvas.drawLine(
      Offset(pivot.dx - 44, h * 0.80),
      Offset(pivot.dx + 44, h * 0.80),
      standPaint..strokeWidth = 7,
    );

    // Tilting beam
    canvas.drawLine(
      leftEnd,
      rightEnd,
      Paint()
        ..color = const Color(0xFFFBBF24)
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, 8, Paint()..color = const Color(0xFFF59E0B));

    // Left & Right hanging pans
    void drawPan(Offset anchor, Color accent, String title, bool isLeft) {
      final panY = anchor.dy + h * 0.22;
      final stringPaint = Paint()
        ..color = const Color(0xFFCBD5E1)
        ..strokeWidth = 1.8;
      canvas.drawLine(anchor, Offset(anchor.dx - 34, panY), stringPaint);
      canvas.drawLine(anchor, Offset(anchor.dx + 34, panY), stringPaint);
      canvas.drawArc(
        Rect.fromCenter(center: Offset(anchor.dx, panY), width: 76, height: 22),
        0,
        math.pi,
        false,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );

      // Draw visual weight blocks/balls on pan
      if (isLeft) {
        // Mystery bag (x) + unit balls
        final bagRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(anchor.dx - 14, panY - 14),
            width: 24,
            height: 22,
          ),
          const Radius.circular(6),
        );
        canvas.drawRRect(bagRect, Paint()..color = const Color(0xFF3B82F6));
        _drawLabel(
          canvas,
          size,
          'x',
          Offset(anchor.dx - 14, panY - 14),
          const Color(0xFF1D4ED8),
        );
        for (int i = 0; i < 3; i++) {
          canvas.drawCircle(
            Offset(anchor.dx + 12 + (i * 8), panY - 8 - (i % 2) * 8),
            5.5,
            Paint()..color = const Color(0xFFF59E0B),
          );
        }
      } else {
        for (int i = 0; i < 4; i++) {
          canvas.drawCircle(
            Offset(anchor.dx - 16 + (i * 11), panY - 9 - (i % 2) * 7),
            5.5,
            Paint()..color = const Color(0xFF10B981),
          );
        }
      }
      _drawLabel(
        canvas,
        size,
        title,
        Offset(anchor.dx, panY + 24),
        Colors.white,
        borderColor: accent,
      );
    }

    drawPan(leftEnd, const Color(0xFF60A5FA), 'Left Side (x)', true);
    drawPan(rightEnd, const Color(0xFF34D399), 'Right Side (=)', false);

    // Top equation / step banner
    final eqBanner = step.title.isNotEmpty ? step.title : 'Keep Both Sides Balanced (=)';
    _drawLabel(
      canvas,
      size,
      eqBanner,
      Offset(w * 0.50, h * 0.14),
      const Color(0xFFFEF08A),
      borderColor: const Color(0xFFF59E0B),
    );
  }

  void _paintSprite(
    Canvas canvas,
    String sprite,
    Offset c,
    double r,
    Color color,
  ) {
    final bob = math.sin(t * 2 * math.pi + c.dx) * 2.2;
    final p = Offset(c.dx, c.dy + bob);

    switch (sprite.toLowerCase()) {
      case 'ball':
      case 'sphere':
      case 'football':
        canvas.drawCircle(p, r * 0.72, Paint()..color = color);
        canvas.drawCircle(
          p,
          r * 0.72,
          Paint()
            ..color = Colors.white.withAlpha(180)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawArc(
          Rect.fromCenter(center: p, width: r * 1.1, height: r * 1.1),
          0.3,
          2.2,
          false,
          Paint()
            ..color = Colors.white.withAlpha(150)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
        break;

      case 'sun':
        canvas.drawCircle(p, r * 0.9, Paint()..color = color.withAlpha(65));
        canvas.drawCircle(p, r * 0.56, Paint()..color = color);
        for (int i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + t * math.pi;
          canvas.drawLine(
            Offset(p.dx + math.cos(a) * r * 0.68, p.dy + math.sin(a) * r * 0.68),
            Offset(p.dx + math.cos(a) * r * 1.05, p.dy + math.sin(a) * r * 1.05),
            Paint()
              ..color = const Color(0xFFFDE68A)
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round,
          );
        }
        break;

      case 'leaf':
        final leaf = Path()
          ..moveTo(p.dx - r, p.dy + r * 0.2)
          ..quadraticBezierTo(p.dx, p.dy - r, p.dx + r, p.dy - r * 0.2)
          ..quadraticBezierTo(p.dx + r * 0.2, p.dy + r * 0.9, p.dx - r, p.dy + r * 0.2);
        canvas.drawPath(leaf, Paint()..color = color);
        canvas.drawLine(
          Offset(p.dx - r * 0.85, p.dy + r * 0.15),
          Offset(p.dx + r * 0.7, p.dy - r * 0.15),
          Paint()
            ..color = const Color(0xFFBBF7D0)
            ..strokeWidth = 2,
        );
        break;

      case 'root':
        final stemPaint = Paint()
          ..color = const Color(0xFFD97706)
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(p.dx, p.dy - r * 0.6), Offset(p.dx, p.dy + r * 0.2), stemPaint);
        canvas.drawLine(Offset(p.dx, p.dy), Offset(p.dx - r * 0.8, p.dy + r * 0.65), stemPaint);
        canvas.drawLine(Offset(p.dx, p.dy), Offset(p.dx + r * 0.75, p.dy + r * 0.65), stemPaint);
        canvas.drawLine(Offset(p.dx - r * 0.3, p.dy + r * 0.2), Offset(p.dx - r * 0.2, p.dy + r * 0.8), stemPaint);
        break;

      case 'stem':
        final rect = Rect.fromCenter(center: p, width: r * 0.75, height: r * 1.8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          Paint()..color = const Color(0xFF0D9488).withAlpha(110),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          Paint()
            ..color = const Color(0xFF5EEAD4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        break;

      case 'cell':
        canvas.drawOval(
          Rect.fromCenter(center: p, width: r * 2.1, height: r * 1.45),
          Paint()..color = color.withAlpha(85),
        );
        canvas.drawOval(
          Rect.fromCenter(center: p, width: r * 2.1, height: r * 1.45),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
        canvas.drawCircle(
          Offset(p.dx - r * 0.25, p.dy),
          r * 0.36,
          Paint()..color = const Color(0xFF6366F1),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(p.dx + r * 0.45, p.dy + 4), width: r * 0.45, height: r * 0.25),
          Paint()..color = const Color(0xFF10B981),
        );
        break;

      case 'beaker':
        final flask = Path()
          ..moveTo(p.dx - r * 0.35, p.dy - r * 0.85)
          ..lineTo(p.dx - r * 0.35, p.dy - r * 0.2)
          ..lineTo(p.dx - r * 0.85, p.dy + r * 0.8)
          ..lineTo(p.dx + r * 0.85, p.dy + r * 0.8)
          ..lineTo(p.dx + r * 0.35, p.dy - r * 0.2)
          ..lineTo(p.dx + r * 0.35, p.dy - r * 0.85)
          ..close();
        canvas.drawPath(flask, Paint()..color = color.withAlpha(90));
        canvas.drawPath(
          flask,
          Paint()
            ..color = const Color(0xFFBAE6FD)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        break;

      case 'flame':
        final flame = Path()
          ..moveTo(p.dx, p.dy - r * 0.9)
          ..quadraticBezierTo(p.dx + r * 0.75, p.dy + r * 0.1, p.dx, p.dy + r * 0.75)
          ..quadraticBezierTo(p.dx - r * 0.75, p.dy + r * 0.1, p.dx, p.dy - r * 0.9);
        canvas.drawPath(flame, Paint()..color = const Color(0xFFF97316));
        canvas.drawCircle(Offset(p.dx, p.dy + r * 0.2), r * 0.25, Paint()..color = const Color(0xFFFEF08A));
        break;

      case 'atom':
        canvas.drawCircle(p, r * 0.24, Paint()..color = const Color(0xFFF43F5E));
        for (int i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(i == 0 ? 0.6 : -0.6);
          canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: r * 2.1, height: r * 0.85),
            Paint()
              ..color = const Color(0xFF60A5FA)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8,
          );
          final a = t * 2 * math.pi + i * math.pi;
          canvas.drawCircle(
            Offset(math.cos(a) * r * 1.05, math.sin(a) * r * 0.42),
            4,
            Paint()..color = const Color(0xFF38BDF8),
          );
          canvas.restore();
        }
        break;

      case 'bulb':
        canvas.drawCircle(p, r * 1.05, Paint()..color = const Color(0xFFFDE047).withAlpha((80 + 70 * math.sin(t * 2 * math.pi)).round()));
        canvas.drawCircle(Offset(p.dx, p.dy - 4), r * 0.58, Paint()..color = const Color(0xFFFACC15));
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx, p.dy + r * 0.55), width: r * 0.5, height: r * 0.35), const Radius.circular(3)),
          Paint()..color = const Color(0xFF94A3B8),
        );
        break;

      case 'battery':
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: r * 1.4, height: r * 0.9), const Radius.circular(5)),
          Paint()..color = color,
        );
        canvas.drawRect(Rect.fromCenter(center: Offset(p.dx + r * 0.8, p.dy), width: 5, height: r * 0.4), Paint()..color = Colors.white);
        break;

      case 'shop':
      case 'bank':
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx, p.dy + 4), width: r * 1.6, height: r * 1.15), const Radius.circular(6)),
          Paint()..color = color.withAlpha(200),
        );
        final roof = Path()
          ..moveTo(p.dx - r * 0.95, p.dy - r * 0.12)
          ..lineTo(p.dx, p.dy - r * 0.85)
          ..lineTo(p.dx + r * 0.95, p.dy - r * 0.12)
          ..close();
        canvas.drawPath(roof, Paint()..color = const Color(0xFFF59E0B));
        canvas.drawRect(
          Rect.fromCenter(center: Offset(p.dx, p.dy + r * 0.3), width: r * 0.45, height: r * 0.65),
          Paint()..color = const Color(0xFFFEF3C7),
        );
        break;

      case 'person':
        canvas.drawCircle(Offset(p.dx, p.dy - r * 0.45), r * 0.34, Paint()..color = color);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx, p.dy + r * 0.25), width: r * 0.85, height: r * 0.8), const Radius.circular(10)),
          Paint()..color = color.withAlpha(220),
        );
        break;

      case 'coin':
        for (int i = -1; i <= 1; i++) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(p.dx, p.dy - i * 6.0), width: r * 1.35, height: r * 0.65),
            Paint()..color = i == 1 ? const Color(0xFFFCD34D) : const Color(0xFFD97706),
          );
        }
        break;

      case 'chart':
        final bars = [0.45, 0.75, 1.0];
        for (int i = 0; i < 3; i++) {
          final h = r * 1.4 * bars[i];
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(p.dx - r * 0.75 + i * r * 0.55, p.dy + r * 0.7 - h, r * 0.38, h),
              const Radius.circular(3),
            ),
            Paint()..color = color,
          );
        }
        break;

      case 'wave':
        final wPath = Path();
        for (double dx = -r; dx <= r; dx += 2) {
          final yOff = math.sin((dx / r) * math.pi * 2 + t * 2 * math.pi) * (r * 0.45);
          if (dx == -r) {
            wPath.moveTo(p.dx + dx, p.dy + yOff);
          } else {
            wPath.lineTo(p.dx + dx, p.dy + yOff);
          }
        }
        canvas.drawPath(
          wPath,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
        break;

      case 'heart':
        canvas.drawCircle(Offset(p.dx - r * 0.28, p.dy - r * 0.15), r * 0.38, Paint()..color = color);
        canvas.drawCircle(Offset(p.dx + r * 0.28, p.dy - r * 0.15), r * 0.38, Paint()..color = color);
        final tri = Path()
          ..moveTo(p.dx - r * 0.65, p.dy)
          ..lineTo(p.dx + r * 0.65, p.dy)
          ..lineTo(p.dx, p.dy + r * 0.72)
          ..close();
        canvas.drawPath(tri, Paint()..color = color);
        break;

      case 'drop':
        final drop = Path()
          ..moveTo(p.dx, p.dy - r * 0.85)
          ..quadraticBezierTo(p.dx + r * 0.8, p.dy + r * 0.2, p.dx, p.dy + r * 0.75)
          ..quadraticBezierTo(p.dx - r * 0.8, p.dy + r * 0.2, p.dx, p.dy - r * 0.85);
        canvas.drawPath(drop, Paint()..color = color);
        break;

      case 'crystal':
        final hex = Path();
        for (int i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          final pt = Offset(p.dx + math.cos(a) * r * 0.78, p.dy + math.sin(a) * r * 0.78);
          if (i == 0) {
            hex.moveTo(pt.dx, pt.dy);
          } else {
            hex.lineTo(pt.dx, pt.dy);
          }
        }
        hex.close();
        canvas.drawPath(hex, Paint()..color = color.withAlpha(110));
        canvas.drawPath(
          hex,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
        break;

      case 'plant':
        canvas.drawLine(
          Offset(p.dx, p.dy + r * 0.65),
          Offset(p.dx, p.dy - r * 0.55),
          Paint()
            ..color = const Color(0xFF16A34A)
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
        final lpLeft = Path()
          ..moveTo(p.dx, p.dy)
          ..quadraticBezierTo(p.dx - r * 0.7, p.dy - r * 0.5, p.dx - r * 0.9, p.dy - r * 0.1)
          ..quadraticBezierTo(p.dx - r * 0.4, p.dy + r * 0.2, p.dx, p.dy);
        final lpRight = Path()
          ..moveTo(p.dx, p.dy - r * 0.18)
          ..quadraticBezierTo(p.dx + r * 0.7, p.dy - r * 0.7, p.dx + r * 0.9, p.dy - r * 0.28)
          ..quadraticBezierTo(p.dx + r * 0.4, p.dy + r * 0.05, p.dx, p.dy - r * 0.18);
        canvas.drawPath(lpLeft, Paint()..color = const Color(0xFF22C55E));
        canvas.drawPath(lpRight, Paint()..color = const Color(0xFF22C55E));
        break;

      case 'axes':
        final axPaint = Paint()
          ..color = const Color(0xFF93C5FD)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(p.dx - r * 0.85, p.dy + r * 0.55), Offset(p.dx + r * 0.9, p.dy + r * 0.55), axPaint);
        canvas.drawLine(Offset(p.dx - r * 0.65, p.dy + r * 0.75), Offset(p.dx - r * 0.65, p.dy - r * 0.8), axPaint);
        final curve = Path();
        for (int i = 0; i <= 16; i++) {
          final frac = i / 16.0;
          final cx = p.dx - r * 0.55 + frac * r * 1.35;
          final norm = (frac - 0.5) * 2.0;
          final cy = p.dy + r * 0.42 - (1.0 - norm * norm * 0.75) * r * 0.95;
          if (i == 0) {
            curve.moveTo(cx, cy);
          } else {
            curve.lineTo(cx, cy);
          }
        }
        canvas.drawPath(
          curve,
          Paint()
            ..color = const Color(0xFF34D399)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0,
        );
        final dotFrac = t;
        final dNorm = (dotFrac - 0.5) * 2.0;
        canvas.drawCircle(
          Offset(p.dx - r * 0.55 + dotFrac * r * 1.35, p.dy + r * 0.42 - (1.0 - dNorm * dNorm * 0.75) * r * 0.95),
          4.8,
          Paint()..color = const Color(0xFFFBBF24),
        );
        break;

      case 'triangle':
        final tri = Path()
          ..moveTo(p.dx - r * 0.75, p.dy + r * 0.65)
          ..lineTo(p.dx - r * 0.75, p.dy - r * 0.75)
          ..lineTo(p.dx + r * 0.8, p.dy + r * 0.65)
          ..close();
        canvas.drawPath(tri, Paint()..color = color.withAlpha(85));
        canvas.drawPath(
          tri,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.8,
        );
        canvas.drawRect(
          Rect.fromLTWH(p.dx - r * 0.75, p.dy + r * 0.40, r * 0.25, r * 0.25),
          Paint()
            ..color = Colors.white.withAlpha(180)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
        break;

      case 'scale':
        final tilt = math.sin(t * 2 * math.pi) * 0.14;
        final beamPaint = Paint()
          ..color = const Color(0xFFFBBF24)
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(p.dx, p.dy - r * 0.55), Offset(p.dx, p.dy + r * 0.75), beamPaint);
        canvas.drawLine(Offset(p.dx - r * 0.45, p.dy + r * 0.75), Offset(p.dx + r * 0.45, p.dy + r * 0.75), beamPaint);
        final lEnd = Offset(p.dx - r * 0.8, p.dy - r * 0.35 + tilt * r);
        final rEnd = Offset(p.dx + r * 0.8, p.dy - r * 0.35 - tilt * r);
        canvas.drawLine(lEnd, rEnd, beamPaint);
        canvas.drawArc(Rect.fromCenter(center: Offset(lEnd.dx, lEnd.dy + r * 0.38), width: r * 0.6, height: r * 0.35), 0, math.pi, false, beamPaint..style = PaintingStyle.stroke);
        canvas.drawArc(Rect.fromCenter(center: Offset(rEnd.dx, rEnd.dy + r * 0.38), width: r * 0.6, height: r * 0.35), 0, math.pi, false, beamPaint..style = PaintingStyle.stroke);
        break;

      case 'cpu':
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: r * 1.35, height: r * 1.35), const Radius.circular(8)),
          Paint()..color = color.withAlpha(210),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: r * 0.75, height: r * 0.75), const Radius.circular(4)),
          Paint()..color = const Color(0xFF38BDF8),
        );
        final pinPaint = Paint()
          ..color = const Color(0xFFE2E8F0)
          ..strokeWidth = 2.2;
        for (int i = -1; i <= 1; i++) {
          final off = i * r * 0.35;
          canvas.drawLine(Offset(p.dx + off, p.dy - r * 0.68), Offset(p.dx + off, p.dy - r * 0.92), pinPaint);
          canvas.drawLine(Offset(p.dx + off, p.dy + r * 0.68), Offset(p.dx + off, p.dy + r * 0.92), pinPaint);
          canvas.drawLine(Offset(p.dx - r * 0.68, p.dy + off), Offset(p.dx - r * 0.92, p.dy + off), pinPaint);
          canvas.drawLine(Offset(p.dx + r * 0.68, p.dy + off), Offset(p.dx + r * 0.92, p.dy + off), pinPaint);
        }
        break;

      case 'database':
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx, p.dy + 2), width: r * 1.35, height: r * 1.35), const Radius.circular(8)),
          Paint()..color = color.withAlpha(190),
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(p.dx, p.dy - r * 0.55), width: r * 1.35, height: r * 0.48),
          Paint()..color = const Color(0xFF99F6E4),
        );
        for (final yOff in [-0.08, 0.28]) {
          canvas.drawLine(
            Offset(p.dx - r * 0.5, p.dy + r * yOff),
            Offset(p.dx + r * 0.5, p.dy + r * yOff),
            Paint()
              ..color = Colors.white.withAlpha(180)
              ..strokeWidth = 2.0,
          );
        }
        break;

      case 'book':
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx - r * 0.38, p.dy), width: r * 0.78, height: r * 1.25), const Radius.circular(4)),
          Paint()..color = const Color(0xFFFEF3C7),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx + r * 0.38, p.dy), width: r * 0.78, height: r * 1.25), const Radius.circular(4)),
          Paint()..color = Colors.white,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: r * 1.56, height: r * 1.28), const Radius.circular(5)),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6,
        );
        canvas.drawLine(Offset(p.dx, p.dy - r * 0.62), Offset(p.dx, p.dy + r * 0.62), Paint()..color = color..strokeWidth = 2.2);
        break;

      case 'mountain':
        final mtn = Path()
          ..moveTo(p.dx - r * 0.95, p.dy + r * 0.7)
          ..lineTo(p.dx - r * 0.2, p.dy - r * 0.75)
          ..lineTo(p.dx + r * 0.3, p.dy + r * 0.05)
          ..lineTo(p.dx + r * 0.62, p.dy - r * 0.4)
          ..lineTo(p.dx + r * 0.95, p.dy + r * 0.7)
          ..close();
        canvas.drawPath(mtn, Paint()..color = const Color(0xFF16A34A));
        canvas.drawPath(
          mtn,
          Paint()
            ..color = const Color(0xFF14532D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        break;

      case 'cloud':
        final cl = Paint()..color = const Color(0xFFE0F2FE);
        canvas.drawCircle(Offset(p.dx - r * 0.42, p.dy + r * 0.05), r * 0.42, cl);
        canvas.drawCircle(Offset(p.dx + r * 0.42, p.dy + r * 0.08), r * 0.38, cl);
        canvas.drawCircle(Offset(p.dx, p.dy - r * 0.16), r * 0.52, cl);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx, p.dy + r * 0.22), width: r * 1.3, height: r * 0.48), const Radius.circular(12)), cl);
        break;

      case 'globe':
        canvas.drawCircle(p, r * 0.78, Paint()..color = const Color(0xFF0284C7));
        canvas.drawCircle(Offset(p.dx - r * 0.18, p.dy - r * 0.1), r * 0.32, Paint()..color = const Color(0xFF22C55E));
        canvas.drawCircle(Offset(p.dx + r * 0.25, p.dy + r * 0.18), r * 0.24, Paint()..color = const Color(0xFF16A34A));
        canvas.drawCircle(
          p,
          r * 0.78,
          Paint()
            ..color = const Color(0xFFBAE6FD)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        break;

      case 'document':
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: r * 1.15, height: r * 1.45), const Radius.circular(6)),
          Paint()..color = Colors.white.withAlpha(235),
        );
        for (int i = -1; i <= 1; i++) {
          canvas.drawLine(
            Offset(p.dx - r * 0.35, p.dy + i * r * 0.32),
            Offset(p.dx + r * 0.35, p.dy + i * r * 0.32),
            Paint()
              ..color = color
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round,
          );
        }
        break;

      case 'truck':
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx - r * 0.15, p.dy), width: r * 1.1, height: r * 0.8), const Radius.circular(5)), Paint()..color = color);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx + r * 0.62, p.dy + r * 0.12), width: r * 0.5, height: r * 0.56), const Radius.circular(4)), Paint()..color = const Color(0xFFF59E0B));
        canvas.drawCircle(Offset(p.dx - r * 0.4, p.dy + r * 0.45), r * 0.2, Paint()..color = const Color(0xFF0F172A));
        canvas.drawCircle(Offset(p.dx + r * 0.55, p.dy + r * 0.45), r * 0.2, Paint()..color = const Color(0xFF0F172A));
        break;

      case 'magnet':
        canvas.drawArc(
          Rect.fromCenter(center: p, width: r * 1.25, height: r * 1.35),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = const Color(0xFFEF4444)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8.0
            ..strokeCap = StrokeCap.round,
        );
        break;

      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: r * 1.45, height: r * 1.15), const Radius.circular(9)),
          Paint()..color = color.withAlpha(210),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: r * 1.45, height: r * 1.15), const Radius.circular(9)),
          Paint()
            ..color = Colors.white.withAlpha(180)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        break;
    }
  }

  void _drawLabel(
    Canvas canvas,
    Size size,
    String text,
    Offset center,
    Color color, {
    Color borderColor = const Color(0xFF94A3B8),
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 122);

    const padX = 8.0;
    const padY = 4.0;
    final boxW = tp.width + padX * 2;
    final boxH = tp.height + padY * 2;
    final left = (center.dx - boxW / 2)
        .clamp(6.0, math.max(6.0, size.width - boxW - 6.0))
        .toDouble();
    final top = (center.dy - boxH / 2)
        .clamp(6.0, math.max(6.0, size.height - boxH - 6.0))
        .toDouble();

    Rect candidate = Rect.fromLTWH(left, top, boxW, boxH);
    for (int tries = 0; tries < 6; tries++) {
      final overlaps = _placedLabels.any((r) => r.overlaps(candidate));
      if (!overlaps) break;
      final shift = ((tries ~/ 2) + 1) * (boxH + 4.0);
      final tryTop = tries.isEven ? top - shift : top + shift;
      final clampedTop = tryTop
          .clamp(6.0, math.max(6.0, size.height - boxH - 6.0))
          .toDouble();
      candidate = Rect.fromLTWH(left, clampedTop, boxW, boxH);
    }
    _placedLabels.add(candidate);

    final rrect = RRect.fromRectAndRadius(candidate, const Radius.circular(8));
    canvas.drawRRect(
      rrect,
      Paint()..color = const Color(0xFF0F172A).withAlpha(224),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor.withAlpha(200)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    tp.paint(canvas, Offset(candidate.left + padX, candidate.top + padY));
  }

  @override
  bool shouldRepaint(covariant _VirtualSimulationPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.scene != scene ||
        oldDelegate.step.title != step.title ||
        oldDelegate.intensity != intensity ||
        oldDelegate.highlightNorm != highlightNorm;
  }
}

/// Renders an inline standard IEEE/ANSI Logic Gate symbol diagram + Boolean
/// formula + compact truth table directly inside lesson notes.
class _LogicGateDiagramCard extends StatelessWidget {
  final String gateType;

  const _LogicGateDiagramCard({required this.gateType});

  @override
  Widget build(BuildContext context) {
    final info = _gateMetadata(gateType);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 76,
            child: CustomPaint(
              painter: _LogicGatePainter(gateType: gateType),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${info.title} • ${info.formula}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: _kDeepNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info.rule,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF334155),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  info.truth,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _kPrimaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({String title, String formula, String rule, String truth}) _gateMetadata(
    String g,
  ) {
    switch (g) {
      case 'NOT':
        return (
          title: 'NOT Gate (Inverter)',
          formula: 'Q = Ā',
          rule: 'Flips the input: 0 becomes 1, and 1 becomes 0.',
          truth: 'A=0 → Q=1   |   A=1 → Q=0',
        );
      case 'AND':
        return (
          title: 'AND Gate',
          formula: 'Q = A · B',
          rule: 'Outputs 1 ONLY when BOTH A and B are 1.',
          truth: '0,0→0  |  0,1→0  |  1,0→0  |  1,1→1',
        );
      case 'OR':
        return (
          title: 'OR Gate',
          formula: 'Q = A + B',
          rule: 'Outputs 1 when AT LEAST ONE input (A or B) is 1.',
          truth: '0,0→0  |  0,1→1  |  1,0→1  |  1,1→1',
        );
      case 'NAND':
        return (
          title: 'NAND Gate',
          formula: 'Q = (A · B)′',
          rule: 'Opposite of AND: outputs 0 only when both A and B are 1.',
          truth: '0,0→1  |  0,1→1  |  1,0→1  |  1,1→0',
        );
      case 'NOR':
        return (
          title: 'NOR Gate',
          formula: 'Q = (A + B)′',
          rule: 'Opposite of OR: outputs 1 only when both A and B are 0.',
          truth: '0,0→1  |  0,1→0  |  1,0→0  |  1,1→0',
        );
      case 'XNOR':
        return (
          title: 'XNOR Gate',
          formula: 'Q = (A ⊕ B)′',
          rule: 'Outputs 1 when both inputs are the SAME.',
          truth: '0,0→1  |  0,1→0  |  1,0→0  |  1,1→1',
        );
      default:
        return (
          title: 'XOR Gate',
          formula: 'Q = A ⊕ B',
          rule: 'Outputs 1 when inputs are DIFFERENT (one 1, one 0).',
          truth: '0,0→0  |  0,1→1  |  1,0→1  |  1,1→0',
        );
    }
  }
}

class _LogicGatePainter extends CustomPainter {
  final String gateType;

  _LogicGatePainter({required this.gateType});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final wirePaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final bodyStroke = Paint()
      ..color = _kDeepNavy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round;
    final bodyFill = Paint()..color = const Color(0xFFE0E7FF);

    final isSingleInput = gateType == 'NOT';
    final hasBubble = gateType == 'NOT' ||
        gateType == 'NAND' ||
        gateType == 'NOR' ||
        gateType == 'XNOR';
    final isOrFamily = gateType == 'OR' ||
        gateType == 'NOR' ||
        gateType == 'XOR' ||
        gateType == 'XNOR';
    final isXor = gateType == 'XOR' || gateType == 'XNOR';

    final leftX = w * 0.27;
    final rightX = hasBubble ? w * 0.67 : w * 0.72;
    final topY = h * 0.20;
    final botY = h * 0.80;
    final midY = h * 0.50;

    // Input wires + labels
    if (isSingleInput) {
      canvas.drawLine(Offset(w * 0.08, midY), Offset(leftX, midY), wirePaint);
      _drawText(canvas, 'A', Offset(w * 0.02, midY - 7));
    } else {
      final y1 = h * 0.34;
      final y2 = h * 0.66;
      final wireEnd = isOrFamily ? leftX + 6 : leftX;
      canvas.drawLine(Offset(w * 0.08, y1), Offset(wireEnd, y1), wirePaint);
      canvas.drawLine(Offset(w * 0.08, y2), Offset(wireEnd, y2), wirePaint);
      _drawText(canvas, 'A', Offset(w * 0.02, y1 - 7));
      _drawText(canvas, 'B', Offset(w * 0.02, y2 - 7));
    }

    // Gate body
    if (gateType == 'NOT') {
      final path = Path()
        ..moveTo(leftX, topY)
        ..lineTo(rightX, midY)
        ..lineTo(leftX, botY)
        ..close();
      canvas.drawPath(path, bodyFill);
      canvas.drawPath(path, bodyStroke);
    } else if (isOrFamily) {
      final path = Path()
        ..moveTo(leftX, topY)
        ..quadraticBezierTo(w * 0.50, topY, rightX, midY)
        ..quadraticBezierTo(w * 0.50, botY, leftX, botY)
        ..quadraticBezierTo(leftX + 12, midY, leftX, topY)
        ..close();
      canvas.drawPath(path, bodyFill);
      canvas.drawPath(path, bodyStroke);
      if (isXor) {
        final backArc = Path()
          ..moveTo(leftX - 7, topY)
          ..quadraticBezierTo(leftX + 5, midY, leftX - 7, botY);
        canvas.drawPath(backArc, bodyStroke);
      }
    } else {
      // AND / NAND (D-shape)
      final curveStart = w * 0.48;
      final path = Path()
        ..moveTo(leftX, topY)
        ..lineTo(curveStart, topY)
        ..quadraticBezierTo(rightX + 8, topY, rightX, midY)
        ..quadraticBezierTo(rightX + 8, botY, curveStart, botY)
        ..lineTo(leftX, botY)
        ..close();
      canvas.drawPath(path, bodyFill);
      canvas.drawPath(path, bodyStroke);
    }

    // Inversion bubble & output wire
    var outStart = rightX;
    if (hasBubble) {
      const bubbleR = 4.5;
      final bubbleCenter = Offset(rightX + bubbleR, midY);
      canvas.drawCircle(bubbleCenter, bubbleR, Paint()..color = Colors.white);
      canvas.drawCircle(bubbleCenter, bubbleR, bodyStroke);
      outStart = rightX + bubbleR * 2;
    }
    canvas.drawLine(Offset(outStart, midY), Offset(w * 0.88, midY), wirePaint);
    _drawText(canvas, 'Q', Offset(w * 0.90, midY - 7));
  }

  void _drawText(Canvas canvas, String text, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _kDeepNavy,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _LogicGatePainter oldDelegate) =>
      oldDelegate.gateType != gateType;
}



