import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../controllers/queue_controller.dart';
import '../../controllers/unified_player_controller.dart';
import '../../models/queue_item.dart';
import 'media_source_picker.dart';

class QueueTabView extends StatelessWidget {
  final QueueController queueController;
  final UnifiedPlayerController player;

  const QueueTabView({
    super.key,
    required this.queueController,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queueController,
      builder: (context, _) {
        final items = queueController.items;
        final bool canManage = queueController.canManageQueue;
        final bool canAdd = queueController.canAddToQueue;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          children: [
            // Top Action Row: Unified Add Video to Queue
            if (canAdd) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryNeon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    AppHaptics.selection();
                    MediaSourcePicker.show(
                      context,
                      syncController: queueController.syncController,
                      chatController: queueController.chatController,
                      queueController: queueController,
                      isAddingToQueueInitial: true,
                    );
                  },
                  icon: const Icon(Icons.add_to_photos_rounded, size: 17),
                  label: const Text(
                    'Tambah Video ke Antrean',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Queue List Header
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DAFTAR ANTREAN (${items.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            if (items.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderLight),
                ),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(
                      Icons.playlist_play_rounded,
                      size: 44,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Antrean video masih kosong',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tambahkan video agar tontonan berlanjut otomatis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (canAdd) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () {
                          AppHaptics.selection();
                          MediaSourcePicker.show(
                            context,
                            syncController: queueController.syncController,
                            chatController: queueController.chatController,
                            queueController: queueController,
                            isAddingToQueueInitial: true,
                          );
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Tambah Video Sekarang'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryNeon,
                          side: const BorderSide(color: AppColors.primaryNeon),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                buildDefaultDragHandles: canManage,
                onReorderItem: (oldIndex, newIndex) {
                  AppHaptics.medium();
                  queueController.reorderQueue(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _QueueItemCard(
                    key: ValueKey(item.id),
                    index: index,
                    item: item,
                    canManage: canManage,
                    onPlayNow: canManage
                        ? () {
                            AppHaptics.selection();
                            queueController.playItem(item);
                          }
                        : null,
                    onRemove: canManage
                        ? () {
                            AppHaptics.selection();
                            queueController.removeFromQueue(item.id);
                          }
                        : null,
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _QueueItemCard extends StatelessWidget {
  final int index;
  final QueueItem item;
  final bool canManage;
  final VoidCallback? onPlayNow;
  final VoidCallback? onRemove;

  const _QueueItemCard({
    super.key,
    required this.index,
    required this.item,
    required this.canManage,
    this.onPlayNow,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final Color sourceColor = item.isYouTube
        ? AppColors.youtubeRed
        : item.isBstation
            ? AppColors.bstationBlue
            : item.isDailymotion
                ? AppColors.dailymotionBlue
                : AppColors.secondaryNeon;
    final String sourceBadge = item.isYouTube
        ? 'YOUTUBE'
        : item.isBstation
            ? 'BSTATION'
            : item.isDailymotion
                ? 'DAILYMOTION'
                : item.mediaType.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canManage)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: sourceColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  sourceBadge,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: sourceColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'oleh ${item.addedByUserName}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canManage && onPlayNow != null)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded,
                      color: AppColors.primaryNeon, size: 22),
                  tooltip: 'Putar Sekarang',
                  onPressed: onPlayNow,
                ),
              if (canManage && onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted, size: 18),
                  tooltip: 'Hapus dari Antrean',
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
