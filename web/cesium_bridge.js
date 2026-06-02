/**
 * CesiumBridge - Flutter Web ↔ Cesium.js 通信レイヤー
 * Flutter の dart:js_interop からこの window.CesiumBridge を呼び出す
 */
window.CesiumBridge = (function () {
  'use strict';

  let viewer = null;
  let gcpPickingMode = false;
  let gcpPickCallback = null;
  const layers = {};          // id → { type, primitive/entity/... }
  const annotations = {};    // id → entity

  // ──────────────────────────────────────────────
  // 初期化
  // ──────────────────────────────────────────────
  function init(options) {
    if (viewer) return true; // 既に初期化済み
    options = options || {};

    // Cesium Ion を無効化し、自分のタイルだけ使用
    Cesium.Ion.defaultAccessToken = undefined;

    // コンテナは div 要素または文字列 ID
    const container = options.container || 'cesiumContainer';

    viewer = new Cesium.Viewer(container, {
      // baseLayer は後で設定
      baseLayerPicker: false,
      geocoder: false,
      homeButton: false,
      sceneModePicker: false,
      navigationHelpButton: false,
      animation: false,
      timeline: false,
      fullscreenButton: false,
      vrButton: false,
      infoBox: false,
      selectionIndicator: false,
      shadows: false,
      shouldAnimate: true,
      // Cesium Ion のデフォルト地形を無効化
      terrainProvider: new Cesium.EllipsoidTerrainProvider(),
    });

    // Cesium のデフォルトイメージリーを削除し、地理院地図を追加
    viewer.imageryLayers.removeAll();
    viewer.imageryLayers.addImageryProvider(
      new Cesium.UrlTemplateImageryProvider({
        url: 'https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png',
        credit: '地理院地図',
        maximumLevel: 18,
        minimumLevel: 2,
      })
    );

    // 深度テスト有効化（地面へのクランプ）
    viewer.scene.globe.depthTestAgainstTerrain = true;

    // 大気・霧を軽くして見やすく
    viewer.scene.skyAtmosphere.show = true;
    viewer.scene.fog.enabled = false;

    // 初期カメラ: 日本全体が見える位置
    viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(135.5, 35.0, 1200000),
      orientation: { heading: 0, pitch: -Cesium.Math.PI_OVER_TWO, roll: 0 },
      duration: 0,
    });

    // クリックハンドラ（GCP + 歩行モード共用）
    const handler = new Cesium.ScreenSpaceEventHandler(viewer.scene.canvas);
    handler.setInputAction(function (movement) {
      const cartesian = viewer.camera.pickEllipsoid(movement.position);
      if (!cartesian) return;
      const carto = Cesium.Cartographic.fromCartesian(cartesian);
      const lon = Cesium.Math.toDegrees(carto.longitude);
      const lat = Cesium.Math.toDegrees(carto.latitude);
      const h   = carto.height;

      // 歩行モード: クリック地点に移動
      if (_walkMode) {
        enableWalkingMode(lon, lat);
        return;
      }

      // GCP ピッキング
      if (gcpPickingMode && gcpPickCallback) {
        gcpPickCallback(JSON.stringify({ lon, lat, height: h }));
      }
    }, Cesium.ScreenSpaceEventType.LEFT_CLICK);

    // viewer への外部参照を保存
    window._cesiumViewerRef = viewer;
    return true;
  }

  // ──────────────────────────────────────────────
  // カメラ制御
  // ──────────────────────────────────────────────
  function flyTo(lon, lat, height, heading, pitch, duration) {
    if (!viewer) return;
    viewer.camera.flyTo({
      destination: Cesium.Cartesian3.fromDegrees(lon, lat, height),
      orientation: {
        heading: Cesium.Math.toRadians(heading || 0),
        pitch: Cesium.Math.toRadians(pitch || -45),
        roll: 0,
      },
      duration: duration !== undefined ? duration : 1.5,
    });
  }

  function getCameraState() {
    if (!viewer) return null;
    const pos = viewer.camera.positionCartographic;
    return JSON.stringify({
      lon: Cesium.Math.toDegrees(pos.longitude),
      lat: Cesium.Math.toDegrees(pos.latitude),
      height: pos.height,
      heading: Cesium.Math.toDegrees(viewer.camera.heading),
      pitch: Cesium.Math.toDegrees(viewer.camera.pitch),
    });
  }

  // ──────────────────────────────────────────────
  // 歩行モード状態
  // ──────────────────────────────────────────────
  let _walkMode = false;
  const WALK_EYE_HEIGHT = 1.7;   // 目線の高さ (m)
  // ジョイスティックは 16ms 周期 (≈62.5 tick/s) で呼ばれる
  // WALK_SPEED_MPS * 62.5 ≈ 実効速度 [m/s]
  // 0.04 → フルスロットル時 約 2.5 m/s (ゆっくり歩き相当)
  const WALK_SPEED_MPS  = 0.04;  // m/tick

  // ジョイスティック移動 (dx, dy: -1.0 ~ 1.0)
  function moveCamera(dx, dy, dz) {
    if (!viewer) return;
    if (_walkMode) {
      _moveWalking(dx, dy);
      return;
    }
    const h = Math.max(10, viewer.camera.positionCartographic.height);
    const speed = h * 0.004;
    // roll=0 を保ちながら水平移動
    const heading = viewer.camera.heading;
    const pos = viewer.camera.positionCartographic;
    const cosLat = Math.cos(pos.latitude);
    const dLon = (dx * speed * Math.cos(heading) + (-dy) * speed * Math.sin(heading)) / (111320 * cosLat);
    const dLat = ((-dy) * speed * Math.cos(heading) - dx * speed * Math.sin(heading)) / 110540;
    viewer.camera.setView({
      destination: Cesium.Cartesian3.fromDegrees(
        Cesium.Math.toDegrees(pos.longitude) + dLon * Cesium.Math.toDegrees(1),
        Cesium.Math.toDegrees(pos.latitude)  + dLat * Cesium.Math.toDegrees(1),
        Math.max(5, pos.height)
      ),
      orientation: {
        heading: heading,
        pitch: viewer.camera.pitch,
        roll: 0,
      },
    });
    if (dz !== 0) viewer.camera.zoomIn(Math.max(5, pos.height) * dz * 0.3);
  }

  // 視点回転 - setView で roll=0 を常に保証
  function rotateCamera(dHeading, dPitch) {
    if (!viewer) return;
    if (_walkMode) {
      _rotateWalking(dHeading, dPitch);
      return;
    }
    const headingRad = viewer.camera.heading + Cesium.Math.toRadians(dHeading * 1.5);
    const pitchDeg   = Cesium.Math.toDegrees(viewer.camera.pitch);
    // 俯瞰モード: pitch を -89° 〜 -5° にクランプ
    const newPitchDeg = Math.max(-89, Math.min(-5, pitchDeg + dPitch * 1.5));
    viewer.camera.setView({
      destination: viewer.camera.position,
      orientation: {
        heading: headingRad,
        pitch: Cesium.Math.toRadians(newPitchDeg),
        roll: 0,
      },
    });
  }

  // ──────────────────────────────────────────────
  // 歩行モード関数
  // ──────────────────────────────────────────────
  function enableWalkingMode(lon, lat) {
    if (!viewer) return;
    _walkMode = true;
    const currentHeading = viewer.camera.heading;
    // 地面近くでの z-fighting を防ぐため depthTest を無効化
    viewer.scene.globe.depthTestAgainstTerrain = false;
    viewer.camera.setView({
      destination: Cesium.Cartesian3.fromDegrees(lon, lat, WALK_EYE_HEIGHT),
      orientation: {
        heading: currentHeading,
        pitch: 0,    // 水平を向く
        roll: 0,
      },
    });
    if (viewer.scene.canvas) {
      viewer.scene.canvas.style.cursor = 'crosshair';
    }
  }

  function disableWalkingMode() {
    _walkMode = false;
    // 通常モードに戻したら depthTest を再有効化
    if (viewer) {
      viewer.scene.globe.depthTestAgainstTerrain = true;
    }
    if (viewer && viewer.scene.canvas) {
      viewer.scene.canvas.style.cursor = '';
    }
  }

  function isWalkingMode() { return _walkMode; }

  // 歩行移動: 高さ固定で水平移動
  function _moveWalking(dx, dy) {
    const heading = viewer.camera.heading;
    const pos = viewer.camera.positionCartographic;
    const cosLat = Math.cos(pos.latitude);
    const spd = WALK_SPEED_MPS;

    // heading は北=0°、東=90° (Cesium convention)
    // forward (dy<0=前進) は heading 方向に進む
    const fwd = -dy * spd;
    const rgt = dx * spd;

    const dLon = (fwd * Math.sin(heading) + rgt * Math.cos(heading)) / (111320 * cosLat);
    const dLat = (fwd * Math.cos(heading) - rgt * Math.sin(heading)) / 110540;

    viewer.camera.setView({
      destination: Cesium.Cartesian3.fromDegrees(
        Cesium.Math.toDegrees(pos.longitude) + Cesium.Math.toDegrees(dLon),
        Cesium.Math.toDegrees(pos.latitude)  + Cesium.Math.toDegrees(dLat),
        WALK_EYE_HEIGHT
      ),
      orientation: {
        heading: heading,
        pitch: viewer.camera.pitch,
        roll: 0,
      },
    });
  }

  // 歩行視点回転: heading (左右) + pitch (-30°〜+20°)
  function _rotateWalking(dHeading, dPitch) {
    const heading  = viewer.camera.heading + Cesium.Math.toRadians(dHeading * 1.5);
    const pitchDeg = Cesium.Math.toDegrees(viewer.camera.pitch);
    const newPitchDeg = Math.max(-30, Math.min(20, pitchDeg + dPitch * 1.0));
    viewer.camera.setView({
      destination: viewer.camera.position,
      orientation: {
        heading,
        pitch: Cesium.Math.toRadians(newPitchDeg),
        roll: 0,
      },
    });
  }

  // ──────────────────────────────────────────────
  // 地図タイル切替
  // ──────────────────────────────────────────────
  const GSI_TILES = {
    standard: 'https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png',
    photo: 'https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg',
    pale: 'https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png',
    blank: 'https://cyberjapandata.gsi.go.jp/xyz/blank/{z}/{x}/{y}.png',
  };

  function setBaseMap(type) {
    if (!viewer) return;
    const url = GSI_TILES[type] || GSI_TILES.standard;
    viewer.imageryLayers.removeAll();
    viewer.imageryLayers.addImageryProvider(
      new Cesium.UrlTemplateImageryProvider({
        url,
        credit: '地理院地図',
        maximumLevel: 18,
      })
    );
  }

  // ──────────────────────────────────────────────
  // 点群レイヤー (JSON 経由 - Flutter/Dart から呼ぶ場合)
  // ──────────────────────────────────────────────
  function addPointCloudLayer(id, pointsJson, options) {
    if (!viewer) return;
    const points = typeof pointsJson === 'string' ? JSON.parse(pointsJson) : pointsJson;
    return _addPointCloudFromArray(id, points, options || {});
  }

  // TypedArray 直接渡し (高速 - JS から直接呼ぶ場合)
  function addPointCloudDirect(id, pointsArray, options) {
    if (!viewer) return;
    // AR 用に生データを保存 (center があれば)
    if (options && options.center && window._arStoreCloud) {
      window._arStoreCloud(id, pointsArray, options.center);
    }
    return _addPointCloudFromArray(id, pointsArray, options || {});
  }

  function _addPointCloudFromArray(id, points, options) {
    removeLayer(id);
    const n = points.length;
    if (n === 0) return false;

    // PointPrimitiveCollection を使う（最も効率的）
    const collection = viewer.scene.primitives.add(
      new Cesium.PointPrimitiveCollection()
    );

    const ptSize = options.pointSize || 3.0;
    const CHUNK = 50000; // 一度に追加する点数

    function addChunk(start) {
      const end = Math.min(start + CHUNK, n);
      for (let i = start; i < end; i++) {
        const p = points[i];
        const r = p.r !== undefined ? p.r : 180;
        const g = p.g !== undefined ? p.g : 180;
        const b = p.b !== undefined ? p.b : 180;
        collection.add({
          position: Cesium.Cartesian3.fromDegrees(p.x, p.y, p.z || 0),
          color: new Cesium.Color(r/255, g/255, b/255, 1),
          pixelSize: ptSize,
        });
      }
      if (end < n) {
        // 次のチャンクを非同期で
        setTimeout(() => addChunk(end), 0);
      }
    }

    addChunk(0);
    layers[id] = { type: 'pointcloud', primitive: collection };
    return true;
  }

  // ──────────────────────────────────────────────
  // PDF レイヤー (PowerPoint 風 ─ 移動・拡縮・回転)
  // ──────────────────────────────────────────────

  // PDF の変換状態を保持
  const _pdfStates = {}; // id → { centerLon, centerLat, widthM, heightM, rotDeg, alpha, imageDataUrl }

  /** 地理座標での4隅を計算 (中心 + サイズ + 回転) */
  function _computePdfCorners(centerLon, centerLat, widthM, heightM, rotDeg) {
    const rot = rotDeg * Math.PI / 180;
    const cosR = Math.cos(rot), sinR = Math.sin(rot);
    const cosLat = Math.cos(centerLat * Math.PI / 180);
    const latPerM = 1 / 110540;
    const lonPerM = 1 / (111320 * cosLat);
    const hw = widthM / 2, hh = heightM / 2;
    // 左上,右上,右下,左下 の順 (逆時計回り)
    return [
      [-hw,  hh], [ hw,  hh], [ hw, -hh], [-hw, -hh],
    ].map(([dx, dy]) => {
      const rdx = dx * cosR - dy * sinR;
      const rdy = dx * sinR + dy * cosR;
      return Cesium.Cartesian3.fromDegrees(
        centerLon + rdx * lonPerM,
        centerLat + rdy * latPerM,
        1 // 地面から 1m 上（z-fighting 防止）
      );
    });
  }

  /** PDF を地図に貼り付け (初回 or 更新) */
  function placePdfLayer(id, imageDataUrl, centerLon, centerLat, widthM, heightM, rotDeg, alpha) {
    if (!viewer) return;
    alpha = alpha !== undefined ? alpha : 0.7;

    _pdfStates[id] = { centerLon, centerLat, widthM, heightM, rotDeg, alpha, imageDataUrl };
    _refreshPdfEntity(id);
    return true;
  }

  function _refreshPdfEntity(id) {
    const s = _pdfStates[id];
    if (!s) return;
    // 既存エンティティ削除
    if (layers[id]?.entity) viewer.entities.remove(layers[id].entity);

    const corners = _computePdfCorners(s.centerLon, s.centerLat, s.widthM, s.heightM, s.rotDeg);
    const entity = viewer.entities.add({
      polygon: {
        hierarchy: new Cesium.PolygonHierarchy(corners),
        material: new Cesium.ImageMaterialProperty({
          image: s.imageDataUrl,
          transparent: true,
          color: new Cesium.Color(1, 1, 1, s.alpha),
        }),
        perPositionHeight: true,
        outline: false,
        arcType: Cesium.ArcType.NONE,
      },
    });
    layers[id] = { type: 'pdf', entity };
  }

  /** PDF の変換を更新 (ドラッグ中にリアルタイム呼ぶ) */
  function updatePdfTransform(id, centerLon, centerLat, widthM, heightM, rotDeg, alpha) {
    if (!_pdfStates[id]) return;
    Object.assign(_pdfStates[id], { centerLon, centerLat, widthM, heightM, rotDeg, alpha });
    _refreshPdfEntity(id);
  }

  /** PDF の4隅 + 中心のスクリーン座標を返す (Flutter ハンドル配置用) */
  function getPdfScreenHandles(id) {
    const s = _pdfStates[id];
    if (!s || !viewer) return null;
    const corners = _computePdfCorners(s.centerLon, s.centerLat, s.widthM, s.heightM, s.rotDeg);
    const pts = corners.map(c => {
      const sc = viewer.scene.cartesianToCanvasCoordinates(c);
      return sc ? { x: sc.x, y: sc.y } : null;
    });
    // 中心点も追加
    const csc = viewer.scene.cartesianToCanvasCoordinates(
      Cesium.Cartesian3.fromDegrees(s.centerLon, s.centerLat, 1)
    );
    pts.push(csc ? { x: csc.x, y: csc.y } : null);
    return JSON.stringify(pts);
  }

  /** カメラ中心にデフォルトサイズで PDF を仮置き */
  function initPdfPlacement(id, imageDataUrl, aspectRatio) {
    if (!viewer) return;
    const pos = viewer.camera.positionCartographic;
    const h = pos.height;
    // 高度に応じて初期サイズ (画面の ~30%が埋まるくらい)
    const widthM  = h * 0.5;
    const heightM = widthM / (aspectRatio || 1.414); // A4縦のデフォルト
    const lon = Cesium.Math.toDegrees(pos.longitude);
    const lat = Cesium.Math.toDegrees(pos.latitude);
    placePdfLayer(id, imageDataUrl, lon, lat, widthM, heightM, 0, 0.7);
    return JSON.stringify({ centerLon: lon, centerLat: lat, widthM, heightM, rotDeg: 0, alpha: 0.7 });
  }

  /** 旧 addPdfLayer (GCP 互換、非推奨) */
  function addPdfLayer(id, canvasDataUrl, cornersJson) {
    if (!viewer) return;
    removeLayer(id);
    const corners = JSON.parse(cornersJson);
    const entity = viewer.entities.add({
      polygon: {
        hierarchy: new Cesium.PolygonHierarchy(
          corners.map(c => Cesium.Cartesian3.fromDegrees(c.lon, c.lat, c.h || 0))
        ),
        material: new Cesium.ImageMaterialProperty({ image: canvasDataUrl, transparent: true }),
        perPositionHeight: true,
        outline: false,
      },
    });
    layers[id] = { type: 'pdf', entity };
    return true;
  }

  // ──────────────────────────────────────────────
  // 3D モデル（GLB）レイヤー
  // ──────────────────────────────────────────────
  function addGlbLayer(id, url, lon, lat, height, heading, pitch, roll, scale) {
    if (!viewer) return;
    removeLayer(id);

    const entity = viewer.entities.add({
      position: Cesium.Cartesian3.fromDegrees(lon, lat, height || 0),
      model: {
        uri: url,
        scale: scale || 1.0,
        minimumPixelSize: 32,
        maximumScale: 20000,
        runAnimations: false,
      },
      orientation: Cesium.Transforms.headingPitchRollQuaternion(
        Cesium.Cartesian3.fromDegrees(lon, lat, height || 0),
        new Cesium.HeadingPitchRoll(
          Cesium.Math.toRadians(heading || 0),
          Cesium.Math.toRadians(pitch || 0),
          Cesium.Math.toRadians(roll || 0)
        )
      ),
    });

    layers[id] = { type: 'glb', entity };
    return true;
  }

  // ──────────────────────────────────────────────
  // レイヤー管理
  // ──────────────────────────────────────────────
  function removeLayer(id) {
    if (!viewer || !layers[id]) return;
    const layer = layers[id];
    if (layer.primitive) viewer.scene.primitives.remove(layer.primitive);
    if (layer.entity) viewer.entities.remove(layer.entity);
    if (layer.imageryLayer) viewer.imageryLayers.remove(layer.imageryLayer);
    delete layers[id];
  }

  function setLayerVisibility(id, visible) {
    if (!layers[id]) return;
    const layer = layers[id];
    if (layer.primitive) layer.primitive.show = visible;
    if (layer.entity) layer.entity.show = visible;
    if (layer.imageryLayer) layer.imageryLayer.show = visible;
  }

  function setLayerOpacity(id, opacity) {
    if (!layers[id]) return;
    const layer = layers[id];
    if (layer.entity && layer.entity.polygon) {
      layer.entity.polygon.material = new Cesium.ColorMaterialProperty(
        Cesium.Color.WHITE.withAlpha(opacity)
      );
    }
    if (layer.imageryLayer) layer.imageryLayer.alpha = opacity;
  }

  // ──────────────────────────────────────────────
  // GCP ピッキングモード
  // ──────────────────────────────────────────────
  function startGcpPicking(callback) {
    gcpPickingMode = true;
    gcpPickCallback = callback;
    if (viewer) {
      viewer.scene.canvas.style.cursor = 'crosshair';
    }
  }

  function stopGcpPicking() {
    gcpPickingMode = false;
    gcpPickCallback = null;
    if (viewer) {
      viewer.scene.canvas.style.cursor = '';
    }
  }

  // ──────────────────────────────────────────────
  // 注釈（ピン + テキスト）
  // ──────────────────────────────────────────────
  function addAnnotation(id, lon, lat, height, text, color) {
    if (!viewer) return;
    removeAnnotation(id);

    const clr = color
      ? Cesium.Color.fromCssColorString(color)
      : Cesium.Color.fromCssColorString('#FF6B35');

    const entity = viewer.entities.add({
      position: Cesium.Cartesian3.fromDegrees(lon, lat, height || 0),
      billboard: {
        image: _createPinCanvas(clr),
        verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
        heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
        pixelOffset: new Cesium.Cartesian2(0, 0),
      },
      label: {
        text: text || '',
        font: '14px Noto Sans JP, sans-serif',
        fillColor: Cesium.Color.WHITE,
        outlineColor: Cesium.Color.BLACK,
        outlineWidth: 2,
        style: Cesium.LabelStyle.FILL_AND_OUTLINE,
        pixelOffset: new Cesium.Cartesian2(12, -30),
        showBackground: true,
        backgroundColor: new Cesium.Color(0, 0, 0, 0.6),
        backgroundPadding: new Cesium.Cartesian2(6, 4),
        heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND,
        disableDepthTestDistance: Number.POSITIVE_INFINITY,
      },
    });

    annotations[id] = entity;
  }

  function removeAnnotation(id) {
    if (!viewer || !annotations[id]) return;
    viewer.entities.remove(annotations[id]);
    delete annotations[id];
  }

  function updateAnnotationText(id, text) {
    if (!annotations[id]) return;
    annotations[id].label.text = text;
  }

  function _createPinCanvas(color) {
    const canvas = document.createElement('canvas');
    canvas.width = 32;
    canvas.height = 44;
    const ctx = canvas.getContext('2d');
    const r = color.red * 255;
    const g = color.green * 255;
    const b = color.blue * 255;
    ctx.beginPath();
    ctx.arc(16, 14, 12, 0, Math.PI * 2);
    ctx.fillStyle = `rgb(${r},${g},${b})`;
    ctx.fill();
    ctx.strokeStyle = 'white';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(10, 22);
    ctx.lineTo(16, 44);
    ctx.lineTo(22, 22);
    ctx.fillStyle = `rgb(${r},${g},${b})`;
    ctx.fill();
    return canvas.toDataURL();
  }

  // ──────────────────────────────────────────────
  // 視点 JSON
  // ──────────────────────────────────────────────
  function getViewpointJson() {
    return getCameraState();
  }

  function applyViewpointJson(json) {
    const vp = JSON.parse(json);
    flyTo(vp.lon, vp.lat, vp.height, vp.heading, vp.pitch, 2.0);
  }

  // ──────────────────────────────────────────────
  // ユーティリティ
  // ──────────────────────────────────────────────
  function zoomIn() { if (viewer) viewer.camera.zoomIn(viewer.camera.positionCartographic.height * 0.3); }
  function zoomOut() { if (viewer) viewer.camera.zoomOut(viewer.camera.positionCartographic.height * 0.5); }

  function resetNorth() {
    if (!viewer) return;
    viewer.camera.flyTo({
      destination: viewer.camera.position,
      orientation: {
        heading: 0,
        pitch: viewer.camera.pitch,
        roll: 0,
      },
      duration: 0.5,
    });
  }

  function getAltitude() {
    if (!viewer) return 0;
    return viewer.camera.positionCartographic.height;
  }

  function isInitialized() {
    return viewer !== null;
  }

  // ──────────────────────────────────────────────
  // カメラ操作の ON/OFF (PDF 編集モード用)
  // ──────────────────────────────────────────────
  function disableCameraControls() {
    if (!viewer) return;
    const ctrl = viewer.scene.screenSpaceCameraController;
    ctrl.enableRotate    = false;
    ctrl.enableTranslate = false;
    ctrl.enableZoom      = false;
    ctrl.enableTilt      = false;
    ctrl.enableLook      = false;
    // CSS でも念押し: Cesium canvas のポインターイベントを無効化
    if (viewer.scene.canvas) {
      viewer.scene.canvas.style.pointerEvents = 'none';
    }
  }

  function enableCameraControls() {
    if (!viewer) return;
    const ctrl = viewer.scene.screenSpaceCameraController;
    ctrl.enableRotate    = true;
    ctrl.enableTranslate = true;
    ctrl.enableZoom      = true;
    ctrl.enableTilt      = true;
    ctrl.enableLook      = true;
    if (viewer.scene.canvas) {
      viewer.scene.canvas.style.pointerEvents = '';
    }
  }

  /** スクリーン座標 → 地理座標 (Cesium ray picking) */
  function screenToGeo(screenX, screenY) {
    if (!viewer) return null;
    const pos2d = new Cesium.Cartesian2(screenX, screenY);

    // まず地形 (Globe) への ray intersection
    const ray = viewer.camera.getPickRay(pos2d);
    let cartesian = null;
    if (ray) {
      cartesian = viewer.scene.globe.pick(ray, viewer.scene);
    }
    // 地形に当たらない場合は楕円体
    if (!cartesian) {
      cartesian = viewer.camera.pickEllipsoid(pos2d);
    }
    if (!cartesian) return null;

    const carto = Cesium.Cartographic.fromCartesian(cartesian);
    return JSON.stringify({
      lon: Cesium.Math.toDegrees(carto.longitude),
      lat: Cesium.Math.toDegrees(carto.latitude),
      h:   carto.height,
    });
  }

  // ──────────────────────────────────────────────
  // ファイルダウンロード
  // ──────────────────────────────────────────────
  function downloadBlob(bytes, filename, mime) {
    const blob = new Blob([bytes], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  // ──────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────
  return {
    init,
    flyTo,
    getCameraState,
    moveCamera,
    rotateCamera,
    setBaseMap,
    addPointCloudLayer,
    addPointCloudDirect,
    addPdfLayer,
    placePdfLayer,
    updatePdfTransform,
    getPdfScreenHandles,
    initPdfPlacement,
    addGlbLayer,
    removeLayer,
    setLayerVisibility,
    setLayerOpacity,
    startGcpPicking,
    stopGcpPicking,
    addAnnotation,
    removeAnnotation,
    updateAnnotationText,
    getViewpointJson,
    applyViewpointJson,
    zoomIn,
    zoomOut,
    resetNorth,
    getAltitude,
    isInitialized,
    downloadBlob,
    enableWalkingMode,
    disableWalkingMode,
    isWalkingMode,
    disableCameraControls,
    enableCameraControls,
    screenToGeo,
  };
})();

// ─────────────────────────────────────────────
// HtmlElementView コンテナ生成 + Cesium 初期化
// Flutter の platformViewRegistry.registerViewFactory から呼ばれる
// ─────────────────────────────────────────────
window._createCesiumDiv = function () {
  const div = document.createElement('div');
  div.id = 'cesiumContainer';
  div.style.cssText = 'width:100%;height:100%;background:#1a1a2e;';

  // 少し遅延させて DOM に追加されてから Cesium を初期化
  requestAnimationFrame(function waitForAttach() {
    if (div.offsetWidth === 0) {
      requestAnimationFrame(waitForAttach);
      return;
    }
    // Cesium を div に対して初期化
    CesiumBridge.init({ container: div });
  });

  return div;
};

// ─────────────────────────────────────────────
// Flutter レイヤーパネル経由のロード
// Flutter Dart から _loadPointCloudFromFlutter(url, layerId, jgdZone, jgdSwapped, callback) で呼ぶ
// ─────────────────────────────────────────────
window._loadPointCloudFromFlutter = function(url, layerId, jgdZone, jgdSwapped, callback) {
  const crsHint = jgdZone > 0 ? { zone: jgdZone, swapped: jgdSwapped } : null;
  fetch(url)
    .then(r => r.arrayBuffer())
    .then(buf => {
      window._runLasWorker(buf, url.split('/').pop(), (json) => {
        const r = JSON.parse(json);
        if (r.type === 'error') {
          callback(JSON.stringify({ error: r.message }));
          return;
        }
        CesiumBridge.addPointCloudDirect(layerId, r.points, { pointSize: 3, center: r.center });
        callback(JSON.stringify({
          pts: r.loadedPoints,
          center: r.center,
          zone: r.jgdZone,
          info: r.coordinateInfo,
        }));
      }, crsHint);
    })
    .catch(e => callback(JSON.stringify({ error: e.message })));
};

// ─────────────────────────────────────────────
// Web Worker: LAS パーサ起動 (Flutter から呼ばれる)
// ─────────────────────────────────────────────
// 旧: 直接 Cesium に表示（JS コンソール用）
window._loadAndShowPointCloud = function(layerId, url, crsHint, onDone) {
  fetch(url)
    .then(r => r.arrayBuffer())
    .then(buf => {
      window._runLasWorker(buf, url.split('/').pop(), (json) => {
        const r = JSON.parse(json);
        if (r.type === 'error') { if(onDone) onDone(null, r.message); return; }
        CesiumBridge.addPointCloudDirect(layerId, r.points, { pointSize: 3 });
        CesiumBridge.flyTo(r.center.lon, r.center.lat, 400, 20, -45, 2.0);
        if (onDone) onDone(r, null);
      }, crsHint);
    })
    .catch(e => { if(onDone) onDone(null, e.message); });
};

window._runLasWorker = function (buffer, filename, callback, crsHint) {
  const worker = new Worker('pointcloud_loader.js');
  const id = Date.now().toString();

  worker.onmessage = function (e) {
    const data = e.data;
    if (data.id !== id) return;
    if (data.type === 'progress') {
      // 進捗ログ（デバッグ用）
      console.log('[LAS]', data.message);
      return;
    }
    if (data.type === 'done' || data.type === 'error') {
      worker.terminate();
      callback(JSON.stringify(data));
    }
  };

  worker.postMessage({ type: 'parse', id, buffer, filename, crsHint }, [buffer]);
};

// ─────────────────────────────────────────────
// PDF アスペクト比取得
// ─────────────────────────────────────────────
window._getPdfAspectRatio = async function (dataUrl) {
  if (typeof pdfjsLib === 'undefined') return 1.0;
  const loadingTask = pdfjsLib.getDocument({ url: dataUrl });
  const pdf = await loadingTask.promise;
  const page = await pdf.getPage(1);
  const vp = page.getViewport({ scale: 1.0 });
  return vp.width / vp.height;
};

// ─────────────────────────────────────────────
// PDF → Canvas 変換 (pdf.js 使用)
// ─────────────────────────────────────────────
window._renderPdfToCanvas = async function (dataUrl) {
  if (typeof pdfjsLib === 'undefined') return dataUrl;

  const loadingTask = pdfjsLib.getDocument({ url: dataUrl });
  const pdf = await loadingTask.promise;
  const page = await pdf.getPage(1);

  const scale = 2.0; // 高解像度
  const viewport = page.getViewport({ scale });

  const canvas = document.createElement('canvas');
  canvas.width = viewport.width;
  canvas.height = viewport.height;
  const ctx = canvas.getContext('2d');

  await page.render({ canvasContext: ctx, viewport }).promise;
  return canvas.toDataURL('image/png');
};
;
