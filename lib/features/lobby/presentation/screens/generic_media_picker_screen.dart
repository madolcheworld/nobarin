import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../data/models/playable_media_item.dart';

/// Configuration definition for [GenericMediaPickerScreen].
class GenericMediaPickerConfig<T extends PlayableMediaItem> {
  final String title;
  final String platformName;
  final Color brandColor;
  final IconData brandIcon;
  final List<String> categories;
  final Map<String, List<T>> categoryPresets;
  final Future<List<T>> Function(String query, int page) searchFunction;
  final bool hasPagination;
  final String searchHint;
  final bool searchOnSubmitOnly;

  const GenericMediaPickerConfig({
    required this.title,
    required this.platformName,
    required this.brandColor,
    required this.brandIcon,
    required this.categories,
    required this.categoryPresets,
    required this.searchFunction,
    this.hasPagination = false,
    required this.searchHint,
    this.searchOnSubmitOnly = false,
  });
}

/// Unified generic screen for searching and selecting videos or streams across any platform.
class GenericMediaPickerScreen<T extends PlayableMediaItem> extends StatefulWidget {
  final GenericMediaPickerConfig<T> config;

  const GenericMediaPickerScreen({
    super.key,
    required this.config,
  });

  @override
  State<GenericMediaPickerScreen<T>> createState() =>
      _GenericMediaPickerScreenState<T>();
}

class _GenericMediaPickerScreenState<T extends PlayableMediaItem>
    extends State<GenericMediaPickerScreen<T>> {
  final _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;

  late String _selectedCategory;
  List<T> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _errorMessage;
  int _searchSequence = 0;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.config.categories.isNotEmpty
        ? widget.config.categories.first
        : 'All';
    _loadCategory(_selectedCategory);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.config.hasPagination) return;
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadMoreItems();
      }
    }
  }

  void _loadCategory(String category) {
    _searchSequence++;
    setState(() {
      _selectedCategory = category;
      _isLoading = false;
      _isLoadingMore = false;
      _hasMore = true;
      _currentPage = 1;
      _errorMessage = null;
      _items = List.from(widget.config.categoryPresets[category] ?? []);
    });
  }

  void _onSearchChanged(String query) {
    if (widget.config.searchOnSubmitOnly) {
      if (query.trim().isEmpty) {
        _loadCategory(_selectedCategory);
      } else {
        setState(() {});
      }
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    FocusScope.of(context).unfocus();

    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      _loadCategory(_selectedCategory);
      return;
    }

    final currentSequence = ++_searchSequence;

    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasMore = true;
      _currentPage = 1;
      _errorMessage = null;
    });

    try {
      final results = await widget.config.searchFunction(cleanQuery, 1);
      if (!mounted || currentSequence != _searchSequence) return;
      setState(() {
        _items = results;
        _isLoading = false;
        if (results.isEmpty) {
          _errorMessage =
              'Tidak menemukan video untuk "$cleanQuery" di ${widget.config.platformName}';
          _hasMore = false;
        }
      });
    } catch (e) {
      if (!mounted || currentSequence != _searchSequence) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Gagal memuat hasil pencarian dari ${widget.config.platformName}. Silakan coba lagi.';
      });
    }
  }

  Future<void> _loadMoreItems() async {
    final cleanQuery = _searchController.text.trim();
    if (cleanQuery.isEmpty) return;

    final currentSequence = _searchSequence;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final results = await widget.config.searchFunction(cleanQuery, nextPage);
      if (!mounted || currentSequence != _searchSequence) return;
      setState(() {
        _currentPage = nextPage;
        _isLoadingMore = false;
        if (results.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(results);
        }
      });
    } catch (_) {
      if (!mounted || currentSequence != _searchSequence) return;
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandColor = widget.config.brandColor;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: brandColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(widget.config.brandIcon, color: brandColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.config.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: isDark ? AppColors.surface : Colors.white,
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: isDark ? AppColors.surface : Colors.white,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: _performSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.config.searchHint,
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 14,
                ),
                prefixIcon: IconButton(
                  icon: Icon(Icons.search, color: brandColor, size: 22),
                  tooltip: 'Cari',
                  onPressed: () => _performSearch(_searchController.text),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Hapus',
                        onPressed: () {
                          _searchController.clear();
                          _loadCategory(_selectedCategory);
                        },
                      ),
                    if (widget.config.searchOnSubmitOnly &&
                        _searchController.text.trim().isNotEmpty)
                      IconButton(
                        icon: Icon(
                          Icons.arrow_forward_rounded,
                          color: brandColor,
                          size: 20,
                        ),
                        tooltip: 'Cari sekarang',
                        onPressed: () => _performSearch(_searchController.text),
                      ),
                  ],
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: isDark
                    ? AppColors.surfaceElevated
                    : const Color(0xFFF0F2F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: brandColor, width: 1.5),
                ),
              ),
            ),
          ),

          // 2. Category Chips (Only shown when not searching)
          if (_searchController.text.trim().isEmpty &&
              widget.config.categories.isNotEmpty)
            Container(
              height: 48,
              color: isDark ? AppColors.surface : Colors.white,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: widget.config.categories.length,
                separatorBuilder: (context, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = widget.config.categories[index];
                  final isSelected = cat == _selectedCategory;
                  return ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: brandColor,
                    backgroundColor: isDark
                        ? AppColors.surfaceElevated
                        : const Color(0xFFF0F2F6),
                    onSelected: (selected) {
                      if (selected) {
                        AppHaptics.selection();
                        _loadCategory(cat);
                      }
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide.none,
                    ),
                    showCheckmark: false,
                  );
                },
              ),
            ),

          const SizedBox(height: 8),

          // 3. Main Content
          Expanded(
            child: _buildContent(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 64, color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadCategory(_selectedCategory),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Muat Ulang Presets'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.config.brandColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Tidak ada item yang tersedia',
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (_searchController.text.trim().isNotEmpty) {
          await _performSearch(_searchController.text);
        } else {
          _loadCategory(_selectedCategory);
        }
      },
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + (_isLoadingMore ? 1 : 0),
        separatorBuilder: (context, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final item = _items[index];
          return _buildMediaCard(item, isDark);
        },
      ),
    );
  }

  Widget _buildMediaCard(T item, bool isDark) {
    return Material(
      color: isDark ? AppColors.surface : Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      elevation: isDark ? 0 : 1,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          Navigator.pop(context, item);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail container
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.thumbnailUrl != null &&
                      item.thumbnailUrl!.isNotEmpty)
                    Image.network(
                      item.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildFallbackThumbnail(),
                    )
                  else
                    _buildFallbackThumbnail(),

                  // Duration / Status Badge
                  if (item.duration.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.duration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Metadata info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(widget.config.brandIcon,
                          size: 14, color: widget.config.brandColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.config.brandColor.withValues(alpha: 0.4),
            widget.config.brandColor.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          widget.config.brandIcon,
          size: 48,
          color: widget.config.brandColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
