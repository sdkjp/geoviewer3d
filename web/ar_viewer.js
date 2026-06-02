/**
 * ar_viewer.js  ─  点群 3D / AR ビューア
 *
 * ・PC / Mac    → model-viewer で 3D オブジェクト表示（ドラッグ回転・ピンチズーム）
 * ・iPhone/iPad → 上記 + 「AR で見る」→ iOS AR Quick Look（GLB、iOS 16.2+）
 * ・Android     → 上記 + 「AR で見る」→ Google Scene Viewer / WebXR
 *
 * 点群を GLTF POINTS (mode=0) の GLB に変換して model-viewer に渡す。
 */
(function () {
  'use strict';

  // ─── 格納済み点群 (layerId → { points, center }) ───
  const _clouds = {};

  window._arStoreCloud = function (id, points, center) {
    _clouds[id] = { points, center };
  };

  // ────────────────────────────────────────
  // GLB エクスポート
  //   GLTF2 POINTS プリミティブ
  //   POSITION : Float32 VEC3  (点群中心からの ENU メートル座標)
  //   COLOR_0  : UNSIGNED_BYTE VEC4 normalized  (RGBA、A=255固定)
  // ────────────────────────────────────────
  function _exportGLB(layerId) {
    const cloud = _clouds[layerId];
    if (!cloud || !cloud.points || cloud.points.length === 0) return null;

    const all = cloud.points;
    const cen = cloud.center;
    // iOS AR Quick Look は POINTS(mode=0) 非対応 → 十字クワッドに変換
    // 1点 = 直交する2枚のクワッド(XY面 + ZY面) = 8頂点 + 4三角形(12インデックス)
    // 表示点数は 40K に間引き (ファイルサイズ ~7MB)
    const MAX  = 40000;
    const skip = Math.max(1, Math.ceil(all.length / MAX));
    const pts  = [];
    for (let i = 0; i < all.length; i += skip) pts.push(all[i]);
    const n = pts.length;

    const cosLat  = Math.cos(cen.lat * Math.PI / 180);
    const mPerLon = 111320 * cosLat;
    const mPerLat = 110540;
    const HALF    = 0.15;  // クワッド半辺 0.15m → 30cm × 30cm

    // 1点あたり: 8頂点・12インデックス
    const nVerts = n * 8;
    const nIdx   = n * 12;

    const pos = new Float32Array(nVerts * 3);  // POSITION VEC3
    const col = new Uint8Array(nVerts * 4);    // COLOR_0  VEC4 (RGBA)
    const idx = new Uint32Array(nIdx);         // INDEX    SCALAR UINT

    let minX=1e9, minY=1e9, minZ=1e9, maxX=-1e9, maxY=-1e9, maxZ=-1e9;

    for (let i = 0; i < n; i++) {
      const p  = pts[i];
      const cx =  (p.x - cen.lon) * mPerLon;
      const cy =  (p.z || 0);
      const cz = -(p.y - cen.lat) * mPerLat;

      const r = p.r !== undefined ? p.r : 180;
      const g = p.g !== undefined ? p.g : 180;
      const b = p.b !== undefined ? p.b : 180;

      const vi = i * 8;   // vertex base index
      const pi = vi * 3;  // pos array offset
      const ci = vi * 4;  // col array offset
      const ii = i * 12;  // idx array offset

      // Quad A: XY 面 (±Z を向く垂直クワッド)
      pos[pi+ 0]=cx-HALF; pos[pi+ 1]=cy-HALF; pos[pi+ 2]=cz;
      pos[pi+ 3]=cx+HALF; pos[pi+ 4]=cy-HALF; pos[pi+ 5]=cz;
      pos[pi+ 6]=cx+HALF; pos[pi+ 7]=cy+HALF; pos[pi+ 8]=cz;
      pos[pi+ 9]=cx-HALF; pos[pi+10]=cy+HALF; pos[pi+11]=cz;
      // Quad B: ZY 面 (±X を向く垂直クワッド)
      pos[pi+12]=cx; pos[pi+13]=cy-HALF; pos[pi+14]=cz-HALF;
      pos[pi+15]=cx; pos[pi+16]=cy-HALF; pos[pi+17]=cz+HALF;
      pos[pi+18]=cx; pos[pi+19]=cy+HALF; pos[pi+20]=cz+HALF;
      pos[pi+21]=cx; pos[pi+22]=cy+HALF; pos[pi+23]=cz-HALF;

      for (let v = 0; v < 8; v++) {
        col[ci+v*4+0]=r; col[ci+v*4+1]=g; col[ci+v*4+2]=b; col[ci+v*4+3]=255;
      }

      // Quad A の三角形 (0-1-2, 0-2-3)
      idx[ii+ 0]=vi+0; idx[ii+ 1]=vi+1; idx[ii+ 2]=vi+2;
      idx[ii+ 3]=vi+0; idx[ii+ 4]=vi+2; idx[ii+ 5]=vi+3;
      // Quad B の三角形 (4-5-6, 4-6-7)
      idx[ii+ 6]=vi+4; idx[ii+ 7]=vi+5; idx[ii+ 8]=vi+6;
      idx[ii+ 9]=vi+4; idx[ii+10]=vi+6; idx[ii+11]=vi+7;

      minX=Math.min(minX,cx-HALF); maxX=Math.max(maxX,cx+HALF);
      minY=Math.min(minY,cy-HALF); maxY=Math.max(maxY,cy+HALF);
      minZ=Math.min(minZ,cz-HALF); maxZ=Math.max(maxZ,cz+HALF);
    }

    // バッファレイアウト: pos → col → idx (4byte アライン)
    const posByteLen = nVerts * 12;
    const colByteLen = nVerts * 4;
    const idxByteLen = nIdx   * 4;
    const binByteLen = posByteLen + colByteLen + idxByteLen;

    const jsonStr = JSON.stringify({
      asset: { version: '2.0', generator: 'GeoViewer3D' },
      scene: 0,
      scenes: [{ nodes: [0] }],
      nodes: [{ mesh: 0 }],
      meshes: [{
        primitives: [{
          attributes: { POSITION: 0, COLOR_0: 1 },
          indices: 2,
          mode: 4,   // TRIANGLES (iOS AR Quick Look 対応)
          material: 0,
        }],
      }],
      materials: [{
        pbrMetallicRoughness: { metallicFactor: 0, roughnessFactor: 1 },
        doubleSided: true,  // 裏面も描画
      }],
      accessors: [
        {
          bufferView: 0, componentType: 5126 /* FLOAT */,
          count: nVerts, type: 'VEC3',
          min: [minX, minY, minZ], max: [maxX, maxY, maxZ],
        },
        {
          bufferView: 1, componentType: 5121 /* UNSIGNED_BYTE */,
          count: nVerts, type: 'VEC4', normalized: true,
        },
        {
          bufferView: 2, componentType: 5125 /* UNSIGNED_INT */,
          count: nIdx, type: 'SCALAR',
        },
      ],
      bufferViews: [
        { buffer: 0, byteOffset: 0,                        byteLength: posByteLen },
        { buffer: 0, byteOffset: posByteLen,               byteLength: colByteLen },
        { buffer: 0, byteOffset: posByteLen + colByteLen,  byteLength: idxByteLen },
      ],
      buffers: [{ byteLength: binByteLen }],
    });

    // JSON チャンクは 4byte アライン (space=0x20 でパディング)
    const jsonBytes    = new TextEncoder().encode(jsonStr);
    const jsonPadLen   = (4 - (jsonBytes.length % 4)) % 4;
    const jsonChunkLen = jsonBytes.length + jsonPadLen;

    // GLB 合計サイズ
    const totalLen = 12 + 8 + jsonChunkLen + 8 + binByteLen;
    const buf = new ArrayBuffer(totalLen);
    const dv  = new DataView(buf);
    const u8  = new Uint8Array(buf);
    let off   = 0;

    // --- GLB ヘッダー ---
    dv.setUint32(off, 0x46546C67, true); off += 4;  // magic "glTF"
    dv.setUint32(off, 2,          true); off += 4;  // version 2
    dv.setUint32(off, totalLen,   true); off += 4;

    // --- JSON チャンク ---
    dv.setUint32(off, jsonChunkLen, true); off += 4;
    dv.setUint32(off, 0x4E4F534A,  true); off += 4;  // "JSON"
    u8.set(jsonBytes, off);               off += jsonBytes.length;
    u8.fill(0x20, off, off + jsonPadLen); off += jsonPadLen;

    // --- BIN チャンク ---
    dv.setUint32(off, binByteLen, true); off += 4;
    dv.setUint32(off, 0x004E4942, true); off += 4;  // "BIN\0"
    u8.set(new Uint8Array(pos.buffer), off); off += posByteLen;
    u8.set(col,                        off); off += colByteLen;
    u8.set(new Uint8Array(idx.buffer), off);

    return buf;
  }

  // ────────────────────────────────────────
  // model-viewer オーバーレイを生成・表示
  // ────────────────────────────────────────
  function _showViewer(blobUrl, layerName) {
    // 既存のビューアがあれば閉じる
    const old = document.getElementById('__mv_overlay__');
    if (old) old.remove();

    const overlay = document.createElement('div');
    overlay.id = '__mv_overlay__';
    overlay.style.cssText = [
      'position:fixed;inset:0;z-index:9999',
      'background:#0a1628',
      'display:flex;flex-direction:column',
    ].join(';');

    // ヘッダー
    const header = document.createElement('div');
    header.style.cssText = [
      'background:#1B3A6B',
      'padding:12px 16px',
      'display:flex;align-items:center;gap:12px',
      'box-shadow:0 2px 8px rgba(0,0,0,0.4)',
    ].join(';');
    header.innerHTML = `
      <span style="font-size:18px">📐</span>
      <span style="color:#fff;font-size:14px;font-weight:700;flex:1">
        ${layerName || '点群'} ─ 3D / AR ビューア
      </span>
      <button id="__mv_close__" style="
        background:rgba(255,255,255,0.15);color:#fff;border:none;
        padding:7px 16px;border-radius:20px;font-size:13px;cursor:pointer;">
        ✕ 閉じる
      </button>
    `;

    // model-viewer 本体
    const mv = document.createElement('model-viewer');
    mv.src = blobUrl;
    mv.setAttribute('ar', '');
    mv.setAttribute('ar-modes', 'webxr scene-viewer quick-look');
    mv.setAttribute('ar-scale', 'auto');
    mv.setAttribute('camera-controls', '');
    mv.setAttribute('auto-rotate', '');
    mv.setAttribute('auto-rotate-delay', '500');
    mv.setAttribute('shadow-intensity', '0');
    mv.setAttribute('environment-image', 'neutral');
    mv.setAttribute('exposure', '0.8');
    mv.style.cssText = 'flex:1;width:100%;background:transparent;';

    // AR ボタン（スマホでのみ表示される slot="ar-button"）
    const arBtn = document.createElement('button');
    arBtn.setAttribute('slot', 'ar-button');
    arBtn.style.cssText = [
      'position:absolute;bottom:36px;left:50%;transform:translateX(-50%)',
      'background:#1B3A6B;color:#fff;border:2px solid rgba(255,255,255,0.3)',
      'padding:13px 32px;border-radius:30px;font-size:15px;cursor:pointer',
      'box-shadow:0 4px 20px rgba(0,0,0,0.5)',
      'white-space:nowrap;letter-spacing:0.3px',
    ].join(';');
    arBtn.innerHTML = '📱&nbsp;&nbsp;AR で見る（カメラ起動）';
    mv.appendChild(arBtn);

    // フッターヒント
    const hint = document.createElement('div');
    hint.style.cssText = [
      'background:#1B3A6B;color:rgba(255,255,255,0.6)',
      'text-align:center;padding:8px;font-size:11px',
    ].join(';');
    hint.textContent = 'ドラッグ: 回転 ／ ホイール / ピンチ: ズーム'
      + '（スマホでは「AR で見る」でカメラ越し表示）';

    overlay.appendChild(header);
    overlay.appendChild(mv);
    overlay.appendChild(hint);
    document.body.appendChild(overlay);

    document.getElementById('__mv_close__').onclick = () => {
      overlay.remove();
      URL.revokeObjectURL(blobUrl);
    };
  }

  // ────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────

  /**
   * 点群 AR/3D ビューアを起動する
   * Flutter の CesiumBridge.startPointCloudAR(layerId) から呼ばれる
   * @param {string} layerId
   * @param {string} [layerName]
   * @returns {Promise<string>} JSON { ok: true, pts: n } | { error: string }
   */
  window.startPointCloudAR = async function (layerId, layerName) {
    if (!_clouds[layerId]) {
      return JSON.stringify({ error: '点群データがまだ読み込まれていません' });
    }

    // model-viewer カスタム要素が登録されるまで待機 (最大3秒)
    if (!customElements.get('model-viewer')) {
      try {
        await Promise.race([
          customElements.whenDefined('model-viewer'),
          new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 3000)),
        ]);
      } catch (_) {
        return JSON.stringify({ error: 'model-viewer のロードに失敗しました。ページを再読み込みしてください。' });
      }
    }

    const glbBuf = _exportGLB(layerId);
    if (!glbBuf) return JSON.stringify({ error: 'GLB の生成に失敗しました' });

    const blob    = new Blob([glbBuf], { type: 'model/gltf-binary' });
    const blobUrl = URL.createObjectURL(blob);

    const n = _clouds[layerId].points.length;
    const displayed = Math.min(n, 100000);
    _showViewer(blobUrl, layerName || layerId);

    return JSON.stringify({ ok: true, pts: displayed, total: n });
  };

  /** ビューアを閉じる */
  window.stopPointCloudAR = function () {
    const el = document.getElementById('__mv_overlay__');
    if (el) el.remove();
  };

  /** AR / model-viewer サポート確認 */
  window.checkARSupport = async function () {
    const mvReady = customElements.get('model-viewer') !== undefined;
    return JSON.stringify({ supported: true, modelViewer: mvReady });
  };

})();
