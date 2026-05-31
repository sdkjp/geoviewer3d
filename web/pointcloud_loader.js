/**
 * PointCloudLoader - LAS/LAZ ファイルをブラウザ内で解析
 * JGD2011 平面直角座標系を自動検出して WGS84 (lon/lat) に変換する
 * Web Worker として動作（UI ブロックなし）
 */

// ─────────────────────────────────────────────
// JGD2011 平面直角座標系 → WGS84 変換
// ─────────────────────────────────────────────
// 系番号と原点 (緯度, 経度)
const JGD2011_ZONES = [
  { zone: 1,  lat0: 33.0, lon0: 129.5     },
  { zone: 2,  lat0: 33.0, lon0: 131.0     },
  { zone: 3,  lat0: 36.0, lon0: 132.16667 },
  { zone: 4,  lat0: 33.0, lon0: 133.5     },
  { zone: 5,  lat0: 36.0, lon0: 134.33333 },
  { zone: 6,  lat0: 36.0, lon0: 136.0     }, // 大阪・兵庫・京都・奈良
  { zone: 7,  lat0: 36.0, lon0: 137.16667 }, // 愛知・岐阜・三重
  { zone: 8,  lat0: 36.0, lon0: 138.5     }, // 新潟・長野
  { zone: 9,  lat0: 36.0, lon0: 139.83333 }, // 東京・神奈川・千葉
  { zone: 10, lat0: 40.0, lon0: 140.83333 }, // 青森・秋田・岩手
  { zone: 11, lat0: 44.0, lon0: 140.25    }, // 北海道
  { zone: 12, lat0: 44.0, lon0: 142.25    },
  { zone: 13, lat0: 44.0, lon0: 144.25    },
  { zone: 14, lat0: 26.0, lon0: 142.0     }, // 小笠原
  { zone: 15, lat0: 26.0, lon0: 127.5     }, // 沖縄
  { zone: 16, lat0: 26.0, lon0: 124.0     },
  { zone: 17, lat0: 26.0, lon0: 131.0     },
  { zone: 18, lat0: 20.0, lon0: 136.0     }, // 硫黄島等
  { zone: 19, lat0: 26.0, lon0: 154.0     }, // 南鳥島
];

/**
 * 平面直角座標 (X=northing, Y=easting) → WGS84 (lon, lat)
 * 簡易変換（精度 < 1m）
 */
function jgd2011ToWgs84(X, Y, lat0_deg, lon0_deg) {
  const lat = lat0_deg + X / 110540.0;
  const lat_rad = lat * Math.PI / 180;
  const lon = lon0_deg + Y / (111320.0 * Math.cos(lat_rad));
  return { lon, lat };
}

/**
 * オフセット値から JGD2011 ゾーンを自動検出
 * 全ゾーン・全軸パターンを試し「日本国土の中心に最も近い」ものを選択
 */
function detectJGD2011Zone(offsetX, offsetY) {
  if (Math.abs(offsetX) > 800000 || Math.abs(offsetY) > 800000) return null;
  if (Math.abs(offsetX) < 360 && Math.abs(offsetY) < 90) return null; // 既に地理座標

  let bestScore = Infinity;
  let bestMatch = null;

  for (const z of JGD2011_ZONES) {
    const cosLat = Math.cos(z.lat0 * Math.PI / 180);

    // パターン1: LAS_X=easting(Y軸), LAS_Y=northing(X軸)  ← 日本の測量標準
    // lat = lat0 + LAS_Y/110540, lon = lon0 + LAS_X/(cosLat*111320)
    {
      const lat = z.lat0 + offsetY / 110540.0;
      const lon = z.lon0 + offsetX / (111320.0 * cosLat);
      if (lon >= 122 && lon <= 154 && lat >= 24 && lat <= 46) {
        // ゾーン原点からの距離でスコアリング（ゾーンに対して典型的な範囲内か確認）
        const dLat = Math.abs(lat - z.lat0);
        const dLon = Math.abs(lon - z.lon0);
        // ゾーンの有効範囲内(±3°)かつ原点に最も近いものを選択
        if (dLat <= 3 && dLon <= 3) {
          const score = dLat + dLon;
          if (score < bestScore) {
            bestScore = score;
            bestMatch = { zone: z.zone, lat0: z.lat0, lon0: z.lon0, swapped: false };
          }
        }
      }
    }
    // パターン2: LAS_X=northing(X軸), LAS_Y=easting(Y軸)  ← 一部ソフト
    {
      const lat = z.lat0 + offsetX / 110540.0;
      const lon = z.lon0 + offsetY / (111320.0 * cosLat);
      if (lon >= 122 && lon <= 154 && lat >= 24 && lat <= 46) {
        const dLat = Math.abs(lat - z.lat0);
        const dLon = Math.abs(lon - z.lon0);
        if (dLat <= 3 && dLon <= 3) {
          const score = dLat + dLon;
          if (score < bestScore) {
            bestScore = score;
            bestMatch = { zone: z.zone, lat0: z.lat0, lon0: z.lon0, swapped: true };
          }
        }
      }
    }
  }
  return bestMatch;
}

// ─────────────────────────────────────────────
// LAS バイナリパーサ
// LAS 1.2 仕様に基づく正確な min/max バイト位置
// Max X (179), Min X (187), Max Y (195), Min Y (203), Max Z (211), Min Z (219)
// ─────────────────────────────────────────────
function parseLasBuffer(buffer, progressCb, crsHint) {
  const view = new DataView(buffer);
  const sig = String.fromCharCode(
    view.getUint8(0), view.getUint8(1),
    view.getUint8(2), view.getUint8(3)
  );
  if (sig !== 'LASF') throw new Error('Not a valid LAS file (signature: ' + sig + ')');

  const versionMajor = view.getUint8(24);
  const versionMinor = view.getUint8(25);

  const pointFormat     = view.getUint8(104);
  const pointDataOffset = view.getUint32(96, true);
  const pointRecordLen  = view.getUint16(105, true);
  let   numPoints       = view.getUint32(107, true);
  if (numPoints === 0 && versionMinor >= 4) {
    numPoints = view.getUint32(247, true); // LAS 1.4 64-bit
  }

  const scaleX   = view.getFloat64(131, true);
  const scaleY   = view.getFloat64(139, true);
  const scaleZ   = view.getFloat64(147, true);
  const offsetX  = view.getFloat64(155, true);
  const offsetY  = view.getFloat64(163, true);
  const offsetZ  = view.getFloat64(171, true);

  // LAS 1.2 spec: MaxX(179) MinX(187) MaxY(195) MinY(203) MaxZ(211) MinZ(219)
  const maxX = view.getFloat64(179, true);
  const minX = view.getFloat64(187, true);
  const maxY = view.getFloat64(195, true);
  const minY = view.getFloat64(203, true);
  const maxZ = view.getFloat64(211, true);
  const minZ = view.getFloat64(219, true);

  // RGB 有無: Format 2, 3, 5, 7, 8 は RGB 含む
  const hasRgb = [2, 3, 5, 7, 8].includes(pointFormat);

  // RGB のバイトオフセット (フォーマットごとに異なる)
  // Format 0: 20b  Format 1: 28b  Format 2: 20b (RGB at 20)
  // Format 3: 28b (RGB at 28)  Format 5: 28b (RGB at 28)  Format 6: 30b
  // Format 7: 36b (RGB at 30)  Format 8: 38b (RGB at 30)
  const rgbOffset = {
    2: 20, 3: 28, 5: 28, 7: 30, 8: 30,
  }[pointFormat] || 20;

  // ──────────────────────────────────────────
  // 座標系の自動判定
  // ──────────────────────────────────────────
  const isGeo = Math.abs(offsetX) < 360 && Math.abs(offsetY) < 90 &&
                Math.abs(maxX)    < 360 && Math.abs(maxY)    < 90;

  let jgdInfo = null;
  let coordMode = 'unknown';

  if (isGeo) {
    coordMode = 'geographic'; // 既に lon/lat
  } else if (crsHint && crsHint.zone) {
    // CRS ヒントが指定されている場合は優先
    const z = JGD2011_ZONES.find(z => z.zone === crsHint.zone);
    if (z) {
      jgdInfo = { zone: z.zone, lat0: z.lat0, lon0: z.lon0, swapped: crsHint.swapped || false };
      coordMode = `jgd2011_zone${z.zone}_hint`;
    }
  }
  if (!coordMode) {
    jgdInfo = detectJGD2011Zone(offsetX, offsetY);
    if (jgdInfo) {
      coordMode = `jgd2011_zone${jgdInfo.zone}`;
    } else {
      coordMode = 'projected_unknown'; // UTM 等、GCP 登録必要
    }
  }

  // ──────────────────────────────────────────
  // 間引き率（最大表示点数）
  // ──────────────────────────────────────────
  const MAX_DISPLAY = 800_000;
  const skip = Math.max(1, Math.ceil(numPoints / MAX_DISPLAY));

  const points = [];
  let bytePos = pointDataOffset;

  const totalBytes = buffer.byteLength;
  let lastProgressPct = 0;

  for (let i = 0; i < numPoints; i += skip) {
    if (bytePos + pointRecordLen > totalBytes) break;

    const xi = view.getInt32(bytePos,     true);
    const yi = view.getInt32(bytePos + 4, true);
    const zi = view.getInt32(bytePos + 8, true);

    const rawX = xi * scaleX + offsetX;
    const rawY = yi * scaleY + offsetY;
    const rawZ = zi * scaleZ + offsetZ;

    let lon, lat, h;

    if (coordMode === 'geographic') {
      lon = rawX; lat = rawY; h = rawZ;
    } else if (jgdInfo) {
      // JGD2011 平面直角 → WGS84
      let northing, easting;
      if (jgdInfo.swapped) {
        // LAS_X = easting, LAS_Y = northing
        easting  = rawX;
        northing = rawY;
      } else {
        // LAS_X = northing, LAS_Y = easting (標準)
        northing = rawX;
        easting  = rawY;
      }
      const geo = jgd2011ToWgs84(northing, easting, jgdInfo.lat0, jgdInfo.lon0);
      lon = geo.lon; lat = geo.lat; h = rawZ;
    } else {
      // 投影座標不明: 生値をそのまま
      lon = rawX; lat = rawY; h = rawZ;
    }

    let r = 160, g = 160, b = 160;
    if (hasRgb) {
      const rp = bytePos + rgbOffset;
      if (rp + 6 <= totalBytes) {
        r = Math.min(255, Math.floor(view.getUint16(rp,     true) / 256));
        g = Math.min(255, Math.floor(view.getUint16(rp + 2, true) / 256));
        b = Math.min(255, Math.floor(view.getUint16(rp + 4, true) / 256));
      }
    } else {
      // 高さで色付け (灰→青)
      const intensity = view.getUint16(bytePos + 12, true);
      const v = Math.min(255, Math.floor(intensity / 256));
      r = v; g = v; b = Math.min(255, v + 60);
    }

    points.push({ x: lon, y: lat, z: h, r, g, b });
    bytePos += pointRecordLen * skip;

    // 進捗通知
    const pct = Math.floor(bytePos / totalBytes * 100);
    if (progressCb && pct > lastProgressPct + 5) {
      lastProgressPct = pct;
      progressCb(pct);
    }
  }

  // 中心座標を地理座標で計算
  let centerLon, centerLat;
  if (coordMode === 'geographic') {
    centerLon = (minX + maxX) / 2;
    centerLat = (minY + maxY) / 2;
  } else if (jgdInfo) {
    // JGD2011: header の min/max は投影座標なので中間点を変換
    const cx = (minX + maxX) / 2;
    const cy = (minY + maxY) / 2;
    // swapped=true: LAS_X=easting(cx), LAS_Y=northing(cy)
    // swapped=false: LAS_X=northing(cx), LAS_Y=easting(cy)
    const northing = jgdInfo.swapped ? cy : cx;
    const easting  = jgdInfo.swapped ? cx : cy;
    const geo = jgd2011ToWgs84(northing, easting, jgdInfo.lat0, jgdInfo.lon0);
    centerLon = geo.lon; centerLat = geo.lat;
  } else {
    // 実点から中心を計算（投影座標不明の場合）
    if (points.length > 0) {
      centerLon = points.reduce((s, p) => s + p.x, 0) / points.length;
      centerLat = points.reduce((s, p) => s + p.y, 0) / points.length;
    } else {
      centerLon = 0; centerLat = 0;
    }
  }

  return {
    points,
    isProjected: coordMode !== 'geographic',
    autoConverted: !!jgdInfo,
    coordMode,
    jgdZone: jgdInfo ? jgdInfo.zone : null,
    coordinateInfo: jgdInfo
      ? `JGD2011 平面直角 第${jgdInfo.zone}系 → WGS84 自動変換済み`
      : coordMode === 'geographic'
        ? '地理座標 (経緯度)'
        : '投影座標 (GCP登録が必要です)',
    totalPoints: numPoints,
    loadedPoints: points.length,
    bounds: { minX, maxX, minY, maxY, minZ, maxZ },
    center: { lon: centerLon, lat: centerLat },
  };
}

// ─────────────────────────────────────────────
// Worker メッセージハンドラ
// ─────────────────────────────────────────────
self.onmessage = async function (e) {
  const { type, id, buffer, filename, crsHint } = e.data;
  // crsHint: { zone: number, swapped: boolean } - 自動検出を上書き

  if (type !== 'parse') return;

  try {
    self.postMessage({ type: 'progress', id, progress: 5, message: 'ファイル解析中...' });

    const lowerName = (filename || '').toLowerCase();
    if (lowerName.endsWith('.laz')) {
      self.postMessage({
        type: 'error', id,
        message: 'LAZ ファイルは LAS に変換してから読み込んでください（GitHub Actions で自動変換できます）',
      });
      return;
    }

    const result = parseLasBuffer(buffer, (pct) => {
      self.postMessage({ type: 'progress', id, progress: pct, message: `点群読み込み中... ${pct}%` });
    }, crsHint);

    self.postMessage({
      type: 'done',
      id,
      points: result.points,
      isProjected: result.isProjected,
      autoConverted: result.autoConverted,
      coordMode: result.coordMode,
      jgdZone: result.jgdZone,
      coordinateInfo: result.coordinateInfo,
      totalPoints: result.totalPoints,
      loadedPoints: result.loadedPoints,
      bounds: result.bounds,
      center: result.center,
    });
  } catch (err) {
    self.postMessage({
      type: 'error',
      id,
      message: err.message || String(err),
    });
  }
};
