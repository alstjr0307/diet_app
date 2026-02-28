import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/settings_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/report_screen.dart';
import 'screens/meal_plan_screen.dart';

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
  double _activityLevel = 1.2;
  int _currentTabIndex = 0;

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
          await prefs.remove('diet_history_v2');
          setState(() {
            _history = {};
          });
        }
      } catch (e) {
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
      _activityLevel = prefs.getDouble('activityLevel') ?? 1.2;
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
    double tdee = bmr * _activityLevel;
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
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

      final prompt =
          '''
      너는 영양 분석 AI야. 사용자가 먹은 음식을 자연어로 입력하면, 
      칼로리와 영양성분을 무조건 아래 JSON 형식으로만 답해. 다른 말은 절대 하지 마.
      만약 입력된 내용에서 음식을 찾을 수 없거나 분석이 불가능하면 빈 리스트 []만 반환해.
      형식: [{"food": "이름", "amount": "양", "kcal": 숫자, "carbs": 숫자, "protein": 숫자, "fat": 숫자}]
      
      사용자 입력: ${_controller.text}
      ''';

      final response = await model.generateContent([Content.text(prompt)]);

      String cleanText = response.text ?? "[]";
      cleanText = cleanText
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();

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

  Widget _buildHomeTab() {
    double progress = _targetKcal > 0 ? _totalKcal / _targetKcal : 0.0;
    if (progress > 1.0) progress = 1.0;

    String todayStr =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
    String weightChangeText = _estimatedWeightChange > 0
        ? '+${_estimatedWeightChange.toStringAsFixed(2)} kg 예상'
        : '${_estimatedWeightChange.toStringAsFixed(2)} kg 예상';
    Color weightChangeColor =
        _estimatedWeightChange > 0 ? Colors.red : Colors.blueAccent;

    return SingleChildScrollView(
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
                      _selectedDate =
                          _selectedDate.subtract(const Duration(days: 1));
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
                      _selectedDate =
                          _selectedDate.add(const Duration(days: 1));
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
                  color: Colors.grey.withValues(alpha: 0.2),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                            fontSize: 16, fontWeight: FontWeight.bold),
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
                    _buildNutrient('총 단백질', '$_totalProtein g', Colors.blueAccent),
                    _buildNutrient('총 지방', '$_totalFat g', Colors.purpleAccent),
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
              prefixIcon: const Icon(Icons.restaurant_menu, color: Colors.green),
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
                  onChanged: (value) => setState(() => _isNightSnack = value),
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
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      '음식 추가하기 ➕',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          if (_errorMessage.isNotEmpty)
            Text(_errorMessage, style: const TextStyle(color: Colors.red)),

          if (_currentFoods.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  "이 날의 식단 기록이 없습니다.",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _currentFoods.length,
              itemBuilder: (context, index) {
                final reversedList = _currentFoods.reversed.toList();
                final item = reversedList[index];
                return Dismissible(
                  key: Key('food_${_dateKey}_$index'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    setState(() {
                      final updated = List<dynamic>.from(reversedList);
                      updated.removeAt(index);
                      _history[_dateKey] = updated.reversed.toList();
                      _calculateTotal();
                      _saveData();
                    });
                  },
                  child: Card(
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
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
                                    fontSize: 14, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          const Divider(height: 20, thickness: 1),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildNutrient(
                                  '칼로리', '${item["kcal"]} kcal', Colors.redAccent),
                              _buildNutrient(
                                  '탄수화물', '${item["carbs"]} g', Colors.orange),
                              _buildNutrient(
                                  '단백질', '${item["protein"]} g', Colors.blueAccent),
                              _buildNutrient(
                                  '지방', '${item["fat"]} g', Colors.purpleAccent),
                            ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
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
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildHomeTab(),
          ChatScreen(
            currentHistory: _history,
            userHeight: _userHeight,
            userAge: _userAge,
            userGender: _userGender,
            currentWeight: _currentWeight,
            targetKcal: _targetKcal,
            apiKey: apiKey,
          ),
          ReportScreen(history: _history, targetKcal: _targetKcal),
          MealPlanScreen(
            history: _history,
            targetKcal: _targetKcal,
            userHeight: _userHeight,
            userAge: _userAge,
            userGender: _userGender,
            currentWeight: _currentWeight,
            apiKey: apiKey,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentTabIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline), label: '채팅'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: '리포트'),
          BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_menu_outlined), label: '식단추천'),
        ],
      ),
    );
  }
}
