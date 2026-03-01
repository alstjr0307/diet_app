import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

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
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'sender': 'AI',
      'text':
          '안녕하세요! 식단과 건강에 대해 무엇이든 물어보세요 😊\n'
          '키 ${widget.userHeight}cm, ${widget.userAge}세, ${widget.userGender}, '
          '체중 ${widget.currentWeight}kg, 목표 ${widget.targetKcal}kcal 정보를 알고 있어요.',
    });
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userHeight != widget.userHeight ||
        oldWidget.userAge != widget.userAge ||
        oldWidget.userGender != widget.userGender ||
        oldWidget.currentWeight != widget.currentWeight ||
        oldWidget.targetKcal != widget.targetKcal) {
      setState(() {
        _messages[0] = {
          'sender': 'AI',
          'text': '안녕하세요! 식단과 건강에 대해 무엇이든 물어보세요 😊\n'
              '키 ${widget.userHeight}cm, ${widget.userAge}세, ${widget.userGender}, '
              '체중 ${widget.currentWeight}kg, 목표 ${widget.targetKcal}kcal 정보를 알고 있어요.',
        };
      });
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_chatController.text.trim().isEmpty || _isSending) return;

    final userMessage = _chatController.text.trim();
    setState(() {
      _messages.add({'sender': 'User', 'text': userMessage});
      _chatController.clear();
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final model = GenerativeModel(model: 'gemini-3-flash-preview', apiKey: widget.apiKey);

      String contextPrompt =
          "사용자 정보: 키 ${widget.userHeight}cm, 나이 ${widget.userAge}세, ${widget.userGender}, "
          "현재 체중 ${widget.currentWeight}kg, 목표 칼로리 ${widget.targetKcal}kcal.\n";

      String todayDateKey =
          "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";
      List<dynamic> todayFoods = widget.currentHistory[todayDateKey] ?? [];
      if (todayFoods.isNotEmpty) {
        contextPrompt += "오늘의 식단 기록:\n";
        for (var food in todayFoods) {
          contextPrompt +=
              "- ${food['food']} ${food['amount']} (${food['kcal']}kcal, 탄${food['carbs']}g, 단${food['protein']}g, 지${food['fat']}g)"
              "${food['isNightSnack'] == true ? ' (야식)' : ''}\n";
        }
      } else {
        contextPrompt += "오늘의 식단 기록: 없음.\n";
      }
      contextPrompt +=
          "이전 대화: ${_messages.where((m) => m['sender'] == 'User').map((m) => m['text']).join(' | ')}.\n";

      final prompt = '''
너는 개인 영양 코치 AI야. 다음 사용자 정보와 식단 기록을 바탕으로 사용자의 질문에 답변하고,
건강하고 동기 부여가 되는 조언을 제공해. 친근하고 유용한 한국어 대화체로 답변해.
JSON 형식으로 답변하지 마.

$contextPrompt
사용자 질문: $userMessage
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final aiResponse = response.text ?? "죄송합니다. 답변을 생성하지 못했습니다.";

      setState(() {
        _messages.add({'sender': 'AI', 'text': aiResponse});
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add({'sender': 'AI', 'text': "오류가 발생했습니다: $e"});
      });
      _scrollToBottom();
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Widget _buildBubble(Map<String, String> message) {
    final isUser = message['sender'] == 'User';
    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 56 : 8,
        right: isUser ? 8 : 56,
        top: 4,
        bottom: 4,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: Colors.green,
              child: const Icon(Icons.smart_toy, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? Colors.green : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message['text']!,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: Colors.green,
            child: const Icon(Icons.smart_toy, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.green[400],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '입력 중...',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text(
          'AI 코치 채팅 💬',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: _messages.length + (_isSending ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isSending && index == _messages.length) {
                  return _buildTypingIndicator();
                }
                return _buildBubble(_messages[index]);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'AI 코치에게 질문하세요...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide:
                            const BorderSide(color: Colors.green, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF7F7F7),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isSending ? null : _sendMessage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _isSending ? Colors.grey[300] : Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
