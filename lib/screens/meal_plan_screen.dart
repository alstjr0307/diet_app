import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';

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
  Map<String, dynamic>? _mealPlan;
  bool _isLoadingPlan = false;
  String _planErrorMessage = "";

  Future<void> _generateMealPlan() async {
    setState(() {
      _isLoadingPlan = true;
      _planErrorMessage = "";
      _mealPlan = null;
    });

    try {
      final model = GenerativeModel(model: 'gemini-3-flash-preview', apiKey: widget.apiKey);

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

      String userContext =
          "키 ${widget.userHeight}cm, 나이 ${widget.userAge}세, ${widget.userGender}, 체중 ${widget.currentWeight}kg, 목표 칼로리 ${widget.targetKcal}kcal.";
      if (topPreferredFoods.isNotEmpty) {
        userContext += " 선호 음식: $topPreferredFoods.";
      }

      final prompt = '''
너는 개인 식단 플래너 AI야. 아래 사용자 정보를 바탕으로 하루 식단을 추천해줘.

사용자 정보: $userContext

칼로리 규칙 (반드시 지켜야 함):
- 아침 + 점심 + 저녁 + 간식의 총 칼로리 합계가 목표 칼로리(${widget.targetKcal}kcal)를 넘으면 절대 안 됨
- 각 끼니별 칼로리를 정확히 계산해서 넣어줘
- 목표 칼로리의 ±100kcal 이내로 맞춰줘

반드시 아래 JSON 형식으로만 답해. 다른 말은 절대 하지 마.
{
  "아침": {"foods": ["음식1 (칼로리kcal)", "음식2 (칼로리kcal)"], "reason": "추천 이유 한 줄", "kcal": 숫자},
  "점심": {"foods": ["음식1 (칼로리kcal)", "음식2 (칼로리kcal)"], "reason": "추천 이유 한 줄", "kcal": 숫자},
  "저녁": {"foods": ["음식1 (칼로리kcal)", "음식2 (칼로리kcal)"], "reason": "추천 이유 한 줄", "kcal": 숫자},
  "간식": {"foods": ["음식1 (칼로리kcal)"], "reason": "추천 이유 한 줄", "kcal": 숫자}
}
''';

      final response = await model.generateContent([Content.text(prompt)]);
      String raw = response.text ?? "{}";
      raw = raw
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();

      setState(() {
        _mealPlan = jsonDecode(raw);
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

  Widget _buildMealCard(String mealTime, Map<String, dynamic> data) {
    final Map<String, Map<String, dynamic>> mealMeta = {
      '아침': {'icon': Icons.wb_sunny_outlined, 'color': Colors.orange},
      '점심': {'icon': Icons.lunch_dining, 'color': Colors.green},
      '저녁': {'icon': Icons.nights_stay_outlined, 'color': Colors.indigo},
      '간식': {'icon': Icons.cookie_outlined, 'color': Colors.brown},
    };

    final meta = mealMeta[mealTime] ?? {'icon': Icons.restaurant, 'color': Colors.grey};
    final color = meta['color'] as Color;
    final icon = meta['icon'] as IconData;
    final foods = (data['foods'] as List<dynamic>?) ?? [];
    final reason = data['reason'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      mealTime,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                if (data['kcal'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${data['kcal']} kcal',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ...foods.map((food) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 15)),
                      Expanded(
                        child: Text(food.toString(), style: const TextStyle(fontSize: 15)),
                      ),
                    ],
                  ),
                )),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 15, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
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

  Widget _buildTotalKcalBanner() {
    final meals = ['아침', '점심', '저녁', '간식'];
    int total = 0;
    for (final meal in meals) {
      if (_mealPlan!.containsKey(meal)) {
        total += ((_mealPlan![meal]['kcal'] ?? 0) as num).toInt();
      }
    }
    final bool overTarget = total > widget.targetKcal;
    final color = overTarget ? Colors.red : Colors.green;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('총 칼로리', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          Text(
            '$total / ${widget.targetKcal} kcal',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
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
          'AI 식단 추천 ✨',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        elevation: 0,
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (_planErrorMessage.isNotEmpty)
              Text(_planErrorMessage, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: _mealPlan == null
                  ? const Center(
                      child: Text(
                        "버튼을 눌러 AI가 추천하는 맞춤 식단을 받아보세요!",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildTotalKcalBanner(),
                          ...['아침', '점심', '저녁', '간식']
                              .where((meal) => _mealPlan!.containsKey(meal))
                              .map((meal) => _buildMealCard(meal, _mealPlan![meal])),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
