import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // 입력값
  String _selectedGender = '남성';
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  double _activityLevel = 1.2;

  int _calculatedBmr = 0;
  int _calculatedTdee = 0;

  final List<Map<String, dynamic>> _activityLevels = [
    {'label': '주로 앉아서 생활', 'sub': '사무직, 재택근무', 'value': 1.2, 'icon': Icons.chair_outlined},
    {'label': '가벼운 활동', 'sub': '산책, 스트레칭', 'value': 1.375, 'icon': Icons.directions_walk},
    {'label': '규칙적인 운동', 'sub': '헬스, 조깅 등 주 3~5회', 'value': 1.55, 'icon': Icons.fitness_center},
    {'label': '고강도 운동', 'sub': '매일 운동 또는 육체 노동', 'value': 1.725, 'icon': Icons.sports_martial_arts},
  ];

  @override
  void initState() {
    super.initState();
    _heightController.addListener(_recalculate);
    _weightController.addListener(_recalculate);
    _ageController.addListener(_recalculate);
    _recalculate();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _recalculate() {
    final weight = double.tryParse(_weightController.text) ?? 0;
    final height = double.tryParse(_heightController.text) ?? 0;
    final age = int.tryParse(_ageController.text) ?? 0;
    if (weight <= 0 || height <= 0 || age <= 0) return;

    double bmr;
    if (_selectedGender == '남성') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    }

    setState(() {
      _calculatedBmr = bmr.round();
      _calculatedTdee = (bmr * _activityLevel).round();
    });
  }

  Future<void> _saveAndStart() async {
    final height = double.tryParse(_heightController.text) ?? 170.0;
    final weight = double.tryParse(_weightController.text) ?? 70.0;
    final age = int.tryParse(_ageController.text) ?? 30;

    final double bmr = _selectedGender == '남성'
        ? (10 * weight) + (6.25 * height) - (5 * age) + 5
        : (10 * weight) + (6.25 * height) - (5 * age) - 161;
    final int tdee = (bmr * _activityLevel).round();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('userHeight', height);
    await prefs.setDouble('currentWeight', weight);
    await prefs.setInt('userAge', age);
    await prefs.setString('userGender', _selectedGender);
    await prefs.setDouble('activityLevel', _activityLevel);
    await prefs.setInt('targetKcal', tdee > 0 ? tdee : 2000);
    await prefs.setBool('onboardingComplete', true);

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 진행 표시
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _currentPage ? Colors.green : Colors.grey[200],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // 페이지 콘텐츠
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildPage1(),
                  _buildPage2(),
                  _buildPage3(),
                ],
              ),
            ),

            // 하단 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: _prevPage,
                          child: const Icon(Icons.arrow_back, color: Colors.grey),
                        ),
                      ),
                    ),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _currentPage < 2 ? _nextPage : _saveAndStart,
                        child: Text(
                          _currentPage < 2 ? '다음' : '시작하기',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
    );
  }

  // 1단계: 환영 + 성별
  Widget _buildPage1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 앱 아이콘
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.local_dining, color: Colors.green, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            '안녕하세요! 👋',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'AI 다이어트 코치입니다.\n몇 가지 정보를 입력하면\n맞춤 식단을 추천해 드릴게요.',
            style: TextStyle(fontSize: 16, color: Colors.grey[600], height: 1.6),
          ),
          const SizedBox(height: 40),
          const Text(
            '성별',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: ['남성', '여성'].map((gender) {
              final bool selected = _selectedGender == gender;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedGender = gender);
                    _recalculate();
                  },
                  child: Container(
                    margin: EdgeInsets.only(right: gender == '남성' ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: selected ? Colors.green : Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? Colors.green : Colors.grey[200]!,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          gender == '남성' ? Icons.male : Icons.female,
                          color: selected ? Colors.white : Colors.grey[500],
                          size: 32,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          gender,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 2단계: 신체 정보
  Widget _buildPage2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '신체 정보를\n알려주세요 📏',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            '정확한 칼로리 계산을 위해 필요해요.',
            style: TextStyle(fontSize: 15, color: Colors.grey[500]),
          ),
          const SizedBox(height: 36),
          _buildInputField(
            controller: _heightController,
            label: '키',
            unit: 'cm',
            icon: Icons.height,
            hint: '예: 170',
          ),
          const SizedBox(height: 16),
          _buildInputField(
            controller: _weightController,
            label: '몸무게',
            unit: 'kg',
            icon: Icons.monitor_weight_outlined,
            hint: '예: 70',
          ),
          const SizedBox(height: 16),
          _buildInputField(
            controller: _ageController,
            label: '나이',
            unit: '세',
            icon: Icons.cake_outlined,
            hint: '예: 30',
            isDecimal: false,
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String unit,
    required IconData icon,
    required String hint,
    bool isDecimal = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isDecimal
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          decoration: InputDecoration(
            hintText: hint,
            suffixText: unit,
            prefixIcon: Icon(icon, color: Colors.green),
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.green, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // 3단계: 활동량 + TDEE 결과
  Widget _buildPage3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '활동 수준을\n선택해주세요 🏃',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            '평소 생활 패턴과 가장 비슷한 것을 골라주세요.',
            style: TextStyle(fontSize: 15, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ..._activityLevels.map((item) {
            final bool selected = _activityLevel == item['value'];
            return GestureDetector(
              onTap: () {
                setState(() => _activityLevel = item['value'] as double);
                _recalculate();
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected ? Colors.green.withValues(alpha: 0.08) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? Colors.green : Colors.grey[200]!,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      item['icon'] as IconData,
                      color: selected ? Colors.green : Colors.grey[400],
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: selected ? Colors.green : Colors.black87,
                            ),
                          ),
                          Text(
                            item['sub'] as String,
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          // 계산 결과 카드
          if (_calculatedTdee > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.withValues(alpha: 0.15), Colors.green.withValues(alpha: 0.05)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    '권장 하루 섭취 칼로리',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_calculatedTdee kcal',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '기초대사량 $_calculatedBmr kcal 기준',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '📌 계산 기준: Mifflin-St Jeor 공식 (Am J Clin Nutr, 1990) 및 활동 계수 (Ainsworth et al., 2000). 이 수치는 참고용이며 개인차가 있을 수 있습니다.',
              style: TextStyle(fontSize: 10, color: Colors.black45, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
