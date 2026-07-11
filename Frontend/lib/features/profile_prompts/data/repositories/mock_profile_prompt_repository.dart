import '../../domain/models/prompt_bank_item.dart';
import '../../domain/repositories/profile_prompt_repository.dart';

/// In-memory mock — no network calls. Default implementation until the
/// backend team ships real endpoints (see [ApiProfilePromptRepository]).
class MockProfilePromptRepository implements ProfilePromptRepository {
  static final List<PromptBankItem> _bank = [
    // ─── Personality ───────────────────────────────────────────────
    const PromptBankItem(
      id: 'p1',
      category: PromptCategory.personality,
      promptText: "People say I'm the go-to person for…",
    ),
    const PromptBankItem(
      id: 'p2',
      category: PromptCategory.personality,
      promptText: 'One thing that always makes me smile…',
    ),
    const PromptBankItem(
      id: 'p3',
      category: PromptCategory.personality,
      promptText: 'My most unusual talent…',
    ),
    const PromptBankItem(
      id: 'p4',
      category: PromptCategory.personality,
      promptText: 'I am happiest when…',
    ),
    const PromptBankItem(
      id: 'p5',
      category: PromptCategory.personality,
      promptText: 'My perfect Sunday is…',
    ),

    // ─── Marriage & Compatibility ──────────────────────────────────
    const PromptBankItem(
      id: 'm1',
      category: PromptCategory.marriageCompatibility,
      promptText: 'My idea of marriage is…',
    ),
    const PromptBankItem(
      id: 'm2',
      category: PromptCategory.marriageCompatibility,
      promptText: 'A relationship works best when…',
    ),
    const PromptBankItem(
      id: 'm3',
      category: PromptCategory.marriageCompatibility,
      promptText: 'I value my partner because…',
    ),

    // ─── Family ─────────────────────────────────────────────────────
    const PromptBankItem(
      id: 'f1',
      category: PromptCategory.family,
      promptText: 'My family describes me as…',
    ),
    const PromptBankItem(
      id: 'f2',
      category: PromptCategory.family,
      promptText: 'Family traditions I love…',
    ),

    // ─── Career ─────────────────────────────────────────────────────
    const PromptBankItem(
      id: 'c1',
      category: PromptCategory.career,
      promptText: 'My biggest ambition is…',
    ),
    const PromptBankItem(
      id: 'c2',
      category: PromptCategory.career,
      promptText: 'Work-life balance means…',
    ),
  ];

  // Seeded with one answered prompt so display surfaces have something
  // real to show out of the box.
  final List<PromptAnswer> _saved = [
    const PromptAnswer(
      promptId: 'p5',
      promptText: 'My perfect Sunday is…',
      answerText: 'Coffee, family time and exploring new places',
    ),
  ];

  @override
  Future<List<PromptBankItem>> getPrompts({PromptCategory? category}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (category == null) return List.unmodifiable(_bank);
    return _bank.where((p) => p.category == category).toList();
  }

  @override
  Future<List<PromptAnswer>> getUserPrompts() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return List.unmodifiable(_saved);
  }

  @override
  Future<void> saveUserPrompts(List<PromptAnswer> prompts) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _saved
      ..clear()
      ..addAll(prompts);
  }
}
