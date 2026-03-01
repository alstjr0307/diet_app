import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert'; // for jsonDecode in case of any future need, though not directly used now

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
  int _averageKcal = 0;
  int _recordedDays = 0;

  @override
  void initState() {
    super.initState();
    _prepareChartData();
    _prepareLast7DaysListData();
  }

  @override
  void didUpdateWidget(ReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepareChartData();
    _prepareLast7DaysListData();
  }

  // 섭취 칼로리 목록 팝업 다이얼로그 (재사용)
  void _showDailyFoodsDialog(
      BuildContext context, String dateKey, List<dynamic> foods) {
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
                        .map((food) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4.0),
                              child: Text(
                                '- ${food["food"]} ${food["amount"]} (\n'
                                '  ${food["kcal"]}kcal, 탄${food["carbs"]}g, 단${food["protein"]}g, 지${food["fat"]}g)'
                                '${(food["isNightSnack"] == true ? " (야식)" : "")}',
                              ),
                            ))
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

  // 그래프 데이터 준비 함수
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
    int totalKcalSum = 0;
    int recordedDaysCount = 0;

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

      if (total > currentMaxKcal) currentMaxKcal = total;
      if (dailyFoods.isNotEmpty) {
        totalKcalSum += total;
        recordedDaysCount++;
      }
    }

    setState(() {
      _maxKcalValue = currentMaxKcal;
      _averageKcal = recordedDaysCount > 0
          ? (totalKcalSum / recordedDaysCount).round()
          : 0;
      _recordedDays = recordedDaysCount;
    });
  }

  // 하단 리스트를 위한 최근 7일 데이터 준비 함수
  void _prepareLast7DaysListData() {
    _last7DaysKeysForList.clear();
    for (int i = 6; i >= 0; i--) {
      DateTime date = DateTime.now().subtract(Duration(days: i));
      _last7DaysKeysForList.add(
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('칼로리 리포트 📊',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  _prepareChartData();
                });
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Colors.green,
                selectedForegroundColor: Colors.white,
                foregroundColor: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('일 평균 섭취',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text(
                          _recordedDays > 0 ? '$_averageKcal kcal' : '기록 없음',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('기록한 날',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text(
                          '$_recordedDays일',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '$_selectedRange간 칼로리 섭취량 추이',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 1.70,
              child: Padding(
                padding: const EdgeInsets.only(
                    right: 18, left: 12, top: 24, bottom: 12),
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
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
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
                              child: Text(label,
                                  style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1000,
                          getTitlesWidget: (value, meta) {
                            return Text('${(value / 1000).toStringAsFixed(0)}k',
                                style: const TextStyle(fontSize: 10));
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
                          colors: [
                            Colors.green.withValues(alpha: 0.5),
                            Colors.green,
                          ],
                        ),
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.withValues(alpha: 0.3),
                              Colors.green.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                      LineChartBarData(
                        spots: [
                          FlSpot(0, widget.targetKcal.toDouble()),
                          FlSpot((_graphDateKeys.length - 1).toDouble(),
                              widget.targetKcal.toDouble())
                        ],
                        isCurved: false,
                        color: Colors.redAccent.withValues(alpha: 0.7),
                        barWidth: 1,
                        dotData: const FlDotData(show: false),
                        dashArray: [5, 5],
                        belowBarData: BarAreaData(show: false),
                      )
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              '최근 7일간 섭취 상세',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _last7DaysKeysForList.length,
              itemBuilder: (context, index) {
                String dateKey = _last7DaysKeysForList[index];
                List<dynamic> dailyFoods = widget.history[dateKey] ?? [];
                int dailyTotalKcal = _dailyCaloriesMap[dateKey] ?? 0;

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
                                fontWeight: FontWeight.bold, fontSize: 16),
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
