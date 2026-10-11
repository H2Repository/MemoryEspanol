import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'database_helper.dart';
import 'word_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      publishableKey: dotenv.env['SUPABASE_KEY']!,
    );
    if (await DatabaseHelper.instance.getWordCount() == 0) {
      await DatabaseHelper.instance.loadExcelFromAssets();
    }
  } catch (e) {
    debugPrint('Supabase initialization/load error: $e');
  }
  runApp(const MemoryEspanolApp());
}

class MemoryEspanolApp extends StatelessWidget {
  const MemoryEspanolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '스페인어 단어 학습',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent,
          surface: Color(0xFF161B22),
          secondary: Colors.blueAccent,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            mouseCursor: WidgetStateProperty.all(SystemMouseCursors.click),
          ),
        ),
      ),
      home: const WordListScreen(),
    );
  }
}

class WordListScreen extends StatefulWidget {
  const WordListScreen({super.key});

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen> {
  List<Word> _allWords = [];
  List<Word> _filteredWords = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _selectedStatusFilter = 0; // Default to 0: 미학습

  final Map<int, String> _statusNames = {
    0: '미학습',
    1: '1주일 후',
    2: '2주일 후',
    3: '한달 후',
    4: '외움 완료',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    final words = await DatabaseHelper.instance.searchWords(_searchQuery, _selectedStatusFilter);
    final all = await DatabaseHelper.instance.getAllWords();
    if (!mounted) return;
    setState(() {
      _filteredWords = words;
      _allWords = all;
      _isLoading = false;
    });
  }

  Future<void> _startStudy() async {
    if (_filteredWords.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getInt('last_studied_word_id');
    int startIndex = 0;
    if (lastId != null) {
      int foundIndex = _filteredWords.indexWhere((w) => w.id == lastId);
      if (foundIndex != -1) {
        startIndex = foundIndex;
      }
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => StudyScreen(words: _filteredWords, initialIndex: startIndex)),
    ).then((_) => _loadData());
  }

  Future<void> _pickAndImportExcel() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      result ??= await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (!mounted) return;
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        if (bytes != null) {
          int added = await DatabaseHelper.instance.loadExcelFromBytes(bytes);
          await _loadData();
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text('엑셀에서 $added개의 새로운 단어가 추가되었습니다.')),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('선택한 파일의 내용(바이트)을 읽을 수 없습니다.')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('엑셀 등록 실패: $e')),
      );
    }
  }

  Future<void> _exportExcel() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await DatabaseHelper.instance.exportToExcel();
      if (!mounted) return;
      if (bytes != null) {
        String? path = await FilePicker.platform.saveFile(
          dialogTitle: '엑셀 파일 저장',
          fileName: 'vocabulary_export.xlsx',
          bytes: bytes,
        );
        if (!mounted) return;
        if (path != null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('엑셀 파일이 성공적으로 다운로드되었습니다.')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('엑셀 저장 실패: $e')),
      );
    }
  }

  Future<void> _addOrEditWordDialog({Word? wordToEdit}) async {
    final wordController = TextEditingController(text: wordToEdit?.word ?? '');
    final pronController = TextEditingController(text: wordToEdit?.pronunciation ?? '');
    final meaningController = TextEditingController(text: wordToEdit?.meaning ?? '');
    final vietController = TextEditingController(text: wordToEdit?.vietnamese ?? '');
    final engController = TextEditingController(text: wordToEdit?.english ?? '');
    final grammarController = TextEditingController(text: wordToEdit?.grammar ?? '');
    int status = wordToEdit?.status ?? 0;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              title: Text(wordToEdit == null ? '단어 직접 추가' : '단어 수정', style: const TextStyle(color: Colors.greenAccent)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: wordController, decoration: const InputDecoration(labelText: '스페인어 단어 (Word)')),
                    TextField(controller: pronController, decoration: const InputDecoration(labelText: '발음 (예: [아브리고])')),
                    TextField(controller: meaningController, decoration: const InputDecoration(labelText: '한국어 뜻')),
                    TextField(controller: vietController, decoration: const InputDecoration(labelText: '베트남어')),
                    TextField(controller: engController, decoration: const InputDecoration(labelText: '영어')),
                    TextField(controller: grammarController, decoration: const InputDecoration(labelText: '동사원형/인칭변화')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: status,
                      dropdownColor: const Color(0xFF161B22),
                      decoration: const InputDecoration(labelText: '학습 상태'),
                      items: _statusNames.entries.map((e) {
                        return DropdownMenuItem(value: e.key, child: Text(e.value));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            status = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                if (wordToEdit != null) ...[
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final nav = Navigator.of(context);
                      await DatabaseHelper.instance.deleteWord(wordToEdit.id!);
                      if (!mounted) return;
                      nav.pop();
                      await _loadData();
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('단어가 삭제되었습니다.')),
                      );
                    },
                    child: const Text('삭제'),
                  ),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final nav = Navigator.of(context);
                    final newWord = Word(
                      id: wordToEdit?.id,
                      word: wordController.text.trim(),
                      pronunciation: pronController.text.trim(),
                      meaning: meaningController.text.trim(),
                      vietnamese: vietController.text.trim(),
                      english: engController.text.trim(),
                      grammar: grammarController.text.trim(),
                      status: status,
                    );
                    if (wordToEdit == null) {
                      await DatabaseHelper.instance.insertWord(newWord);
                    } else {
                      await DatabaseHelper.instance.updateWord(newWord);
                    }
                    if (!mounted) return;
                    nav.pop();
                    await _loadData();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('저장되었습니다.')),
                    );
                  },
                  child: const Text('저장', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsMenuButton({bool isMobile = false}) {
    return PopupMenuButton<String>(
      color: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(0, 40),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF21262D),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 6 : 10),
          minimumSize: Size(isMobile ? 36 : 64, isMobile ? 32 : 40),
        ),
        icon: const Icon(Icons.menu, size: 14, color: Colors.greenAccent),
        label: Text('데이타관리', style: TextStyle(fontSize: isMobile ? 11 : 14)),
        onPressed: null,
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              Icon(Icons.upload_file, size: 16, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text('엑셀 파일 등록 (단어 추가)'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.download, size: 16, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text('전체 엑셀 다운로드'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'add',
          child: Row(
            children: [
              Icon(Icons.add, size: 16, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('단어 직접 추가'),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value == 'import') {
          _pickAndImportExcel();
        } else if (value == 'export') {
          _exportExcel();
        } else if (value == 'add') {
          _addOrEditWordDialog();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = screenWidth < 900;
    int totalCount = _allWords.length;

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
            : Column(
                children: [
                  // Top Header
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 12),
                    color: const Color(0xFF161B22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isMobile) ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(6)),
                                child: const Icon(Icons.school, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text('단어 학습', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withValues(alpha: 0.3),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.blueAccent),
                                          ),
                                          child: const Text('Ver 1.0', style: TextStyle(color: Colors.blueAccent, fontSize: 9)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 1),
                                    const Text('스페인어 단어장', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                  ],
                                ),
                              ),
                              _buildSettingsMenuButton(isMobile: true),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.school, color: Colors.white, size: 28),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('단어 학습', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.blueAccent),
                                        ),
                                        child: const Text('Vocabulary Learning Ver 1.0', style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Spacer(),
                              _buildSettingsMenuButton(isMobile: false),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Main Content (Word List)
                  Expanded(
                    child: _buildWordListView(isMobile, totalCount),
                  ),

                  // Footer / Copyright
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'Developer: H2 | Copyright: © 2026.10',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildWordListView(bool isMobile, int totalCount) {
    return Padding(
      padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search & Filters
          if (isMobile) ...[
            TextField(
              decoration: InputDecoration(
                hintText: '단어, 뜻, 발음, 영어 실시간 검색...',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: const Color(0xFF161B22),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
                _loadData();
              },
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterPill('미학습', 0),
                  const SizedBox(width: 6),
                  _buildFilterPill('1주일 후', 1),
                  const SizedBox(width: 6),
                  _buildFilterPill('2주일 후', 2),
                  const SizedBox(width: 6),
                  _buildFilterPill('한달 후', 3),
                  const SizedBox(width: 6),
                  _buildFilterPill('외움 완료', 4),
                  const SizedBox(width: 6),
                  _buildFilterPill('전체', null),
                ],
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '단어, 뜻, 발음, 영어, 베트남어 실시간 검색...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFF161B22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                      _loadData();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterPill('미학습', 0),
                    _buildFilterPill('1주일 후', 1),
                    _buildFilterPill('2주일 후', 2),
                    _buildFilterPill('한달 후', 3),
                    _buildFilterPill('외움 완료', 4),
                    _buildFilterPill('전체', null),
                  ],
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // Action bar above table
          if (isMobile) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('총 ${_filteredWords.length}개 단어 (전체 $totalCount개)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                    icon: const Icon(Icons.play_arrow, size: 12),
                    label: const Text('학습 시작', style: TextStyle(fontSize: 11)),
                    onPressed: _startStudy,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Text('총 ${_filteredWords.length}개의 단어 (전체 $totalCount개)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text('현재 목록 (${_filteredWords.length}개) 학습 시작'),
                    onPressed: _startStudy,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),

          // Word DataTable Container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: _filteredWords.isEmpty
                  ? const Center(child: Text('단어가 없습니다.', style: TextStyle(color: Colors.grey)))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 790.0,
                        child: ListView.separated(
                          itemCount: _filteredWords.length + 1,
                          separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                color: const Color(0xFF21262D),
                                child: const Row(
                                  children: [
                                    SizedBox(width: 150, child: Text('단어 / 발음', style: TextStyle(fontWeight: FontWeight.bold))),
                                    SizedBox(width: 110, child: Text('한국어 뜻', style: TextStyle(fontWeight: FontWeight.bold))),
                                    SizedBox(width: 110, child: Text('베트남어', style: TextStyle(fontWeight: FontWeight.bold))),
                                    SizedBox(width: 110, child: Text('영어', style: TextStyle(fontWeight: FontWeight.bold))),
                                    SizedBox(width: 130, child: Text('동사원형/변화', style: TextStyle(fontWeight: FontWeight.bold))),
                                    SizedBox(width: 100, child: Text('학습 상태', style: TextStyle(fontWeight: FontWeight.bold))),
                                    SizedBox(width: 80, child: Text('관리', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                  ],
                                ),
                              );
                            }
                            final word = _filteredWords[index - 1];
                            return InkWell(
                              onDoubleTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => StudyScreen(words: _filteredWords, initialIndex: index - 1)),
                                ).then((_) => _loadData());
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 150,
                                      child: Row(
                                        children: [
                                          Text(word.word, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.greenAccent)),
                                          const SizedBox(width: 6),
                                          Flexible(child: Text(word.pronunciation.isNotEmpty ? '[${word.pronunciation}]' : '', style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 110, child: Text(word.meaning, style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis)),
                                    SizedBox(width: 110, child: Text(word.vietnamese, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis)),
                                    SizedBox(width: 110, child: Text(word.english, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis)),
                                    SizedBox(width: 130, child: Text(word.grammar, style: const TextStyle(color: Colors.white60), overflow: TextOverflow.ellipsis)),
                                    SizedBox(
                                      width: 100,
                                      child: Chip(
                                        backgroundColor: word.status == 0 ? Colors.orange.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                                        label: Text(_statusNames[word.status] ?? '미학습', style: TextStyle(color: word.status == 0 ? Colors.orangeAccent : Colors.greenAccent, fontSize: 11)),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: IconButton(
                                              icon: const Icon(Icons.edit, size: 18, color: Colors.blueAccent),
                                              onPressed: () => _addOrEditWordDialog(wordToEdit: word),
                                            ),
                                          ),
                                          MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: IconButton(
                                              icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                                              onPressed: () async {
                                                await DatabaseHelper.instance.deleteWord(word.id!);
                                                _loadData();
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, int? status) {
    bool isSelected = _selectedStatusFilter == status;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.grey)),
        selected: isSelected,
        selectedColor: Colors.green,
        backgroundColor: const Color(0xFF161B22),
        onSelected: (selected) {
          setState(() {
            _selectedStatusFilter = selected ? status : null;
          });
          _loadData();
        },
      ),
    );
  }
}

class StudyScreen extends StatefulWidget {
  final List<Word> words;
  final int initialIndex;

  const StudyScreen({super.key, required this.words, required this.initialIndex});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  late int _studyIndex;
  bool _hideWord = false;
  bool _hideMeaning = false;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _studyIndex = widget.initialIndex;
    _saveLastStudiedId(widget.words[_studyIndex].id!);
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("es-ES");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      if (Platform.isIOS) {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.allowAirPlay,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.spokenAudio,
        );
      }
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    }
  }

  Future<void> _saveLastStudiedId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_studied_word_id', id);
  }

  Future<void> _handleStudyAction(int? newStatus) async {
    if (widget.words.isEmpty) return;
    final currentWord = widget.words[_studyIndex];

    if (newStatus != null) {
      await DatabaseHelper.instance.updateWordStatus(currentWord.id!, newStatus);
    }

    if (!mounted) return;

    if (_studyIndex < widget.words.length - 1) {
      setState(() {
        _studyIndex++;
      });
      _saveLastStudiedId(widget.words[_studyIndex].id!);
    } else {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('마지막 학습 단어입니다. 처음 단어로 이동합니다.')),
      );
      setState(() {
        _studyIndex = 0;
      });
      _saveLastStudiedId(widget.words[0].id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isMobile = screenWidth < 900;

    if (widget.words.isEmpty) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.black, title: const Text('단어 학습')),
        body: const Center(child: Text('학습할 단어가 없습니다.', style: TextStyle(color: Colors.grey))),
      );
    }

    if (_studyIndex >= widget.words.length) {
      _studyIndex = 0;
    }
    final word = widget.words[_studyIndex];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Subheader & Toggles
              if (isMobile) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('복습 단어 ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('${_studyIndex + 1}/${widget.words.length}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    Row(
                      children: [
                        FilterChip(
                          label: const Text('단어', style: TextStyle(fontSize: 11)),
                          selected: _hideWord,
                          mouseCursor: SystemMouseCursors.click,
                          onSelected: (val) => setState(() => _hideWord = val),
                        ),
                        const SizedBox(width: 4),
                        FilterChip(
                          label: const Text('뜻', style: TextStyle(fontSize: 11)),
                          selected: _hideMeaning,
                          mouseCursor: SystemMouseCursors.click,
                          onSelected: (val) => setState(() => _hideMeaning = val),
                        ),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('오늘 복습 도래 단어', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 8),
                        Text('${_studyIndex + 1} / ${widget.words.length}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Row(
                      children: [
                        FilterChip(
                          label: const Text('단어 가리기'),
                          selected: _hideWord,
                          mouseCursor: SystemMouseCursors.click,
                          onSelected: (val) => setState(() => _hideWord = val),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('뜻 가리기'),
                          selected: _hideMeaning,
                          mouseCursor: SystemMouseCursors.click,
                          onSelected: (val) => setState(() => _hideMeaning = val),
                        ),
                        const SizedBox(width: 16),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: TextButton.icon(
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('닫기'),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Word Study Card Container
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 700),
                    padding: EdgeInsets.all(isMobile ? 16 : 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Box 1: Word & Pronunciation
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1117),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('단어 & 발음', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _hideWord ? '••••••' : '${word.word} ${word.pronunciation.isNotEmpty ? '[${word.pronunciation}]' : ''}',
                                      style: TextStyle(color: Colors.white, fontSize: isMobile ? 22 : 26, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => _speak(word.word),
                                  child: const Icon(Icons.volume_up, color: Colors.greenAccent, size: 22),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Box 2: Meaning & Grammar
                        if (isMobile) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1117),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('한국어 뜻', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text(
                                  _hideMeaning ? '••••••' : word.meaning,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                                const Divider(height: 16, color: Colors.white10),
                                const Text('동사원형 / 인칭변화', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text(
                                  word.grammar.isNotEmpty ? word.grammar : '-',
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1117),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('한국어 뜻', style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 6),
                                      Text(
                                        _hideMeaning ? '••••••' : word.meaning,
                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1117),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('동사원형 / 인칭변화', style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 6),
                                      Text(
                                        word.grammar.isNotEmpty ? word.grammar : '-',
                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),

                        // Box 3: Vietnamese & English
                        if (isMobile) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1117),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('베트남어', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text(word.vietnamese.isNotEmpty ? word.vietnamese : '-', style: const TextStyle(color: Colors.white, fontSize: 16)),
                                const Divider(height: 16, color: Colors.white10),
                                const Text('영어', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 4),
                                Text(word.english.isNotEmpty ? word.english : '-', style: const TextStyle(color: Colors.white, fontSize: 16)),
                              ],
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1117),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('베트남어', style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 6),
                                      Text(word.vietnamese.isNotEmpty ? word.vietnamese : '-', style: const TextStyle(color: Colors.white, fontSize: 18)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1117),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('영어', style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w500)),
                                      const SizedBox(height: 6),
                                      Text(word.english.isNotEmpty ? word.english : '-', style: const TextStyle(color: Colors.white, fontSize: 18)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),

                        // AI Example sentence box
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F242C),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome, size: 14, color: Colors.blueAccent),
                                  const SizedBox(width: 6),
                                  const Text('인공지능 실생활 예문 (스페인어 A1)', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(foregroundColor: Colors.grey, padding: EdgeInsets.zero),
                                      icon: const Icon(Icons.refresh, size: 12),
                                      label: const Text('새로고침', style: TextStyle(fontSize: 11)),
                                      onPressed: () {},
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('1. Vamos a practicar ${word.word} juntos hoy.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 14 : 15)),
                                        const SizedBox(height: 2),
                                        Text('오늘 같이 ${word.meaning}(을) 연습해봐요. (A1)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () => _speak('Vamos a practicar ${word.word} juntos hoy.'),
                                      child: const Icon(Icons.volume_up, size: 18, color: Colors.blueAccent),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Action Buttons
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B2323),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _handleStudyAction(0),
                          child: const Text('다시', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1F3A60),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _handleStudyAction(null),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.arrow_forward, size: 16),
                              SizedBox(width: 4),
                              Text('다음', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B4D3E),
                            foregroundColor: Colors.greenAccent,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            int nextStatus = word.status < 4 ? word.status + 1 : 4;
                            _handleStudyAction(nextStatus);
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 16),
                              SizedBox(width: 4),
                              Text('외움', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
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
    );
  }
}
