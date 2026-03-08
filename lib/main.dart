import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'screens/settings_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/report_screen.dart';
import 'screens/meal_plan_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/notification_settings_screen.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool onboardingComplete = false; // Default value

  try {
    await dotenv.load(fileName: '.env');
    await MobileAds.instance.initialize();
    await NotificationService.init();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notificationEnabled') ?? true) {
      await NotificationService.scheduleMealReminders(
        lunchHour: prefs.getInt('lunchHour') ?? 12,
        lunchMinute: prefs.getInt('lunchMinute') ?? 0,
        dinnerHour: prefs.getInt('dinnerHour') ?? 19,
        dinnerMinute: prefs.getInt('dinnerMinute') ?? 0,
      );
    }
    onboardingComplete = prefs.getBool('onboardingComplete') ?? false;
  } catch (e) {
    if (kDebugMode) {
      print('Error during app initialization: $e');
    }
    // In case of error, we proceed with the default value for onboardingComplete,
    // which will show the onboarding screen. This is a safe fallback.
  }

  runApp(DietApp(showOnboarding: !onboardingComplete));
}

class DietApp extends StatelessWidget {
  final bool showOnboarding;
  const DietApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 칼로리 계산기',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      initialRoute: showOnboarding ? '/onboarding' : '/home',
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const DietScreen(),
      },
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

  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  InterstitialAd? _interstitialAd;
  int _analysisCount = 0;

  static final String _bannerAdUnitId = kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'  // 테스트 ID
      : Platform.isIOS
          ? 'ca-app-pub-6925657557995580/3948817704' // iOS 실제 ID
          : 'ca-app-pub-6925657557995580/5374344359'; // Android 실제 ID

  static final String _interstitialAdUnitId = kDebugMode
      ? 'ca-app-pub-3940256099942544/1033173712'  // 테스트 ID
      : Platform.isIOS
          ? 'ca-app-pub-6925657557995580/1677877582' // iOS 실제 ID
          : 'ca-app-pub-6925657557995580/3980461503'; // Android 실제 ID

  final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  String get _dateKey =>
      "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
  List<dynamic> get _currentFoods => _history[_dateKey] ?? [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadInterstitialAd();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bannerAd == null && !_isBannerAdLoaded) {
      _loadBannerAd(context);
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialAd!.setImmersiveMode(true);
        },
        onAdFailedToLoad: (_) {
          _interstitialAd = null;
        },
      ),
    );
  }

  void _showInterstitialAdIfNeeded() {
    _analysisCount++;
    if (_analysisCount % 3 == 0 && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (ad, _) {
          ad.dispose();
          _interstitialAd = null;
          _loadInterstitialAd();
        },
      );
      _interstitialAd!.show();
    }
  }

  Future<void> _loadBannerAd(BuildContext context) async {
    final width = MediaQuery.of(context).size.width.truncate();
    final adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (adSize == null) return;
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: adSize,
      request: const AdRequest(nonPersonalizedAds: false),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
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
      final model = GenerativeModel(model: 'gemini-3-flash-preview', apiKey: apiKey);

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
          food['isNightSnack'] = false;
        }

        List<dynamic> updatedList = List.from(_currentFoods);
        updatedList.addAll(newFoods);
        _history[_dateKey] = updatedList;

        _calculateTotal();
        _controller.clear();
        _saveData();
      });
      _showInterstitialAdIfNeeded();
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

  Future<void> _analyzeDietFromImage() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final XFile? pickedFile = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
    );

    if (pickedFile == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final imageBytes = await pickedFile.readAsBytes();
      final model = GenerativeModel(model: 'gemini-3-flash-preview', apiKey: apiKey);

      const prompt = '''
너는 영양 분석 AI야. 이 음식 사진을 보고 어떤 음식인지 파악해서,
칼로리와 영양성분을 무조건 아래 JSON 형식으로만 답해. 다른 말은 절대 하지 마.
만약 음식을 찾을 수 없거나 분석이 불가능하면 빈 리스트 []만 반환해.
형식: [{"food": "이름", "amount": "양", "kcal": 숫자, "carbs": 숫자, "protein": 숫자, "fat": 숫자}]
''';

      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]);

      String cleanText = response.text ?? "[]";
      cleanText = cleanText
          .replaceAll(RegExp(r'```json\s*'), '')
          .replaceAll(RegExp(r'```\s*'), '')
          .trim();

      List<dynamic> newFoods = jsonDecode(cleanText);

      setState(() {
        if (newFoods.isEmpty) {
          _errorMessage = "음식을 인식하지 못했습니다. 다른 사진을 시도해보세요!";
          return;
        }

        for (var food in newFoods) {
          food['isNightSnack'] = false;
        }

        List<dynamic> updatedList = List.from(_currentFoods);
        updatedList.addAll(newFoods);
        _history[_dateKey] = updatedList;

        _calculateTotal();
        _saveData();
      });
      _showInterstitialAdIfNeeded();
    } catch (e) {
      setState(() {
        _errorMessage = "사진 분석 중 오류가 발생했어요: $e";
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

  Widget _nutritionChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
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
    final double progressClamped = progress.clamp(0.0, 1.0);
    final int progressPct = _targetKcal > 0
        ? (_totalKcal / _targetKcal * 100).round()
        : 0;

    final String todayStr =
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
    final String weightChangeText = _estimatedWeightChange > 0
        ? '+${_estimatedWeightChange.toStringAsFixed(2)} kg 예상'
        : '${_estimatedWeightChange.toStringAsFixed(2)} kg 예상';
    final Color weightChangeColor =
        _estimatedWeightChange > 0 ? Colors.redAccent : Colors.blueAccent;
    final Color kcalColor =
        _totalKcal > _targetKcal ? Colors.redAccent : Colors.green;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 네비게이터
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.green),
                onPressed: () => setState(() {
                  _selectedDate =
                      _selectedDate.subtract(const Duration(days: 1));
                  _calculateTotal();
                }),
              ),
              GestureDetector(
                onTap: () => _selectDate(context),
                child: Text(
                  _dateKey == todayStr ? "오늘 ($_dateKey)" : _dateKey,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.green),
                onPressed: () => setState(() {
                  _selectedDate = _selectedDate.add(const Duration(days: 1));
                  _calculateTotal();
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 칼로리 요약 카드 (원형 프로그레스)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // 좌측: 숫자 정보
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '오늘 섭취',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[500]),
                          ),
                          const SizedBox(height: 2),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '$_totalKcal',
                                  style: TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.bold,
                                    color: kcalColor,
                                  ),
                                ),
                                TextSpan(
                                  text: ' kcal',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '목표 $_targetKcal kcal',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[500]),
                          ),
                          if (_currentFoods.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: weightChangeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                weightChangeText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: weightChangeColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // 우측: 원형 프로그레스 링
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 92,
                          height: 92,
                          child: CircularProgressIndicator(
                            value: progressClamped,
                            strokeWidth: 9,
                            backgroundColor: Colors.grey[200],
                            valueColor:
                                AlwaysStoppedAnimation<Color>(kcalColor),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$progressPct%',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: kcalColor,
                              ),
                            ),
                            Text(
                              '달성',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 영양소 요약
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNutrient('탄수화물', '$_totalCarbs g', Colors.orange),
                    Container(width: 1, height: 32, color: Colors.grey[200]),
                    _buildNutrient('단백질', '$_totalProtein g', Colors.blueAccent),
                    Container(width: 1, height: 32, color: Colors.grey[200]),
                    _buildNutrient('지방', '$_totalFat g', Colors.purpleAccent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 음식 입력 영역
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: "무엇을 드셨나요? (예: 제육볶음 1인분)",
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Colors.green, width: 1.5),
              ),
              prefixIcon:
                  const Icon(Icons.restaurant_menu, color: Colors.green),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.green, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isLoading ? null : _analyzeDietFromImage,
                    icon: const Icon(Icons.camera_alt, color: Colors.green),
                    label: const Text(
                      '사진으로 추가',
                      style: TextStyle(
                          color: Colors.green,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isLoading ? null : analyzeDiet,
                    icon: _isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: const Text(
                      '직접 입력',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMessage,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (_isBannerAdLoaded && _bannerAd != null)
            SizedBox(
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),

          const SizedBox(height: 16),

          if (_currentFoods.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.restaurant,
                        size: 60, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(
                      '이 날의 식단 기록이 없습니다.',
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '위에서 먹은 음식을 입력해보세요',
                      style: TextStyle(
                          color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              '오늘 먹은 음식',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _currentFoods.length,
              itemBuilder: (context, index) {
                final reversedList = _currentFoods.reversed.toList();
                final item = reversedList[index];
                final bool isNight = item["isNightSnack"] == true;
                return Dismissible(
                  key: ObjectKey(item),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 22),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white, size: 26),
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
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 1.5,
                    shadowColor: Colors.grey.withValues(alpha: 0.2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 4,
                              color:
                                  isNight ? Colors.orange : Colors.green,
                            ),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 12, 14, 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item["food"],
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isNight) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              '야식',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${item["kcal"]} kcal',
                                            style: const TextStyle(
                                              color: Colors.redAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Text(
                                          '${item["amount"]}',
                                          style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 12),
                                        ),
                                        const SizedBox(width: 10),
                                        _nutritionChip('탄',
                                            '${item["carbs"]}g', Colors.orange),
                                        const SizedBox(width: 4),
                                        _nutritionChip('단',
                                            '${item["protein"]}g',
                                            Colors.blueAccent),
                                        const SizedBox(width: 4),
                                        _nutritionChip('지',
                                            '${item["fat"]}g',
                                            Colors.purpleAccent),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentTabIndex == 0
          ? AppBar(
              title: const Text(
                'AI 다이어트 코치 🥗',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: _navigateToSettings,
                ),
              ],
            )
          : null,
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
              icon: Icon(Icons.chat_bubble_outline), label: 'AI코치'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: '리포트'),
          BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_menu_outlined), label: '식단추천'),
        ],
      ),
    );
  }
}
