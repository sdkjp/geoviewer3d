import 'dart:math';
import '../models/layer.dart';

/// 点群座標 (x, y, z) → 地理座標 (lon, lat, h) の 3D アフィン変換を
/// 4 対の GCP から最小二乗法で推定する
class GcpTransform {
  // 変換行列 A (3x4) を格納: lon = A[0]*x + A[1]*y + A[2]*z + A[3]
  final List<double> _matLon; // 4係数
  final List<double> _matLat;
  final List<double> _matH;
  final double _residualRms;

  const GcpTransform._(this._matLon, this._matLat, this._matH, this._residualRms);

  double get residualRms => _residualRms;

  /// 4点以上の GcpPair からアフィン変換を推定
  static GcpTransform estimate(List<GcpPair> gcpPairs) {
    assert(gcpPairs.length >= 4, 'GCP は4点以上必要です');
    final n = gcpPairs.length;

    // 設計行列 A (n × 4)
    final A = List.generate(n, (i) {
      final pc = gcpPairs[i].pcPoint;
      return [pc[0], pc[1], pc[2], 1.0];
    });

    final bLon = gcpPairs.map((g) => g.mapPoint.lon).toList();
    final bLat = gcpPairs.map((g) => g.mapPoint.lat).toList();
    final bH = gcpPairs.map((g) => g.mapPoint.height).toList();

    final matLon = _leastSquares(A, bLon);
    final matLat = _leastSquares(A, bLat);
    final matH = _leastSquares(A, bH);

    // RMS 残差 (lon/lat のみ, 度単位 → メートル換算)
    double sumSq = 0;
    for (int i = 0; i < n; i++) {
      final row = A[i];
      final predLon = _dot(matLon, row);
      final predLat = _dot(matLat, row);
      final dLon = (predLon - bLon[i]) * 111320 * cos(bLat[i] * pi / 180);
      final dLat = (predLat - bLat[i]) * 110540;
      sumSq += dLon * dLon + dLat * dLat;
    }
    final rms = sqrt(sumSq / n);

    return GcpTransform._(matLon, matLat, matH, rms);
  }

  /// 点群座標 → 地理座標
  GeoPoint transform(double x, double y, double z) {
    final row = [x, y, z, 1.0];
    return GeoPoint(
      _dot(_matLon, row),
      _dot(_matLat, row),
      _dot(_matH, row),
    );
  }

  /// 点群の全点を変換 (List<{x,y,z,r,g,b}> → List<{x:lon,y:lat,z:h,r,g,b}>)
  List<Map<String, dynamic>> transformPoints(List<Map<String, dynamic>> points) {
    return points.map((p) {
      final geo = transform(
        (p['x'] as num).toDouble(),
        (p['y'] as num).toDouble(),
        (p['z'] as num).toDouble(),
      );
      return {
        'x': geo.lon,
        'y': geo.lat,
        'z': geo.height,
        'r': p['r'] ?? 128,
        'g': p['g'] ?? 128,
        'b': p['b'] ?? 128,
      };
    }).toList();
  }

  // ─────────────────────────────────────────────
  // 最小二乗法 (正規方程式 A'A x = A'b)
  // ─────────────────────────────────────────────
  static List<double> _leastSquares(List<List<double>> A, List<double> b) {
    final m = A.length;
    final n = A[0].length;

    // A'A
    final AtA = List.generate(n, (_) => List.filled(n, 0.0));
    for (int i = 0; i < m; i++) {
      for (int j = 0; j < n; j++) {
        for (int k = 0; k < n; k++) {
          AtA[j][k] += A[i][j] * A[i][k];
        }
      }
    }

    // A'b
    final Atb = List.filled(n, 0.0);
    for (int i = 0; i < m; i++) {
      for (int j = 0; j < n; j++) {
        Atb[j] += A[i][j] * b[i];
      }
    }

    return _solveLinear(AtA, Atb);
  }

  // ガウスの消去法
  static List<double> _solveLinear(List<List<double>> A, List<double> b) {
    final n = b.length;
    final aug = List.generate(n, (i) => [...A[i], b[i]]);

    for (int col = 0; col < n; col++) {
      int pivot = col;
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > aug[pivot][col].abs()) pivot = row;
      }
      final tmp = aug[col];
      aug[col] = aug[pivot];
      aug[pivot] = tmp;

      final pivVal = aug[col][col];
      if (pivVal.abs() < 1e-12) continue;

      for (int row = col + 1; row < n; row++) {
        final factor = aug[row][col] / pivVal;
        for (int k = col; k <= n; k++) {
          aug[row][k] -= factor * aug[col][k];
        }
      }
    }

    final x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      x[i] = aug[i][n];
      for (int j = i + 1; j < n; j++) {
        x[i] -= aug[i][j] * x[j];
      }
      x[i] /= aug[i][i];
    }
    return x;
  }

  static double _dot(List<double> a, List<double> b) {
    double s = 0;
    for (int i = 0; i < a.length; i++) s += a[i] * b[i];
    return s;
  }
}
