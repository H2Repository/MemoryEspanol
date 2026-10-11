import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart';
import 'word_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  DatabaseHelper._init();

  SupabaseClient get _client => Supabase.instance.client;

  Future<int> getWordCount() async {
    try {
      final response = await _client.from('words').select('id');
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> loadExcelFromAssets() async {
    try {
      final ByteData data = await rootBundle.load('assets/통합 문서1.xlsx');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await loadExcelFromBytes(bytes);
    } catch (e) {
      // ignore
    }
  }

  Future<int> loadExcelFromBytes(Uint8List bytes) async {
    try {
      var excel = Excel.decodeBytes(bytes);
      int addedCount = 0;
      final nowIso = DateTime.now().toIso8601String();

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table];
        if (sheet == null) continue;

        for (var row in sheet.rows) {
          if (row.isEmpty) continue;
          
          String word = row.isNotEmpty && row[0]?.value != null ? row[0]!.value.toString().trim() : '';
          if (word.isEmpty || word.toLowerCase() == 'word') continue;

          String pronunciation = row.length > 1 && row[1]?.value != null ? row[1]!.value.toString().trim() : '';
          String meaning = row.length > 2 && row[2]?.value != null ? row[2]!.value.toString().trim() : '';
          String vietnamese = row.length > 3 && row[3]?.value != null ? row[3]!.value.toString().trim() : '';
          String english = row.length > 4 && row[4]?.value != null ? row[4]!.value.toString().trim() : '';
          String grammar = row.length > 5 && row[5]?.value != null ? row[5]!.value.toString().trim() : '';

          try {
            final existing = await _client.from('words').select('id').eq('word', word).maybeSingle();
            if (existing == null) {
              await _client.from('words').insert({
                'word': word,
                'pronunciation': pronunciation,
                'meaning': meaning,
                'vietnamese': vietnamese,
                'english': english,
                'grammar': grammar,
                'status': 0,
                'status_updated_at': nowIso,
              });
              addedCount++;
            }
          } catch (_) {}
        }
      }
      return addedCount;
    } catch (e) {
      return 0;
    }
  }

  Future<List<Word>> getAllWords() async {
    try {
      final response = await _client.from('words').select().order('id', ascending: true);
      return (response as List).map((map) => Word.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Word>> searchWords(String query, String filterType) async {
    try {
      final response = await _client.from('words').select().order('id', ascending: true);
      var words = (response as List).map((map) => Word.fromMap(map)).toList();

      final now = DateTime.now();

      // Filter by type
      if (filterType == 'study_due') {
        words = words.where((w) {
          if (w.status == 0) return true; // 미학습은 항상 학습 대상
          if (w.status == 5) return false; // 외움 완료는 복습 대상 아님
          if (w.statusUpdatedAt == null) return false;

          final updatedAt = w.statusUpdatedAt!.toLocal();
          final diffDays = now.difference(updatedAt).inDays;

          if (w.status == 1 && diffDays >= 3) return true;  // 3일 후 (3일 이상 경과)
          if (w.status == 2 && diffDays >= 7) return true;  // 1주일 후 (7일 이상 경과)
          if (w.status == 3 && diffDays >= 14) return true; // 2주일 후 (14일 이상 경과)
          if (w.status == 4 && diffDays >= 30) return true; // 한달 후 (30일 이상 경과)
          return false;
        }).toList();
      } else if (filterType != 'all') {
        int? statusVal = int.tryParse(filterType);
        if (statusVal != null) {
          words = words.where((w) => w.status == statusVal).toList();
        }
      }

      // Filter by search query
      if (query.trim().isNotEmpty) {
        final q = query.toLowerCase();
        words = words.where((w) =>
          w.word.toLowerCase().contains(q) ||
          w.meaning.toLowerCase().contains(q) ||
          w.english.toLowerCase().contains(q) ||
          w.vietnamese.toLowerCase().contains(q) ||
          w.pronunciation.toLowerCase().contains(q) ||
          w.grammar.toLowerCase().contains(q)
        ).toList();
      }

      return words;
    } catch (e) {
      return [];
    }
  }

  Future<void> insertWord(Word word) async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      final map = word.toMap();
      map['status_updated_at'] = nowIso;
      await _client.from('words').insert(map);
    } catch (_) {}
  }

  Future<void> updateWord(Word word) async {
    try {
      if (word.id != null) {
        final nowIso = DateTime.now().toIso8601String();
        final map = word.toMap();
        map['status_updated_at'] = nowIso;
        await _client.from('words').update(map).eq('id', word.id!);
      }
    } catch (_) {}
  }

  Future<void> deleteWord(int id) async {
    try {
      await _client.from('words').delete().eq('id', id);
    } catch (_) {}
  }

  Future<void> updateWordStatus(int id, int newStatus) async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      await _client.from('words').update({
        'status': newStatus,
        'status_updated_at': nowIso,
      }).eq('id', id);
    } catch (_) {}
  }

  Future<void> resetAllWords() async {
    try {
      final nowIso = DateTime.now().toIso8601String();
      await _client.from('words').update({
        'status': 0,
        'status_updated_at': nowIso,
      }).gte('id', 0);
    } catch (_) {}
  }

  Future<Uint8List?> exportToExcel() async {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Words'];
      excel.delete('Sheet1');

      sheet.appendRow([
        TextCellValue('Word'),
        TextCellValue('Pronunciation'),
        TextCellValue('Meaning'),
        TextCellValue('Vietnamese'),
        TextCellValue('English'),
        TextCellValue('Grammar'),
        TextCellValue('Status'),
        TextCellValue('StatusUpdatedAt'),
      ]);

      final words = await getAllWords();
      for (var w in words) {
        sheet.appendRow([
          TextCellValue(w.word),
          TextCellValue(w.pronunciation),
          TextCellValue(w.meaning),
          TextCellValue(w.vietnamese),
          TextCellValue(w.english),
          TextCellValue(w.grammar),
          IntCellValue(w.status),
          TextCellValue(w.statusUpdatedAt?.toIso8601String() ?? ''),
        ]);
      }

      return Uint8List.fromList(excel.encode()!);
    } catch (e) {
      return null;
    }
  }
}
