import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/viewpoint.dart';
import '../services/file_service.dart';

const _kNavy    = Color(0xFF1B3A6B);
const _kNavyMid = Color(0xFF2A5298);
const _kBorder  = Color(0xFFDDE2EE);
const _kTextSub = Color(0xFF6B7A99);

class ViewpointExportDialog extends StatefulWidget {
  final String viewpointJson;
  const ViewpointExportDialog({super.key, required this.viewpointJson});

  @override
  State<ViewpointExportDialog> createState() => _ViewpointExportDialogState();
}

class _ViewpointExportDialogState extends State<ViewpointExportDialog> {
  bool _copied = false;
  final _labelCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.share_location, color: _kNavy),
                const SizedBox(width: 8),
                const Text('視点を共有',
                    style: TextStyle(
                        color: _kNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: _kTextSub, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: SelectableText(
                widget.viewpointJson,
                style: const TextStyle(
                    color: _kNavy,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                        _copied ? Icons.check : Icons.copy, size: 16),
                    label: Text(_copied ? 'コピー済み' : 'クリップボードにコピー'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          _copied ? Colors.green : _kNavy,
                      side: BorderSide(
                          color: _copied ? Colors.green : _kNavyMid),
                    ),
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: widget.viewpointJson));
                      setState(() => _copied = true);
                      await Future.delayed(const Duration(seconds: 2));
                      if (mounted) setState(() => _copied = false);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('JSON 保存'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTextSub,
                    side: const BorderSide(color: _kBorder),
                  ),
                  onPressed: () {
                    FileService.downloadJson(
                        widget.viewpointJson, 'viewpoint.json');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ViewpointImportDialog extends StatefulWidget {
  const ViewpointImportDialog({super.key});

  @override
  State<ViewpointImportDialog> createState() => _ViewpointImportDialogState();
}

class _ViewpointImportDialogState extends State<ViewpointImportDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    try {
      final text = _ctrl.text.trim();
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      if (!decoded.containsKey('lon') || !decoded.containsKey('lat')) {
        setState(() => _error = 'lon / lat フィールドが見つかりません');
        return;
      }
      Navigator.pop(context, text);
    } catch (e) {
      setState(() => _error = 'JSONの形式が正しくありません');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.my_location, color: _kNavy),
                const SizedBox(width: 8),
                const Text('視点を読み込む',
                    style: TextStyle(
                        color: _kNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: _kTextSub, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              style: const TextStyle(
                  color: _kNavy,
                  fontSize: 11,
                  fontFamily: 'monospace'),
              maxLines: 8,
              decoration: InputDecoration(
                hintText: '{"lon": 135.5, "lat": 34.7, ...}',
                hintStyle: const TextStyle(color: _kTextSub, fontSize: 11),
                filled: true,
                fillColor: const Color(0xFFF0F4F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _kNavy, width: 2),
                ),
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('ファイルから'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kTextSub,
                    side: const BorderSide(color: _kBorder),
                  ),
                  onPressed: () async {
                    final f = await FileService.pickJson();
                    if (f != null) {
                      _ctrl.text = String.fromCharCodes(f.bytes);
                      setState(() => _error = null);
                    }
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル',
                      style: TextStyle(color: _kTextSub)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kNavy,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _ctrl.text.trim().isEmpty ? null : _apply,
                  child: const Text('移動'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
