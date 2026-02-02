import '../models/embedding_model.dart';
import '../models/match_result_model.dart';

/// M3: Face Matching Module
/// Identifies who a face belongs to by comparing embeddings
/// Uses Cosine Similarity or KNN algorithm (NOT a neural network)
class FaceMatchingModule {
  static const String modelName = 'Face Matcher (Cosine Similarity)';
  static const double defaultSimilarityThreshold = 0.60;
  static const int knnK = 1; // Use 1-NN for single match

  /// Match incoming embedding against database embeddings
  /// Returns the best match with highest similarity
  MatchResult matchFace(
    List<double> incomingEmbedding,
    List<FaceEmbedding> databaseEmbeddings, {
    double similarityThreshold = defaultSimilarityThreshold,
  }) {
    if (databaseEmbeddings.isEmpty) {
      return MatchResult(
        identityType: 'unknown',
        similarity: 0,
      );
    }

    // Calculate cosine similarity with all database embeddings
    double bestSimilarity = -1;
    FaceEmbedding? bestMatch;

    for (final dbEmbedding in databaseEmbeddings) {
      final similarity = cosineSimilarity(incomingEmbedding, dbEmbedding.vector);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestMatch = dbEmbedding;
      }
    }

    // Check if similarity exceeds threshold
    if (bestMatch != null && bestSimilarity >= similarityThreshold) {
      return MatchResult(
        identityType: 'known',
        studentId: bestMatch.studentId,
        similarity: bestSimilarity,
      );
    }

    return MatchResult(
      identityType: 'unknown',
      similarity: bestSimilarity,
    );
  }

  /// Calculate cosine similarity between two vectors
  /// Range: [-1, 1], where 1 = identical vectors
  double cosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length) return 0;

    // Calculate dot product
    double dotProduct = 0;
    double norm1 = 0;
    double norm2 = 0;

    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      norm1 += vec1[i] * vec1[i];
      norm2 += vec2[i] * vec2[i];
    }

    norm1 = _sqrt(norm1);
    norm2 = _sqrt(norm2);

    if (norm1 == 0 || norm2 == 0) return 0;

    return dotProduct / (norm1 * norm2);
  }

  /// Calculate Euclidean distance between two vectors
  double euclideanDistance(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length) return double.infinity;

    double sum = 0;
    for (int i = 0; i < vec1.length; i++) {
      final diff = vec1[i] - vec2[i];
      sum += diff * diff;
    }

    return _sqrt(sum);
  }

  /// K-Nearest Neighbors matching (for more robust identification)
  List<MatchResult> knnMatch(
    List<double> incomingEmbedding,
    List<FaceEmbedding> databaseEmbeddings, {
    int k = knnK,
    double similarityThreshold = defaultSimilarityThreshold,
  }) {
    if (databaseEmbeddings.isEmpty) {
      return [
        MatchResult(
          identityType: 'unknown',
          similarity: 0,
        ),
      ];
    }

    // Calculate similarity for all embeddings
    final similarities = databaseEmbeddings.map((emb) {
      final sim = cosineSimilarity(incomingEmbedding, emb.vector);
      return MapEntry(emb, sim);
    }).toList();

    // Sort by similarity (descending)
    similarities.sort((a, b) => b.value.compareTo(a.value));

    // Get top K matches above threshold
    final topMatches = similarities
        .take(k)
        .where((entry) => entry.value >= similarityThreshold)
        .map((entry) {
      return MatchResult(
        identityType: 'known',
        studentId: entry.key.studentId,
        similarity: entry.value,
      );
    }).toList();

    return topMatches.isNotEmpty
        ? topMatches
        : [
            MatchResult(
              identityType: 'unknown',
              similarity: similarities[0].value,
            ),
          ];
  }

  /// Get matching statistics
  Map<String, dynamic> getMatchingStats(
    List<double> incomingEmbedding,
    List<FaceEmbedding> databaseEmbeddings,
  ) {
    if (databaseEmbeddings.isEmpty) {
      return {
        'total_embeddings': 0,
        'best_similarity': 0,
        'threshold': defaultSimilarityThreshold,
      };
    }

    double bestSim = -1;
    double worstSim = 2;

    for (final emb in databaseEmbeddings) {
      final sim = cosineSimilarity(incomingEmbedding, emb.vector);
      if (sim > bestSim) bestSim = sim;
      if (sim < worstSim) worstSim = sim;
    }

    return {
      'total_embeddings': databaseEmbeddings.length,
      'best_similarity': bestSim.toStringAsFixed(4),
      'worst_similarity': worstSim.toStringAsFixed(4),
      'threshold': defaultSimilarityThreshold,
    };
  }

  /// Simple square root helper
  double _sqrt(double x) {
    if (x == 0) return 0;
    double z = x;
    double result = 0;
    while ((z - result).abs() > 1e-7) {
      result = z;
      z = 0.5 * (z + x / z);
    }
    return z;
  }
}
