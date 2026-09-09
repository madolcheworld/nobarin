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
      listenable: Listenable.merge([queueController, player]),
      builder: (context, _) {
        final items = queueController.items;
        final bool canManage = queueController.canManageQueue;
        final bool canAdd = queueController.canAddToQueue;
        final hasMedia = player.mediaUrl.isNotEmpty;
        final isYouTube = player.mediaType == 'youtube';
        final isTwitch = player.mediaType == 'twitch';
        final isVimeo = player.mediaType == 'vimeo';
        final isDailymotion = player.mediaType == 'dailymotion';
        final isBstation = player.mediaType == 'bstation' ||
            player.mediaType == 'bilibili';
        final isGoogleDrive = player.mediaType == 'google_drive' ||
            player.mediaType == 'gdrive';
        final ytId = UnifiedPlayerController.extractYouTubeVideoId(
            player.mediaUrl);
        final dmId = isDailymotion
            ? UnifiedPlayerController.extractDailymotionVideoId(
                player.mediaUrl)
            : null;

        final Color sourceColor = isYouTube
            ? AppColors.youtubeRed
            : (isTwitch
                ? AppColors.twitchPurple
                : (isVimeo
                    ? AppColors.vimeoBlue
                    : (isDailymotion
                        ? AppColors.dailymotionBlue
                        : (isBstation
                            ? AppColors.bstationBlue
                            : (isGoogleDrive
                                ? AppColors.googleDriveGreen
                                : AppColors.secondaryNeon)))));

        final String sourceLabel = isYouTube
            ? 'YouTube'
            : (isTwitch
                ? 'Twitch'
                : (isVimeo
                    ? 'Vimeo'
                    : (isDailymotion
                        ? 'Dailymotion'
                        : (isBstation
                            ? 'Bstation'
                            : (isGoogleDrive ? 'Google Drive' : 'Direct URL')))));

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          children: [
            // Top Action Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.queue_music_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Antrean (${items.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (canAdd)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text(
                      'Tambah Video',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Now Playing Card
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                'SEDANG DIPUTAR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.primaryNeon.withValues(alpha: 0.9),
                ),
              ),
            ),

            if (hasMedia)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primaryNeon.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryNeon.withValues(alpha: 0.08),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isYouTube && ytId != null
                          ? Image.network(
                              'https://img.youtube.com/vi/$ytId/hqdefault.jpg',
                              width: 68,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 68,
                                height: 44,
                                color: Colors.black38,
                                child: const Icon(Icons.play_circle_fill,
                                    color: AppColors.youtubeRed, size: 24),
                              ),
                            )
                          : (isDailymotion && dmId != null
                              ? Image.network(
                                  'https://www.dailymotion.com/thumbnail/video/$dmId',
                                  width: 68,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    width: 68,
                                    height: 44,
                                    color: Colors.black38,
                                    child: const Icon(
                                        Icons.play_circle_filled_rounded,
                                        color: AppColors.dailymotionBlue,
                                        size: 24),
                                  ),
                                )
                              : Container(
                                  width: 68,
                                  height: 44,
                                  color: sourceColor.withValues(alpha: 0.15),
                                  child: Icon(
                                    isTwitch
                                        ? Icons.videogame_asset_rounded
                                        : (isVimeo
                                            ? Icons.ondemand_video_rounded
                                            : (isBstation
                                                ? Icons.smart_display_rounded
                                                : (isGoogleDrive
                                                    ? Icons.cloud_queue_rounded
                                                    : Icons.movie_outlined))),
                                    color: sourceColor,
                                    size: 24,
                                  ),
                                )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: sourceColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sourceLabel,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: sourceColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (player.isPlaying)
                                const Row(
                                  children: [
                                    Icon(Icons.graphic_eq_rounded,
                                        size: 13, color: AppColors.accentGreen),
                                    SizedBox(width: 3),
                                    Text(
                                      'Playing',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.accentGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            player.mediaUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: const Text(
                  'Belum ada video yang sedang diputar.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            // Section 2: Up Next
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'BERIKUTNYA (${items.length})',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (canManage && items.length > 1)
                    const Text(
                      'Tahan & geser untuk atur urutan',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
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
    final isYouTube = item.mediaType == 'youtube';
    final isTwitch = item.mediaType == 'twitch';
    final isVimeo = item.mediaType == 'vimeo';
    final isDailymotion = item.mediaType == 'dailymotion';
    final isBstation =
        item.mediaType == 'bstation' || item.mediaType == 'bilibili';
    final isGoogleDrive =
        item.mediaType == 'google_drive' || item.mediaType == 'gdrive';

    final Color sourceColor = isYouTube
        ? AppColors.youtubeRed
        : (isTwitch
            ? AppColors.twitchPurple
            : (isVimeo
                ? AppColors.vimeoBlue
                : (isDailymotion
                    ? AppColors.dailymotionBlue
                    : (isBstation
                        ? AppColors.bstationBlue
                        : (isGoogleDrive
                            ? AppColors.googleDriveGreen
                            : AppColors.secondaryNeon)))));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
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
                item.mediaType.toUpperCase(),
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
    );
  }
}
