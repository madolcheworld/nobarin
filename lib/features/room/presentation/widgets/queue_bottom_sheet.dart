import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../controllers/queue_controller.dart';
import '../../controllers/unified_player_controller.dart';
import '../../models/queue_item.dart';
import 'media_source_picker.dart';

class QueueBottomSheet extends StatefulWidget {
  final QueueController queueController;
  final UnifiedPlayerController player;

  const QueueBottomSheet({
    super.key,
    required this.queueController,
    required this.player,
  });

  static Future<void> show(
    BuildContext context, {
    required QueueController queueController,
    required UnifiedPlayerController player,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QueueBottomSheet(
        queueController: queueController,
        player: player,
      ),
    );
  }

  @override
  State<QueueBottomSheet> createState() => _QueueBottomSheetState();
}

class _QueueBottomSheetState extends State<QueueBottomSheet> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.queueController,
      builder: (context, _) {
        final items = widget.queueController.items;
        final bool canManage = widget.queueController.canManageQueue;
        final bool canAdd = widget.queueController.canAddToQueue;
        final hasMedia = widget.player.mediaUrl.isNotEmpty;
        final isYouTube = widget.player.mediaType == 'youtube';
        final ytId = UnifiedPlayerController.extractYouTubeVideoId(
            widget.player.mediaUrl);

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
            maxWidth: 600,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: AppColors.border, width: 1.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryNeon.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.queue_music_rounded,
                        color: AppColors.primaryNeon,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            'Antrean Video',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              '${items.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryNeon,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Add to Queue button
                    if (canAdd)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryNeon,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          MediaSourcePicker.show(
                            context,
                            syncController: widget.queueController.syncController,
                            chatController: widget.queueController.chatController,
                            queueController: widget.queueController,
                            isAddingToQueueInitial: true,
                          );
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text(
                          'Tambah',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppColors.border),

              // Content List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Section 1: Sedang Diputar (Now Playing)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Text(
                        'SEDANG DIPUTAR',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.primaryNeon.withValues(alpha: 0.9),
                        ),
                      ),
                    ),

                    if (hasMedia) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primaryNeon.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: isYouTube && ytId != null
                                  ? Image.network(
                                      'https://img.youtube.com/vi/$ytId/hqdefault.jpg',
                                      width: 64,
                                      height: 42,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        width: 64,
                                        height: 42,
                                        color: Colors.black26,
                                        child: const Icon(
                                          Icons.play_circle_fill,
                                          color: AppColors.accentRed,
                                          size: 24,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      width: 64,
                                      height: 42,
                                      color: Colors.black26,
                                      child: const Icon(
                                        Icons.movie_outlined,
                                        color: AppColors.secondaryNeon,
                                        size: 24,
                                      ),
                                    ),
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
                                            horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: (isYouTube
                                                  ? AppColors.accentRed
                                                  : AppColors.secondaryNeon)
                                              .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isYouTube ? 'YouTube' : 'Direct URL',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isYouTube
                                                ? AppColors.accentRed
                                                : AppColors.secondaryNeon,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (widget.player.isPlaying)
                                        const Row(
                                          children: [
                                            Icon(Icons.graphic_eq_rounded,
                                                size: 13,
                                                color: AppColors.primaryNeon),
                                            SizedBox(width: 3),
                                            Text(
                                              'Playing',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: AppColors.primaryNeon,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.player.mediaUrl,
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
                      ),
                    ] else ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(
                          'Belum ada video yang diputar.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Section 2: Antrean Berikutnya (Up Next)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'BERIKUTNYA (${items.length})',
                            style: const TextStyle(
                              fontSize: 11,
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
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (items.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 36),
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
                              'Tambahkan video agar langsung berlanjut setelah ini.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        buildDefaultDragHandles: canManage,
                        onReorderItem: (oldIdx, newIdx) {
                          widget.queueController.reorderQueue(oldIdx, newIdx);
                        },
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _buildQueueTile(
                            context,
                            item: item,
                            index: index,
                            canManage: canManage,
                            key: ValueKey(item.id),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQueueTile(
    BuildContext context, {
    required QueueItem item,
    required int index,
    required bool canManage,
    required Key key,
  }) {
    final ytId = item.isYouTube
        ? UnifiedPlayerController.extractYouTubeVideoId(item.mediaUrl)
        : null;

    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: item.isYouTube && ytId != null
                  ? Image.network(
                      item.thumbnailUrl ??
                          'https://img.youtube.com/vi/$ytId/hqdefault.jpg',
                      width: 54,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 54,
                        height: 36,
                        color: Colors.black26,
                        child: const Icon(
                          Icons.play_circle_fill,
                          color: AppColors.accentRed,
                          size: 18,
                        ),
                      ),
                    )
                  : Container(
                      width: 54,
                      height: 36,
                      color: Colors.black26,
                      child: const Icon(
                        Icons.movie_outlined,
                        color: AppColors.secondaryNeon,
                        size: 18,
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
        subtitle: Text(
          'Ditambahkan oleh ${item.addedByUserName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play now button
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded,
                  color: AppColors.primaryNeon, size: 22),
              tooltip: 'Putar Sekarang',
              onPressed: () {
                widget.queueController.playItem(item);
              },
            ),

            // Delete from queue button
            if (canManage)
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary, size: 18),
                tooltip: 'Hapus dari Antrean',
                onPressed: () {
                  widget.queueController.removeFromQueue(item.id);
                },
              ),
          ],
        ),
      ),
    );
  }
}
