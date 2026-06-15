import 'package:flutter/material.dart';

import '../services/api_service.dart';

class AiChatView extends StatefulWidget {
  const AiChatView({super.key});

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.actionPerformed = false,
  });

  final String text;
  final bool isUser;
  final bool actionPerformed;
}

class _ChatSession {
  const _ChatSession({required this.id, required this.title, required this.updatedAt});

  final String id;
  final String title;
  final String updatedAt;
}

class _AiChatViewState extends State<AiChatView> {
  final ApiService _apiService = ApiService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<_ChatSession> _chatSessions = [];
  String? _activeChatId;
  final List<_ChatMessage> _messages = [
    _ChatMessage(
      text: 'Ask me about today, priorities, or what to tackle next.',
      isUser: false,
    ),
  ];
  bool _isSending = false;
  bool _isLoadingChats = false;
  bool _isLoadingMessages = false;

  @override
  void initState() {
    super.initState();
    _loadChatSessions();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatSessions() async {
    setState(() => _isLoadingChats = true);
    try {
      final chats = await _apiService.listAiChats();
      if (!mounted) return;
      setState(() {
        _chatSessions = chats
            .map((c) => _ChatSession(
                  id: c['id'] as String,
                  title: (c['title'] as String?) ?? 'New Chat',
                  updatedAt: (c['updated_at'] as String?) ?? '',
                ))
            .toList();
        _isLoadingChats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingChats = false);
    }
  }

  Future<void> _loadChatMessages(String chatId) async {
    setState(() {
      _isLoadingMessages = true;
      _activeChatId = chatId;
    });
    try {
      final chat = await _apiService.getAiChat(chatId);
      if (!mounted) return;
      final messages = (chat['messages'] as List<dynamic>? ?? []);
      setState(() {
        _messages.clear();
        _messages.add(
          const _ChatMessage(text: 'Ask me about today, priorities, or what to tackle next.', isUser: false),
        );
        for (final msg in messages) {
          _messages.add(_ChatMessage(
            text: (msg['content'] as String?) ?? '',
            isUser: msg['role'] == 'user',
            actionPerformed: msg['action_performed'] == true,
          ));
        }
        _isLoadingMessages = false;
      });
      await _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMessages = false);
    }
  }

  Future<void> _startNewChat() async {
    setState(() {
      _activeChatId = null;
      _messages.clear();
      _messages.add(
        const _ChatMessage(text: 'Ask me about today, priorities, or what to tackle next.', isUser: false),
      );
    });
    Navigator.of(context).pop();
  }

  Future<void> _selectChat(String chatId) async {
    Navigator.of(context).pop();
    await _loadChatMessages(chatId);
  }

  Future<void> _deleteChat(String chatId) async {
    try {
      await _apiService.deleteAiChat(chatId);
      if (!mounted) return;
      if (_activeChatId == chatId) {
        setState(() {
          _activeChatId = null;
          _messages.clear();
          _messages.add(
            const _ChatMessage(text: 'Ask me about today, priorities, or what to tackle next.', isUser: false),
          );
        });
      }
      await _loadChatSessions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete chat: $e')),
      );
    }
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || !_scrollController.hasClients) return;

    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isSending = true;
    });
    _messageController.clear();
    await _scrollToBottom();

    try {
      final response = await _apiService.sendChatMessage(text, chatId: _activeChatId);
      if (!mounted) return;

      setState(() {
        _messages.add(_ChatMessage(
          text: response.message,
          isUser: false,
          actionPerformed: response.actionPerformed,
        ));
        if (response.chatId != null && _activeChatId == null) {
          _activeChatId = response.chatId;
        }
      });

      if (response.actionPerformed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task list updated')),
        );
      }

      await _loadChatSessions();
      await _scrollToBottom();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _messages.add(
          _ChatMessage(
            text: 'I could not reach the AI assistant right now.',
            isUser: false,
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI chat failed: $error')),
      );
      await _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildDrawer() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _startNewChat,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Chat'),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoadingChats
                  ? const Center(child: CircularProgressIndicator())
                  : _chatSessions.isEmpty
                      ? Center(
                          child: Text(
                            'No conversations yet',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _chatSessions.length,
                          itemBuilder: (context, index) {
                            final chat = _chatSessions[index];
                            final isActive = chat.id == _activeChatId;

                            return Dismissible(
                              key: ValueKey(chat.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: colorScheme.error,
                                child: Icon(Icons.delete_rounded, color: colorScheme.onError),
                              ),
                              confirmDismiss: (_) async {
                                return await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Chat'),
                                    content: Text('Delete "${chat.title}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              onDismissed: (_) => _deleteChat(chat.id),
                              child: ListTile(
                                selected: isActive,
                                selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
                                leading: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                ),
                                title: Text(
                                  chat.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                                subtitle: Text(
                                  _formatDate(chat.updatedAt),
                                  style: theme.textTheme.bodySmall,
                                ),
                                onTap: () => _selectChat(chat.id),
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

  Widget _buildMessageBubble(_ChatMessage message) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final alignment = message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final cardColor = colorScheme.surfaceContainerHighest;
    final textColor = colorScheme.onSurface;
    final shadow = <BoxShadow>[
      BoxShadow(
        color: colorScheme.outline.withValues(alpha: 0.04),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: message.isUser ? colorScheme.primary : cardColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(message.isUser ? 18 : 4),
              bottomRight: Radius.circular(message.isUser ? 4 : 18),
            ),
            boxShadow: shadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: message.isUser ? colorScheme.onPrimary : textColor,
                  height: 1.35,
                ),
              ),
              if (message.actionPerformed)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Task created',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: message.isUser
                          ? colorScheme.onPrimary.withValues(alpha: 0.7)
                          : colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final cardColor = colorScheme.surface;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurfaceVariant;
    final shadow = <BoxShadow>[
      BoxShadow(
        color: colorScheme.primary.withValues(alpha: 0.08),
        blurRadius: 30,
        offset: const Offset(0, 14),
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 92 + bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onHorizontalDragEnd: (_) => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colorScheme.primary, colorScheme.secondary],
                    ),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(color: colorScheme.outline),
                    boxShadow: shadow,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Chat',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: colorScheme.onPrimary,
                                    letterSpacing: -0.8,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _activeChatId != null
                                  ? '${_messages.length - 1} messages'
                                  : 'Swipe right for history',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onPrimary.withValues(alpha: 0.78),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _scaffoldKey.currentState?.openDrawer(),
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: colorScheme.onPrimary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(
                            Icons.history_rounded,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: _isLoadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                      ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: colorScheme.outline),
                  boxShadow: shadow,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          hintText: 'What do I have to do today?',
                          hintStyle: TextStyle(color: subTextColor),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _isSending ? null : _sendMessage,
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
