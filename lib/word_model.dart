class Word {
  final int? id;
  final String word;
  final String pronunciation;
  final String meaning;
  final String vietnamese;
  final String english;
  final String grammar;
  final int status; // 0: 미학습, 1: 3일 후, 2: 1주일 후, 3: 2주일 후, 4: 한달 후, 5: 외움 완료
  final DateTime? statusUpdatedAt;

  Word({
    this.id,
    required this.word,
    required this.pronunciation,
    required this.meaning,
    required this.vietnamese,
    required this.english,
    required this.grammar,
    required this.status,
    this.statusUpdatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'word': word,
      'pronunciation': pronunciation,
      'meaning': meaning,
      'vietnamese': vietnamese,
      'english': english,
      'grammar': grammar,
      'status': status,
      'status_updated_at': statusUpdatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  factory Word.fromMap(Map<String, dynamic> map) {
    return Word(
      id: map['id'],
      word: map['word'] ?? '',
      pronunciation: map['pronunciation'] ?? '',
      meaning: map['meaning'] ?? '',
      vietnamese: map['vietnamese'] ?? '',
      english: map['english'] ?? '',
      grammar: map['grammar'] ?? '',
      status: map['status'] ?? 0,
      statusUpdatedAt: map['status_updated_at'] != null ? DateTime.tryParse(map['status_updated_at'].toString()) : null,
    );
  }

  Word copyWith({
    int? id,
    String? word,
    String? pronunciation,
    String? meaning,
    String? vietnamese,
    String? english,
    String? grammar,
    int? status,
    DateTime? statusUpdatedAt,
  }) {
    return Word(
      id: id ?? this.id,
      word: word ?? this.word,
      pronunciation: pronunciation ?? this.pronunciation,
      meaning: meaning ?? this.meaning,
      vietnamese: vietnamese ?? this.vietnamese,
      english: english ?? this.english,
      grammar: grammar ?? this.grammar,
      status: status ?? this.status,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
    );
  }
}
