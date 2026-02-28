import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';

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
