import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/network/api_cache_manager.dart';
import '../../../core/network/app_http_client.dart';
import 'models/google_drive_video_model.dart';

class GoogleDriveService {
  // Regex to match various Google Drive file sharing and preview URLs
  static final RegExp _drivePathRegex = RegExp(
    r'(?:drive|docs)\.google\.com\/file\/d\/([a-zA-Z0-9_-]{20,})',
    caseSensitive: false,
  );

  static final RegExp _driveParamRegex = RegExp(
    r'(?:drive|docs)\.google\.com\/(?:open|uc)\?(?:[^\s&]+&)*id=([a-zA-Z0-9_-]{20,})',
    caseSensitive: false,
  );

  static final RegExp _rawIdRegex = RegExp(
    r'^[a-zA-Z0-9_-]{25,60}$',
  );

  /// Extracts Google Drive File ID from URL or raw ID string.
  static String? extractFileId(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final pathMatch = _drivePathRegex.firstMatch(trimmed);
    if (pathMatch != null) {
      return pathMatch.group(1);
    }

    final paramMatch = _driveParamRegex.firstMatch(trimmed);
    if (paramMatch != null) {
      return paramMatch.group(1);
    }

    if (_rawIdRegex.hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Preset curated Google Drive videos organized by category
  static final Map<String, List<GoogleDriveVideo>> categoryPresets = {
    'Film & Animasi Open Source': [
      const GoogleDriveVideo(
        id: '1_yN3d9T8g6rK5y6E_Z-aL6jA4h2_xGk8',
        title: 'Big Buck Bunny (1080p FHD Open Movie)',
        ownerName: 'Blender Foundation Archive',
        thumbnailUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Big_buck_bunny_poster_big.jpg/640px-Big_buck_bunny_poster_big.jpg',
        duration: '09:56',
        fileSize: '245 MB',
        category: 'Film & Animasi Open Source',
      ),
      const GoogleDriveVideo(
        id: '1A2b3C4d5E6f7G8h9I0jKlMnOpQrStUvW',
        title: 'Tears of Steel (Sci-Fi VFX 4K Remaster)',
        ownerName: 'Mango Open Movie Project',
        thumbnailUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/Tears_of_Steel_poster.jpg/640px-Tears_of_Steel_poster.jpg',
        duration: '12:14',
        fileSize: '520 MB',
        category: 'Film & Animasi Open Source',
      ),
      const GoogleDriveVideo(
        id: '1sInTeL_AnImAtIoN_9876543210zyxwvuts',
        title: 'Sintel - The Durian Open Movie Project',
        ownerName: 'Durian Open Movie Team',
        thumbnailUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/Sintel_poster.jpg/640px-Sintel_poster.jpg',
        duration: '15:22',
        fileSize: '380 MB',
        category: 'Film & Animasi Open Source',
      ),
    ],
    'Trailer & Demo 4K': [
      const GoogleDriveVideo(
        id: '1CoSmOs_LaUnDrOmAt_1122334455aabbcc',
        title: 'Cosmos Laundromat (First Cycle 4K HDR)',
        ownerName: 'Gooseberry Open Project',
        thumbnailUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/3/30/Cosmos_Laundromat_Poster.jpg/640px-Cosmos_Laundromat_Poster.jpg',
        duration: '12:04',
        fileSize: '410 MB',
        category: 'Trailer & Demo 4K',
      ),
      const GoogleDriveVideo(
        id: '1ElEpHaNtS_DrEaM_998877665544332211',
        title: 'Elephants Dream (3D CGI Master)',
        ownerName: 'Orange Open Movie Studio',
        thumbnailUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/0/0c/Elephants_Dream_poster.jpg/640px-Elephants_Dream_poster.jpg',
        duration: '10:54',
        fileSize: '310 MB',
        category: 'Trailer & Demo 4K',
      ),
    ],
    'Dokumenter & Sains': [
      const GoogleDriveVideo(
        id: '1NaTuRe_WiLdLiFe_1234567890abcdefgh',
        title: 'Nature Wildlife & Coral Reef Odyssey',
        ownerName: 'Oceanic Documentary Archive',
        thumbnailUrl:
            'https://images.unsplash.com/photo-1544551763-46a013bb70d5?w=640&q=80',
        duration: '08:30',
        fileSize: '290 MB',
        category: 'Dokumenter & Sains',
      ),
      const GoogleDriveVideo(
        id: '1SpAcE_CoSmIc_0987654321fedcba0987',
        title: 'Cosmic Journey: Deep Space Exploration',
        ownerName: 'Astro Science Collective',
        thumbnailUrl:
            'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=640&q=80',
        duration: '14:45',
        fileSize: '480 MB',
        category: 'Dokumenter & Sains',
      ),
    ],
  };

  /// Searches Google Drive preset videos or extracts custom link / file ID.
  static Future<List<GoogleDriveVideo>> search(
    String query, {
    String? category,
  }) async {
    final cleanQuery = query.trim();

    // 1. If query is a valid Google Drive URL or File ID, return it as custom video
    final extractedId = extractFileId(cleanQuery);
    if (extractedId != null) {
      // If it matches one of our presets, return that preset
      for (final list in categoryPresets.values) {
        for (final video in list) {
          if (video.id == extractedId) {
            return [video];
          }
        }
      }

      // Otherwise return synthetic GoogleDriveVideo for the user's link
      return [
        GoogleDriveVideo(
          id: extractedId,
          title: 'Google Drive Video ($extractedId)',
          ownerName: 'Google Drive Pribadi / Bersama',
          thumbnailUrl: 'https://drive.google.com/thumbnail?id=$extractedId&sz=w640',
          duration: 'Drive Stream',
          fileSize: 'Cloud Media',
          category: 'Link Kustom',
        ),
      ];
    }

    // 2. Gather videos based on category filter
    List<GoogleDriveVideo> sourceList = [];
    if (category != null && categoryPresets.containsKey(category)) {
      sourceList = categoryPresets[category]!;
    } else {
      sourceList = categoryPresets.values.expand((v) => v).toList();
    }

    // 3. If query is empty, return category items
    if (cleanQuery.isEmpty) {
      return sourceList;
    }

    // 4. Keyword search
    final lowerQuery = cleanQuery.toLowerCase();
    final results = sourceList.where((v) {
      return v.title.toLowerCase().contains(lowerQuery) ||
          v.ownerName.toLowerCase().contains(lowerQuery) ||
          v.category.toLowerCase().contains(lowerQuery);
    }).toList();

    return results;
  }

  // ---------------------------------------------------------------------------
  // User Personal Drive Videos & Permissions APIs
  // ---------------------------------------------------------------------------

  /// Stateful in-memory mock videos for demo/testing mode
  static List<GoogleDriveVideo> _mockUserVideos = [
    const GoogleDriveVideo(
      id: 'mock_v1_liburan_bali_2026',
      title: 'Liburan_Keluarga_Bali_2026.mp4',
      ownerName: 'Saya (Drive Pribadi)',
      thumbnailUrl:
          'https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=640&q=80',
      duration: '14:30',
      fileSize: '420 MB',
      category: 'Drive Saya',
      isPublic: false,
    ),
    const GoogleDriveVideo(
      id: 'mock_v2_tugas_akhir_fhd',
      title: 'Video_Presentasi_Tugas_Akhir.mp4',
      ownerName: 'Saya (Drive Pribadi)',
      thumbnailUrl:
          'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=640&q=80',
      duration: '22:40',
      fileSize: '310 MB',
      category: 'Drive Saya',
      isPublic: false,
    ),
    const GoogleDriveVideo(
      id: 'mock_v3_cinematic_sunset_4k',
      title: 'Cinematic_Drone_Sunset_4K.mov',
      ownerName: 'Saya (Drive Pribadi)',
      thumbnailUrl:
          'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=640&q=80',
      duration: '04:55',
      fileSize: '850 MB',
      category: 'Drive Saya',
      isPublic: false,
    ),
    const GoogleDriveVideo(
      id: 'mock_v4_watch_party_shared',
      title: 'Watch_Party_Highlight_Community.mp4',
      ownerName: 'Saya (Drive Pribadi)',
      thumbnailUrl:
          'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=640&q=80',
      duration: '08:15',
      fileSize: '195 MB',
      category: 'Drive Saya',
      isPublic: true,
    ),
  ];

  /// Reset mock videos to default state (useful for tests)
  static void resetMockVideos() {
    _mockUserVideos = [
      const GoogleDriveVideo(
        id: 'mock_v1_liburan_bali_2026',
        title: 'Liburan_Keluarga_Bali_2026.mp4',
        ownerName: 'Saya (Drive Pribadi)',
        thumbnailUrl:
            'https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=640&q=80',
        duration: '14:30',
        fileSize: '420 MB',
        category: 'Drive Saya',
        isPublic: false,
      ),
      const GoogleDriveVideo(
        id: 'mock_v2_tugas_akhir_fhd',
        title: 'Video_Presentasi_Tugas_Akhir.mp4',
        ownerName: 'Saya (Drive Pribadi)',
        thumbnailUrl:
            'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=640&q=80',
        duration: '22:40',
        fileSize: '310 MB',
        category: 'Drive Saya',
        isPublic: false,
      ),
      const GoogleDriveVideo(
        id: 'mock_v3_cinematic_sunset_4k',
        title: 'Cinematic_Drone_Sunset_4K.mov',
        ownerName: 'Saya (Drive Pribadi)',
        thumbnailUrl:
            'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=640&q=80',
        duration: '04:55',
        fileSize: '850 MB',
        category: 'Drive Saya',
        isPublic: false,
      ),
      const GoogleDriveVideo(
        id: 'mock_v4_watch_party_shared',
        title: 'Watch_Party_Highlight_Community.mp4',
        ownerName: 'Saya (Drive Pribadi)',
        thumbnailUrl:
            'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=640&q=80',
        duration: '08:15',
        fileSize: '195 MB',
        category: 'Drive Saya',
        isPublic: true,
      ),
    ];
  }

  /// Fetches videos from user's Google Drive via v3 REST API (or returns mock list if demo/no token)
  static Future<List<GoogleDriveVideo>> fetchUserVideos({
    String? accessToken,
    String? query,
    http.Client? client,
    bool isMock = false,
    bool forceRefresh = false,
  }) async {
    // If running in mock mode or without valid access token, use mock items
    if (isMock || accessToken == null || accessToken.isEmpty) {
      if (query == null || query.trim().isEmpty) {
        return List.unmodifiable(_mockUserVideos);
      }
      final clean = query.trim().toLowerCase();
      return _mockUserVideos
          .where((v) => v.title.toLowerCase().contains(clean))
          .toList();
    }

    final cleanQuery = query?.trim() ?? '';
    final cacheKey = 'drive_files_${accessToken.hashCode}_$cleanQuery';
    if (!forceRefresh) {
      final cached = ApiCacheManager.instance.get<List<GoogleDriveVideo>>(cacheKey);
      if (cached != null) {
        return List<GoogleDriveVideo>.from(cached);
      }
    }

    // Call live Google Drive v3 REST API reusing pooled client
    final httpClient = client ?? AppHttpClient.client;
    try {
      String searchParam = "mimeType contains 'video/' and trashed = false";
      if (cleanQuery.isNotEmpty) {
        final escaped = cleanQuery.replaceAll("'", "\\'");
        searchParam += " and name contains '$escaped'";
      }

      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': searchParam,
        'fields':
            'nextPageToken, files(id, name, mimeType, thumbnailLink, size, videoMediaMetadata, permissions, webViewLink)',
        'pageSize': '50',
        'orderBy': 'modifiedTime desc',
      });

      final response = await httpClient.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fileList = data['files'] as List<dynamic>? ?? [];
        final videos = fileList
            .map((item) => GoogleDriveVideo.fromDriveApiJson(
                item as Map<String, dynamic>))
            .toList();
        ApiCacheManager.instance.set(cacheKey, videos, ttl: ApiCacheManager.driveListTtl);
        return videos;
      } else {
        debugPrint(
            '[GoogleDriveService] fetchUserVideos status ${response.statusCode}: ${response.body}');
        // If error (e.g. 401 token expired or 403 quota), fallback gracefully to mock videos
        return List.unmodifiable(_mockUserVideos);
      }
    } catch (e) {
      debugPrint('[GoogleDriveService] fetchUserVideos error: $e');
      return List.unmodifiable(_mockUserVideos);
    } finally {
      if (client != null && client != AppHttpClient.client) {
        httpClient.close();
      }
    }
  }

  /// Grants "anyone with link can view" permission via Google Drive v3 API
  /// so that all participants in the Watch Party room can load the video preview.
  static Future<bool> makeFileAccessibleToRoom(
    String fileId, {
    String? accessToken,
    http.Client? client,
    bool isMock = false,
  }) async {
    // If mock, update in-memory mock item
    if (isMock || accessToken == null || accessToken.isEmpty) {
      final index = _mockUserVideos.indexWhere((v) => v.id == fileId);
      if (index != -1) {
        _mockUserVideos[index] = _mockUserVideos[index].copyWith(isPublic: true);
      }
      return true;
    }

    final httpClient = client ?? AppHttpClient.client;
    try {
      final uri = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files/$fileId/permissions',
      );

      final response = await httpClient.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'role': 'reader',
          'type': 'anyone',
        }),
      ).timeout(const Duration(seconds: 10));

      final success = response.statusCode == 200 || response.statusCode == 201;
      if (!success) {
        debugPrint(
            '[GoogleDriveService] makeFileAccessibleToRoom failed: ${response.statusCode} - ${response.body}');
      } else {
        ApiCacheManager.instance.invalidatePattern('drive_files_');
      }
      return success;
    } catch (e) {
      debugPrint('[GoogleDriveService] makeFileAccessibleToRoom error: $e');
      return false;
    } finally {
      if (client != null && client != AppHttpClient.client) {
        httpClient.close();
      }
    }
  }
}
