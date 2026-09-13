import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';

class EmojiPickerSheet extends StatefulWidget {
  final ValueChanged<String> onSelectEmoji;
  final ValueChanged<String>? onSelectCallout;
  final String title;

  const EmojiPickerSheet({
    super.key,
    required this.onSelectEmoji,
    this.onSelectCallout,
    this.title = 'Pilih Emoticon & Reaksi',
  });

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSelectEmoji,
    ValueChanged<String>? onSelectCallout,
    String title = 'Pilih Emoticon & Reaksi',
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EmojiPickerSheet(
        onSelectEmoji: onSelectEmoji,
        onSelectCallout: onSelectCallout,
        title: title,
      ),
    );
  }

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<String> nobarHits = [
    '❤️', '🔥', '😂', '👏', '🍿', '🚀', '🎉', '😱',
    '🍕', '🍻', '😴', '💀', '🤩', '😭', '🙌', '💯',
    '😍', '✨', '⚡', '💣', '👀', '🤯', '👑', '🏆',
  ];

  static const List<String> expressions = [
    '🤣', '🥺', '🤯', '🥳', '🤩', '😭', '😈', '👀',
    '🫠', '🫡', '🫣', '🤔', '😎', '😜', '😍', '🥶',
    '🥵', '🤡', '🤐', '🙄', '🤤', '🤠', '😇', '🤫',
  ];

  static const List<String> cinemaAndChill = [
    '🍿', '🎬', '📽️', '🥤', '🍫', '🍕', '🍦', '🍔',
    '🍟', '🛋️', '🕹️', '🎶', '🌙', '✨', '⚡', '☕',
    '🍩', '🍰', '📺', '🎧', '🎸', '🎮', '💡', '🎆',
  ];

  static const List<String> quickCallouts = [
    'GG! 🔥',
    'Plot twist! 😱',
    'Wkwkwk 😂',
    'Lanjut gass! 🚀',
    'Pause bentar ⏸️',
    'Sedih banget 😭',
    'Keren parah! 👏',
    'Momen epic! ⭐',
    'Ngantuk zzz 😴',
    'Seru abis! 🎉',
    'No debat 💯',
    'Next video apa? 🍿',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.onSelectCallout != null ? 4 : 3,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryNeon.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.mood_rounded,
                      color: AppColors.primaryNeon,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Category TabBar
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.primaryNeon,
              labelColor: AppColors.primaryNeon,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              dividerColor: AppColors.border,
              tabs: [
                const Tab(text: '🍿 Nobar Hits'),
                const Tab(text: '🎭 Ekspresi'),
                const Tab(text: '🎬 Bioskop & Snack'),
                if (widget.onSelectCallout != null)
                  const Tab(text: '💬 Callout Teks'),
              ],
            ),

            // TabBar View
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEmojiGrid(nobarHits),
                  _buildEmojiGrid(expressions),
                  _buildEmojiGrid(cinemaAndChill),
                  if (widget.onSelectCallout != null) _buildCalloutList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: emojis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        return Material(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () {
              AppHaptics.selection();
              widget.onSelectEmoji(emoji);
            },
            borderRadius: BorderRadius.circular(14),
            splashColor: AppColors.primaryNeon.withValues(alpha: 0.3),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 26),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalloutList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: quickCallouts.length,
      itemBuilder: (context, index) {
        final callout = quickCallouts[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                AppHaptics.light();
                Navigator.of(context).pop();
                widget.onSelectCallout?.call(callout);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        callout,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.send_rounded,
                      size: 16,
                      color: AppColors.secondaryNeon,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
