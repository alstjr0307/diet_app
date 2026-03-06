import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  double _activityLevel = 1.2;

  int _calculatedBmr = 0;
  int _calculatedTdee = 0;

  final List<Map<String, dynamic>> _activityLevels = [
    {'label': '주로 앉아서 생활 (사무직, 재택)', 'value': 1.2},
    {'label': '가벼운 활동 (산책, 스트레칭)', 'value': 1.375},
    {'label': '규칙적인 운동 (헬스, 조깅 등)', 'value': 1.55},
    {'label': '고강도 운동 또는 육체 노동', 'value': 1.725},
  ];

  @override
  void initState() {
    super.initState();
    _targetKcalController = TextEditingController(text: widget.initialTargetKcal.toString());
    _currentWeightController = TextEditingController(text: widget.initialCurrentWeight.toString());
    _userHeightController = TextEditingController(text: widget.initialUserHeight.toString());
    _userAgeController = TextEditingController(text: widget.initialUserAge.toString());
    _selectedGender = widget.initialUserGender;

    _currentWeightController.addListener(_recalculate);
    _userHeightController.addListener(_recalculate);
    _userAgeController.addListener(_recalculate);

    _recalculate();
    _loadActivityLevel();
  }

  Future<void> _loadActivityLevel() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _activityLevel = prefs.getDouble('activityLevel') ?? 1.2;
      _recalculate();
    });
  }

  @override
  void dispose() {
    _targetKcalController.dispose();
    _currentWeightController.dispose();
    _userHeightController.dispose();
    _userAgeController.dispose();
    super.dispose();
  }

  void _recalculate() {
    final weight = double.tryParse(_currentWeightController.text) ?? 0;
    final height = double.tryParse(_userHeightController.text) ?? 0;
    final age = int.tryParse(_userAgeController.text) ?? 0;

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

  void _applyCalculated() {
    _targetKcalController.text = _calculatedTdee.toString();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('targetKcal', int.tryParse(_targetKcalController.text) ?? widget.initialTargetKcal);
    await prefs.setDouble('currentWeight', double.tryParse(_currentWeightController.text) ?? widget.initialCurrentWeight);
    await prefs.setDouble('userHeight', double.tryParse(_userHeightController.text) ?? widget.initialUserHeight);
    await prefs.setInt('userAge', int.tryParse(_userAgeController.text) ?? widget.initialUserAge);
    await prefs.setString('userGender', _selectedGender);
    await prefs.setDouble('activityLevel', _activityLevel);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('개인 설정', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('신체 정보', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: _currentWeightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '현재 체중 (kg)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.monitor_weight),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userHeightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '키 (cm)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.height),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userAgeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '나이 (세)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cake),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person, color: Colors.grey),
                const SizedBox(width: 12),
                const Text('성별', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '남성', label: Text('남성')),
                    ButtonSegment(value: '여성', label: Text('여성')),
                  ],
                  selected: {_selectedGender},
                  onSelectionChanged: (val) {
                    setState(() {
                      _selectedGender = val.first;
                      _recalculate();
                    });
                  },
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: Colors.green,
                    selectedForegroundColor: Colors.white,
                    foregroundColor: Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            const Text('기초대사량 (BMR) 계산', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('기초대사량 (BMR)', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      Text(
                        _calculatedBmr > 0 ? '$_calculatedBmr kcal' : '-',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('활동 수준', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<double>(
                    initialValue: _activityLevel,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    items: _activityLevels.map((item) {
                      return DropdownMenuItem<double>(
                        value: item['value'] as double,
                        child: Text(item['label'] as String, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _activityLevel = val!;
                        _recalculate();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('권장 섭취 칼로리 (TDEE)', style: TextStyle(fontSize: 14, color: Colors.grey)),
                      Text(
                        _calculatedTdee > 0 ? '$_calculatedTdee kcal' : '-',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: const BorderSide(color: Colors.green, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _calculatedTdee > 0 ? _applyCalculated : null,
                icon: const Icon(Icons.auto_fix_high),
                label: Text(
                  _calculatedTdee > 0 ? '권장 칼로리 자동 설정 ($_calculatedTdee kcal)' : '신체 정보를 입력하면 자동 계산됩니다',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text('목표 칼로리', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: _targetKcalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '목표 칼로리 (kcal)',
                helperText: '위 계산값을 적용하거나 직접 입력하세요',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flash_on, color: Colors.green),
              ),
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saveSettings,
                child: const Text('설정 저장', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
