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
}
