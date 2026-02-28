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

  @override
  void initState() {
    super.initState();
    _targetKcalController = TextEditingController(text: widget.initialTargetKcal.toString());
    _currentWeightController = TextEditingController(text: widget.initialCurrentWeight.toString());
    _userHeightController = TextEditingController(text: widget.initialUserHeight.toString());
    _userAgeController = TextEditingController(text: widget.initialUserAge.toString());
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
    await prefs.setInt('targetKcal', int.tryParse(_targetKcalController.text) ?? widget.initialTargetKcal);
    await prefs.setDouble('currentWeight', double.tryParse(_currentWeightController.text) ?? widget.initialCurrentWeight);
    await prefs.setDouble('userHeight', double.tryParse(_userHeightController.text) ?? widget.initialUserHeight);
    await prefs.setInt('userAge', int.tryParse(_userAgeController.text) ?? widget.initialUserAge);
    await prefs.setString('userGender', _selectedGender);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('개인 설정', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  items: <String>['남성', '여성']
                      .map<DropdownMenuItem<String>>((String value) {
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
