import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  runApp(const DietApp());
}

class DietApp extends StatelessWidget {
  const DietApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 칼로리 계산기',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const DietScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DietScreen extends StatefulWidget {
  const DietScreen({super.key});

  @override
  State<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends State<DietScreen> {
  final TextEditingController _controller = TextEditingController();

  Map<String, dynamic> _history = {};
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  String _errorMessage = "";
  bool _isNightSnack = false;

  int _totalKcal = 0;
  int _targetKcal = 2400;
  double _currentWeight = 70.0;

  double _userHeight = 170.0;
  int _userAge = 30;
  String _userGender = '남성';

  int _totalCarbs = 0;
  int _totalProtein = 0;
  int _totalFat = 0;

  double _estimatedWeightChange = 0.0;

  final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  String get _dateKey =>
      "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
  List<dynamic> get _currentFoods => _history[_dateKey] ?? [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyString = prefs.getString('diet_history_v2');
    if (historyString != null) {
      try {
        final decodedData = jsonDecode(historyString);
        if (decodedData is Map<String, dynamic>) {
          setState(() {
            _history = decodedData;
          });
        } else {
          print("Error decoding diet_history_v2: Stored data is not a Map.");
          await prefs.remove('diet_history_v2');
          setState(() {
            _history = {};
          });
        }
      } catch (e) {
        print("Error decoding diet_history_v2: $e");
        await prefs.remove('diet_history_v2');
        setState(() {
          _history = {};
        });
      }
    }
    setState(() {
      _targetKcal = prefs.getInt('targetKcal') ?? 2400;
      _currentWeight = prefs.getDouble('currentWeight') ?? 70.0;
      _userHeight = prefs.getDouble('userHeight') ?? 170.0;
      _userAge = prefs.getInt('userAge') ?? 30;
      _userGender = prefs.getString('userGender') ?? '남성';
      _calculateTotal();
      _calculateEstimatedWeightChange();
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('diet_history_v2', jsonEncode(_history));
    await prefs.setInt('targetKcal', _targetKcal);
    await prefs.setDouble('currentWeight', _currentWeight);
    await prefs.setDouble('userHeight', _userHeight);
    await prefs.setInt('userAge', _userAge);
    await prefs.setString('userGender', _userGender);
  }

  void _calculateTotal() {
    int sumKcal = 0;
    int sumCarbs = 0;
    int sumProtein = 0;
    int sumFat = 0;

    for (var item in _currentFoods) {
      sumKcal += (item["kcal"] as num).toInt();
      sumCarbs += (item["carbs"] as num).toInt();
      sumProtein += (item["protein"] as num).toInt();
      sumFat += (item["fat"] as num).toInt();
    }
    setState(() {
      _totalKcal = sumKcal;
      _totalCarbs = sumCarbs;
      _totalProtein = sumProtein;
      _totalFat = sumFat;
      _calculateEstimatedWeightChange();
    });
  }

  double _calculateBMR() {
    if (_userGender == '남성') {
      return (10 * _currentWeight) + (6.25 * _userHeight) - (5 * _userAge) + 5;
    } else {
      return (10 * _currentWeight) +
          (6.25 * _userHeight) -
          (5 * _userAge) -
          161;
    }
  }

  void _calculateEstimatedWeightChange() {
    double bmr = _calculateBMR();
    double tdee = bmr * 1.2;
    double calorieDifference = _totalKcal - tdee;
    _estimatedWeightChange = calorieDifference / 7700;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _calculateTotal();
      });
    }
  }

  Future<void> analyzeDiet() async {
    if (_controller.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final model = GenerativeModel(model: 'gemini-pro', apiKey: apiKey);

      final prompt =
          '''
      너는 영양 분석 AI야. 사용자가 먹은 음식을 자연어로 입력하면, 
      칼로리와 영양성분을 무조건 아래 JSON 형식으로만 답해. 다른 말은 절대 하지 마.
      만약 입력된 내용에서 음식을 찾을 수 없거나 분석이 불가능하면 빈 리스트 []만 반환해.
      형식: [{"food": "이름", "amount": "양", "kcal": 숫자, "carbs": 숫자, "protein": 숫자, "fat": 숫자}]
      
      사용자 입력: ${_controller.text}
      ''';

      final response = await model.generateContent([Content.text(prompt)]);

      print('Raw AI Response: ${response.text}');

      String cleanText =
          response.text?.replaceAll('''json', '').replaceAll(''', '').trim() ??
          "[]";

      print('Cleaned AI Response: $cleanText');

      List<dynamic> newFoods = jsonDecode(cleanText);

      setState(() {
        if (newFoods.isEmpty) {
          _errorMessage = "음식을 인식하지 못했습니다. 구체적으로 입력해 주세요!";
          return;
        }

        for (var food in newFoods) {
          food['isNightSnack'] = _isNightSnack;
        }

        List<dynamic> updatedList = List.from(_currentFoods);
        updatedList.addAll(newFoods);
        _history[_dateKey] = updatedList;

        _calculateTotal();
        _controller.clear();
        _isNightSnack = false;
        _saveData();
      });
    } catch (e) {
      setState(() {
        _errorMessage =
            "분석 중 오류가 발생했어요. API 키, 네트워크 연결 또는 모델 응답을 확인해주세요! 오류: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildNutrient(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _navigateToSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          initialTargetKcal: _targetKcal,
          initialCurrentWeight: _currentWeight,
          initialUserHeight: _userHeight,
          initialUserAge: _userAge,
          initialUserGender: _userGender,
        ),
      ),
    );
    _loadData();
  }

  void _navigateToChatScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          currentHistory: _history,
          userHeight: _userHeight,
          userAge: _userAge,
          userGender: _userGender,
          currentWeight: _currentWeight,
          targetKcal: _targetKcal,
          apiKey: apiKey,
        ),
      ),
    );
  }

  void _navigateToReportScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ReportScreen(history: _history, targetKcal: _targetKcal),
      ),
    );
  }

  void _navigateToMealPlanScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MealPlanScreen(
          history: _history,
          targetKcal: _targetKcal,
          userHeight: _userHeight,
          userAge: _userAge,
          userGender: _userGender,
          currentWeight: _currentWeight,
          apiKey: apiKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double progress = _targetKcal > 0 ? _totalKcal / _targetKcal : 0.0;
    if (progress > 1.0) progress = 1.0;

    String todayStr =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
    String weightChangeText = _estimatedWeightChange > 0
        ? '+${_estimatedWeightChange.toStringAsFixed(2)} kg 예상'
        : '${_estimatedWeightChange.toStringAsFixed(2)} kg 예상';
    Color weightChangeColor = _estimatedWeightChange > 0
        ? Colors.red
        : Colors.blueAccent;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI 다이어트 코치 🥗',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _selectDate(context),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: _navigateToChatScreen,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: _navigateToReportScreen,
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_menu_outlined),
            onPressed: _navigateToMealPlanScreen,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.green),
                    onPressed: () {
                      setState(() {
                        _selectedDate = _selectedDate.subtract(
                          const Duration(days: 1),
                        );
                        _calculateTotal();
                      });
                    },
                  ),
                  GestureDetector(
                    onTap: () => _selectDate(context),
                    child: Text(
                      _dateKey == todayStr ? "오늘 ($_dateKey)" : _dateKey,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.green),
                    onPressed: () {
                      setState(() {
                        _selectedDate = _selectedDate.add(
                          const Duration(days: 1),
                        );
                        _calculateTotal();
                      });
                    },
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "섭취량 / 목표량",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "$_totalKcal / $_targetKcal kcal",
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_currentFoods.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "예상 체중 변화 (일)",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          weightChangeText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: weightChangeColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _totalKcal > _targetKcal ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNutrient('총 탄수화물', '$_totalCarbs g', Colors.orange),
                      _buildNutrient(
                        '총 단백질',
                        '$_totalProtein g',
                        Colors.blueAccent,
                      ),
                      _buildNutrient(
                        '총 지방',
                        '$_totalFat g',
                        Colors.purpleAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "무엇을 드셨나요? (예: 제육볶음 1인분)",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.restaurant_menu,
                  color: Colors.green,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    '🌙 야식 여부',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Switch(
                    value: _isNightSnack,
                    onChanged: (value) {
                      setState(() {
                        _isNightSnack = value;
                      });
                    },
                    activeThumbColor: Colors.orangeAccent,
                  ),
                ],
              ),
            ),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isLoading ? null : analyzeDiet,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        '음식 추가하기 ➕',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            if (_errorMessage.isNotEmpty)
              Text(_errorMessage, style: const TextStyle(color: Colors.red)),

            Expanded(
              child: _currentFoods.isEmpty
                  ? const Center(
                      child: Text(
                        "이 날의 식단 기록이 없습니다.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _currentFoods.length,
                      itemBuilder: (context, index) {
                        final item = _currentFoods.reversed.toList()[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '🍽️ ${item["food"]}',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (item["isNightSnack"] == true) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.orangeAccent,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                '야식',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${item["amount"]}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20, thickness: 1),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildNutrient(
                                      '칼로리',
                                      '${item["kcal"]} kcal',
                                      Colors.redAccent,
                                    ),
                                    _buildNutrient(
                                      '탄수화물',
                                      '${item["carbs"]} g',
                                      Colors.orange,
                                    ),
                                    _buildNutrient(
                                      '단백질',
                                      '${item["protein"]} g',
                                      Colors.blueAccent,
                                    ),
                                    _buildNutrient(
                                      '지방',
                                      '${item["fat"]} g',
                                      Colors.purpleAccent,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final int initialTargetKcal;
  final double initialCurrentWeight;
  final double initialUserHeight;
  final int initialUserAge;
  final String initialUserGender;

  const SettingsScreen({
    super.key,
    required this.initialTargetKcal,
    required this.initialCurrentWeight,
    required this.initialUserHeight,
    required this.initialUserAge,
    required this.initialUserGender,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _targetKcalController;
  late TextEditingController _currentWeightController;
  late TextEditingController _userHeightController;
  late TextEditingController _userAgeController;
  late String _selectedGender;

  @override
  void initState() {
    super.initState();
    _targetKcalController = TextEditingController(
      text: widget.initialTargetKcal.toString(),
    );
    _currentWeightController = TextEditingController(
      text: widget.initialCurrentWeight.toString(),
    );
    _userHeightController = TextEditingController(
      text: widget.initialUserHeight.toString(),
    );
    _userAgeController = TextEditingController(
      text: widget.initialUserAge.toString(),
    );
    _selectedGender = widget.initialUserGender;
  }

  @override
  void dispose() {
    _targetKcalController.dispose();
    _currentWeightController.dispose();
    _userHeightController.dispose();
    _userAgeController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'targetKcal',
      int.tryParse(_targetKcalController.text) ?? widget.initialTargetKcal,
    );
    await prefs.setDouble(
      'currentWeight',
      double.tryParse(_currentWeightController.text) ??
          widget.initialCurrentWeight,
    );
    await prefs.setDouble(
      'userHeight',
      double.tryParse(_userHeightController.text) ?? widget.initialUserHeight,
    );
    await prefs.setInt(
      'userAge',
      int.tryParse(_userAgeController.text) ?? widget.initialUserAge,
    );
    await prefs.setString('userGender', _selectedGender);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '개인 설정',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _targetKcalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '목표 칼로리 (kcal)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flash_on),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _currentWeightController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '현재 체중 (kg)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.monitor_weight),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _userHeightController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '키 (cm)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.height),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _userAgeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '나이 (세)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cake),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('성별: ', style: TextStyle(fontSize: 16)),
                DropdownButton<String>(
                  value: _selectedGender,
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedGender = newValue!;
                    });
                  },
                  items: <String>['남성', '여성'].map<DropdownMenuItem<String>>((
                    String value,
                  ) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _saveSettings,
                child: const Text(
                  '설정 저장',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> currentHistory;
  final double userHeight;
  final int userAge;
  final String userGender;
  final double currentWeight;
  final int targetKcal;
  final String apiKey;

  const ChatScreen({
    super.key,
    required this.currentHistory,
    required this.userHeight,
    required this.userAge,
    required this.userGender,
    required this.currentWeight,
    required this.targetKcal,
    required this.apiKey,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'sender': 'AI',
      'text':
          '안녕하세요! 당신의 식단과 건강에 대해 무엇이든 물어보세요.\n'
          '저는 당신의 키 ${widget.userHeight}cm, 나이 ${widget.userAge}세, ${widget.userGender}, '
          '현재 체중 ${widget.currentWeight}kg, 목표 칼로리 ${widget.targetKcal}kcal 정보를 알고 있습니다. '
          '오늘 식단 기록을 기반으로 조언을 드릴 수 있습니다.',
    });
  }

  Future<void> _sendMessage() async {
    if (_chatController.text.isEmpty || _isSending) return;

    final userMessage = _chatController.text;
    setState(() {
      _messages.add({'sender': 'User', 'text': userMessage});
      _chatController.clear();
      _isSending = true;
    });

    try {
      final model = GenerativeModel(model: 'gemini-pro', apiKey: widget.apiKey);

      String contextPrompt = "";
      contextPrompt +=
          "사용자 정보: 키 ${widget.userHeight}cm, 나이 ${widget.userAge}세, ${widget.userGender}, 현재 체중 ${widget.currentWeight}kg, 목표 칼로리 ${widget.targetKcal}kcal.\n";

      String todayDateKey =
          "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
      List<dynamic> todayFoods = widget.currentHistory[todayDateKey] ?? [];
      if (todayFoods.isNotEmpty) {
        contextPrompt += "오늘의 식단 기록:\n";
        for (var food in todayFoods) {
          contextPrompt +=
              "- ${food['food']} ${food['amount']} (${food['kcal']}kcal, 탄${food['carbs']}g, 단${food['protein']}g, 지${food['fat']}g) ${food['isNightSnack'] == true ? '(야식)' : ''}\n";
        }
      } else {
        contextPrompt += "오늘의 식단 기록: 없음.\n";
      }
      contextPrompt +=
          "이전 대화: ${_messages.where((m) => m['sender'] == 'User').map((m) => m['text']).join(' | ')}.\n";

      final prompt =
          '''
      너는 개인 영양 코치 AI야. 다음 사용자 정보와 식단 기록을 바탕으로 사용자의 질문에 답변하고, 
      건강하고 동기 부여가 되는 조언을 제공해. 사용자의 질문에 대해 친근하고 유용한 방식으로 응답해줘.
      JSON 형식으로 답변하지 말고, 자연스러운 한국어 대화체로 답변해.

      $contextPrompt
      사용자 질문: $userMessage
      ''';

      final response = await model.generateContent([Content.text(prompt)]);
      final aiResponse = response.text ?? "죄송합니다. 답변을 생성하지 못했습니다.";

      setState(() {
        _messages.add({'sender': 'AI', 'text': aiResponse});
      });
    } catch (e) {
      setState(() {
        _messages.add({'sender': 'AI', 'text': "오류가 발생했습니다: $e"});
      });
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI 다이어트 코치 💬',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['sender'] == 'User';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5.0),
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.green[100] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    child: Text(message['text']!),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    decoration: InputDecoration(
                      hintText: 'AI 코치에게 질문하세요...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8.0),
                _isSending
                    ? const CircularProgressIndicator()
                    : FloatingActionButton(
                        onPressed: _sendMessage,
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        child: const Icon(Icons.send),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReportScreen extends StatefulWidget {
  final Map<String, dynamic> history;
  final int targetKcal;

  const ReportScreen({
    super.key,
    required this.history,
    required this.targetKcal,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _selectedRange = '7일'; // '7일', '1개월', '3개월'
  final Map<String, int> _dailyCaloriesMap = {};
  int _maxKcalValue = 0;
  final List<FlSpot> _spots = [];
  final List<String> _graphDateKeys = []; // 그래프 x-axis labels
  final List<String> _last7DaysKeysForList = []; // 하단 리스트를 위한 최근 7일 데이터

  @override
  void initState() {
    super.initState();
    _prepareChartData();
    _prepareLast7DaysListData(); // 하단 리스트 데이터 준비
  }

  void _prepareChartData() {
    _dailyCaloriesMap.clear();
    _spots.clear();
    _graphDateKeys.clear();

    DateTime endDate = DateTime.now();
    DateTime startDate;
    int numberOfDays;

    if (_selectedRange == '7일') {
      numberOfDays = 7;
    } else if (_selectedRange == '1개월') {
      numberOfDays = 30;
    } else {
      // '3개월'
      numberOfDays = 90;
    }
    startDate = endDate.subtract(Duration(days: numberOfDays - 1));

    List<DateTime> datesInRange = [];
    for (int i = 0; i < numberOfDays; i++) {
      datesInRange.add(startDate.add(Duration(days: i)));
    }

    int currentMaxKcal = widget.targetKcal;

    for (int i = 0; i < datesInRange.length; i++) {
      DateTime date = datesInRange[i];
      String dateKey =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      _graphDateKeys.add(dateKey);

      List<dynamic> dailyFoods = widget.history[dateKey] ?? [];
      int total = 0;
      for (var food in dailyFoods) {
        total += (food['kcal'] as num).toInt();
      }
      _dailyCaloriesMap[dateKey] = total;
      _spots.add(FlSpot(i.toDouble(), total.toDouble()));

      if (total > currentMaxKcal) {
        currentMaxKcal = total;
      }
    }

    setState(() {
      _maxKcalValue = currentMaxKcal;
    });
  }

  // 🌟 하단 리스트를 위한 최근 7일 데이터 준비 함수
  void _prepareLast7DaysListData() {
    _last7DaysKeysForList.clear();
    for (int i = 6; i >= 0; i--) {
      DateTime date = DateTime.now().subtract(Duration(days: i));
      _last7DaysKeysForList.add(
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}",
      );
    }
  }

  void _showDailyFoodsDialog(
    BuildContext context,
    String dateKey,
    List<dynamic> foods,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('$dateKey 식단 상세'),
          content: SingleChildScrollView(
            child: foods.isEmpty
                ? const Text("기록된 음식이 없습니다.")
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: foods
                        .map(
                          (food) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(
                              '- ${food["food"]} ${food["amount"]} (\n'
                              '  ${food["kcal"]}kcal, 탄${food["carbs"]}g, 단${food["protein"]}g, 지${food["fat"]}g)'
                              '${(food["isNightSnack"] == true ? " (야식)" : "")}',
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '섭취 칼로리 리포트 📊',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🌟 날짜 범위 선택 버튼
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: '7일', label: Text('7일')),
                ButtonSegment<String>(value: '1개월', label: Text('1개월')),
                ButtonSegment<String>(value: '3개월', label: Text('3개월')),
              ],
              selected: <String>{_selectedRange},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _selectedRange = newSelection.first;
                  _prepareChartData(); // 그래프 데이터만 다시 준비
                });
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Colors.green,
                selectedForegroundColor: Colors.white,
                foregroundColor: Colors.green,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '$_selectedRange간 칼로리 섭취량 추이',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 1.70,
              child: Padding(
                padding: const EdgeInsets.only(
                  right: 18,
                  left: 12,
                  top: 24,
                  bottom: 12,
                ),
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: 500,
                      verticalInterval: 1,
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          // 🌟 날짜 범위에 따른 동적 간격 조정
                          interval: _selectedRange == '7일'
                              ? 1
                              : (_selectedRange == '1개월' ? 5 : 15),
                          getTitlesWidget: (value, meta) {
                            int index = value.toInt();
                            if (index < 0 || index >= _graphDateKeys.length)
                              return const Text('');
                            String dateKey = _graphDateKeys[index];
                            DateTime date = DateTime.parse(dateKey);
                            String label = '';
                            if (_selectedRange == '3개월') {
                              if (date.day == 1 ||
                                  index == 0 ||
                                  index == _graphDateKeys.length - 1) {
                                // 매월 1일, 처음과 끝은 항상 표시
                                label = '${date.month}월';
                              } else {
                                return const Text('');
                              }
                            } else {
                              label =
                                  '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
                            }
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              space: 8.0,
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1000,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              '${(value / 1000).toStringAsFixed(0)}k',
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                          reservedSize: 42,
                        ),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: const Color(0xff37434d)),
                    ),
                    minX: 0,
                    maxX: (_graphDateKeys.length - 1).toDouble(),
                    minY: 0,
                    maxY: _maxKcalValue.toDouble() * 1.2,
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _spots,
                        isCurved: true,
                        gradient: LinearGradient(
                          colors: [Colors.green.withOpacity(0.5), Colors.green],
                        ),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.withOpacity(0.3),
                              Colors.green.withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                      LineChartBarData(
                        spots: [
                          FlSpot(0, widget.targetKcal.toDouble()),
                          FlSpot(
                            (_graphDateKeys.length - 1).toDouble(),
                            widget.targetKcal.toDouble(),
                          ),
                        ],
                        isCurved: false,
                        color: Colors.redAccent.withOpacity(0.7),
                        barWidth: 1,
                        dotData: const FlDotData(show: false),
                        dashArray: [5, 5],
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              '최근 7일간 섭취 상세', // 🌟 텍스트 변경
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _last7DaysKeysForList.length, // 🌟 항상 7일 데이터 사용
              itemBuilder: (context, index) {
                String dateKey = _last7DaysKeysForList[index];
                List<dynamic> dailyFoods = widget.history[dateKey] ?? [];
                int dailyTotalKcal =
                    _dailyCaloriesMap[dateKey] ??
                    0; // 🌟 _dailyCaloriesMap에서 가져옴

                double progress = widget.targetKcal > 0
                    ? dailyTotalKcal / widget.targetKcal
                    : 0.0;
                if (progress > 1.0) progress = 1.0;

                return GestureDetector(
                  onTap: () =>
                      _showDailyFoodsDialog(context, dateKey, dailyFoods),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateKey ==
                                    "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}"
                                ? '오늘'
                                : dateKey,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('섭취 칼로리: $dailyTotalKcal kcal'),
                              Text('목표: ${widget.targetKcal} kcal'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 10,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                dailyTotalKcal > widget.targetKcal
                                    ? Colors.redAccent
                                    : Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class MealPlanScreen extends StatefulWidget {
  final Map<String, dynamic> history;
  final int targetKcal;
  final double userHeight;
  final int userAge;
  final String userGender;
  final double currentWeight;
  final String apiKey;

  const MealPlanScreen({
    super.key,
    required this.history,
    required this.targetKcal,
    required this.userHeight,
    required this.userAge,
    required this.userGender,
    required this.currentWeight,
    required this.apiKey,
  });

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  final List<String> _mealPlan = [];
  bool _isLoadingPlan = false;
  String _planErrorMessage = "";

  Future<void> _generateMealPlan() async {
    setState(() {
      _isLoadingPlan = true;
      _planErrorMessage = "";
      _mealPlan.clear();
    });

    try {
      final model = GenerativeModel(model: 'gemini-pro', apiKey: widget.apiKey);

      Map<String, int> foodFrequency = {};
      widget.history.forEach((date, foods) {
        for (var food in foods) {
          String foodName = food['food'].toString().split(' ')[0];
          foodFrequency[foodName] = (foodFrequency[foodName] ?? 0) + 1;
        }
      });
      List<MapEntry<String, int>> preferredFoods =
          foodFrequency.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

      String topPreferredFoods = preferredFoods
          .take(3)
          .map((e) => e.key)
          .join(', ');

      String userContext = "";
      userContext +=
          "사용자 정보: 키 ${widget.userHeight}cm, 나이 ${widget.userAge}세, ${widget.userGender}, 현재 체중 ${widget.currentWeight}kg, 목표 칼로리 ${widget.targetKcal}kcal.\n";
      if (topPreferredFoods.isNotEmpty) {
        userContext += "선호하는 음식 (과거 기록 기반): $topPreferredFoods.\n";
      }
      userContext +=
          "식단은 아침, 점심, 저녁, 간식으로 구성해줘. 각 식단별로 음식명과 대략적인 칼로리를 포함해줘. 총 칼로리는 목표 칼로리를 넘지 않게 조절해줘.\n";
      userContext += "각 음식에 대한 간단한 설명이나 팁도 포함해줘.\n";

      final prompt =
          '''
      너는 개인 식단 플래너 AI야. 다음 사용자 정보와 선호도를 바탕으로 
      하루치 건강한 식단을 한국어로 추천해줘. JSON 형식으로 답하지 마.
      
      $userContext
      ''';

      final response = await model.generateContent([Content.text(prompt)]);
      final aiResponse = response.text ?? "식단을 생성하지 못했습니다.";

      setState(() {
        _mealPlan.add(aiResponse);
      });
    } catch (e) {
      setState(() {
        _planErrorMessage = "식단 생성 중 오류가 발생했습니다: $e";
      });
    } finally {
      setState(() {
        _isLoadingPlan = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI 맞춤 식단 추천 🍽️',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isLoadingPlan ? null : _generateMealPlan,
                child: _isLoadingPlan
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        '오늘의 식단 추천받기 ✨',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (_planErrorMessage.isNotEmpty)
              Text(
                _planErrorMessage,
                style: const TextStyle(color: Colors.red),
              ),
            Expanded(
              child: _mealPlan.isEmpty
                  ? const Center(
                      child: Text(
                        "버튼을 눌러 AI가 추천하는 맞춤 식단을 받아보세요!",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _mealPlan
                            .map(
                              (plan) => Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    plan,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
