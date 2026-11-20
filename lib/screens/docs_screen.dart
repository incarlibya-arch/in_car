import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets.dart';

/// رفع وثائق السواق للتوثيق
class DriverDocsScreen extends StatefulWidget {
  final Profile me;
  const DriverDocsScreen({super.key, required this.me});
  @override
  State<DriverDocsScreen> createState() => _DriverDocsScreenState();
}

class _DriverDocsScreenState extends State<DriverDocsScreen> {
  late Future<List<DriverDoc>> _docs = Api.myDocuments();
  String? _uploading;

  Future<void> _pick(String type) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('صوّر بالكاميرا'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('من الصور'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 80);
    if (file == null) return;
    setState(() => _uploading = type);
    try {
      final bytes = await file.readAsBytes();
      // PNG يبدأ بالبايتات 89 50 4E 47، وأي شي ثاني نعامله كـ JPG
      final ext = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50 ? 'png' : 'jpg';
      await Api.uploadDocument(type, bytes, ext);
      if (mounted) {
        showMsg(context, 'تم رفع ${docTypes[type]}');
        setState(() => _docs = Api.myDocuments());
      }
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.me.driverStatus;
    return Scaffold(
      appBar: AppBar(title: const Text('توثيق الحساب')),
      body: FutureBuilder<List<DriverDoc>>(
        future: _docs,
        builder: (context, snap) {
          final docs = {for (final d in snap.data ?? <DriverDoc>[]) d.docType: d};
          final allUploaded = docTypes.keys.every(docs.containsKey);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: status == 'approved'
                    ? const Color(0xFFDDF3E8)
                    : status == 'rejected'
                        ? const Color(0xFFFBE0DC)
                        : AppColors.accentSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                status == 'approved'
                    ? 'حسابك موثّق ✓'
                    : status == 'rejected'
                        ? 'الوثائق ما انقبلتش${widget.me.driverNote != null ? ': ${widget.me.driverNote}' : ''}. ارفعها من جديد.'
                        : allUploaded
                            ? 'وثائقك وصلت، والإدارة تراجعها. بيوصلك إشعار أول ما يتوثق حسابك.'
                            : 'ارفع الوثائق الأربعة باش تقدر تبدأ تستقبل الطلبات.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            for (final e in docTypes.entries)
              Card(
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  leading: Icon(
                    docs.containsKey(e.key) ? Icons.check_circle : Icons.upload_file,
                    color: docs.containsKey(e.key) ? AppColors.ok : AppColors.mute,
                  ),
                  title: Text(e.value),
                  subtitle: Text(docs.containsKey(e.key)
                      ? const {'approved': 'مقبولة', 'rejected': 'مرفوضة، ارفعها من جديد'}[docs[e.key]!.status] ?? 'تم الرفع'
                      : 'ما ترفعتش'),
                  trailing: _uploading == e.key
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: _uploading == null ? () => _pick(e.key) : null,
                          child: Text(docs.containsKey(e.key) ? 'تغيير' : 'رفع'),
                        ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'الصور تبقى خاصة، ما يشوفها إلا فريق in car للمراجعة. لو بدّلت بيانات السيارة أو اللوحة، حسابك يرجع للمراجعة.',
              style: TextStyle(color: AppColors.mute, fontSize: 13),
            ),
          ]);
        },
      ),
    );
  }
}
