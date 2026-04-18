import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();

  String?  _filePath;
  String?  _fileName;
  int?     _fileSize;
  bool     _uploading   = false;
  double   _uploadProgress = 0;
  String?  _uploadError;
  String?  _uploadedVideoId;
  String   _selectedPrivacy = 'public';

  static const _privacyOptions = ['public', 'unlisted', 'private'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type:           FileType.video,
      allowMultiple:  false,
      withReadStream: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _filePath  = result.files.single.path;
        _fileName  = result.files.single.name;
        _fileSize  = result.files.single.size;
        _uploadedVideoId = null;
        _uploadError     = null;
      });
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    if (_filePath == null) {
      setState(() => _uploadError = 'Please select a video file first.');
      return;
    }

    setState(() { _uploading = true; _uploadProgress = 0; _uploadError = null; });

    try {
      final api = ref.read(apiClientProvider);

      // 1. Get presigned upload URL
      final presign = await api.presignUpload(
        title:       _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      final videoId   = presign['videoId']   as String;
      final uploadUrl = presign['uploadUrl'] as String;

      // 2. Upload file directly to MinIO via the presigned PUT URL
      final file = File(_filePath!);
      final dio  = Dio();
      await dio.put(
        uploadUrl,
        data:    file.openRead(),
        options: Options(
          headers: {
            'Content-Type':   'video/mp4',
            'Content-Length': file.lengthSync(),
          },
        ),
        onSendProgress: (sent, total) {
          setState(() => _uploadProgress = total > 0 ? sent / total : 0);
        },
      );

      // 3. Notify API to start transcoding
      await api.confirmUpload(videoId);

      setState(() {
        _uploadedVideoId  = videoId;
        _uploading        = false;
        _uploadProgress   = 1.0;
      });

    } catch (e) {
      setState(() {
        _uploading   = false;
        _uploadError = e.toString();
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024)          return '${bytes}B';
    if (bytes < 1024 * 1024)   return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor:  AppColors.darkBg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Upload Video'),
        actions: [
          if (!_uploading && _uploadedVideoId == null && _filePath != null)
            TextButton(
              onPressed: _upload,
              child: ShaderMask(
                shaderCallback: (b) => AppColors.brandGradient.createShader(b),
                child: const Text('Upload',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
        ],
      ),
      body: _uploadedVideoId != null
          ? _buildSuccess()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── File picker ────────────────────────────────────
                    GestureDetector(
                      onTap: _uploading ? null : _pickFile,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height:    _filePath == null ? 180 : 100,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _filePath != null
                                ? AppColors.accentOrange
                                : AppColors.darkBorder,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          color: _filePath != null
                              ? AppColors.accentOrange.withOpacity(0.05)
                              : AppColors.darkElevated,
                        ),
                        child: _filePath == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ShaderMask(
                                    shaderCallback: (b) => AppColors.brandGradient.createShader(b),
                                    child: const Icon(Icons.cloud_upload_rounded,
                                        color: Colors.white, size: 48),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text('Tap to select a video',
                                    style: TextStyle(color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  const Text('MP4, MKV, MOV, AVI · Max 500MB',
                                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                                ],
                              )
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42, height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.accentOrange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.video_file_rounded,
                                          color: AppColors.accentOrange, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(_fileName ?? '',
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600, fontSize: 13)),
                                          const SizedBox(height: 3),
                                          Text(_formatSize(_fileSize ?? 0),
                                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
                                      onPressed: () => setState(() {
                                        _filePath = _fileName = null; _fileSize = null; }),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ).animate().fadeIn(),

                    if (_uploading) ...[
                      const SizedBox(height: 16),
                      _UploadProgress(progress: _uploadProgress),
                    ],

                    if (_uploadError != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.error.withOpacity(0.3)),
                        ),
                        child: Text(_uploadError!,
                          style: const TextStyle(color: AppColors.error, fontSize: 13)),
                      ),

                    const SizedBox(height: 24),

                    // ── Title ─────────────────────────────────────────
                    TextFormField(
                      controller: _titleCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Title *',
                        hintText:  'Give your video a descriptive title',
                        counterText: '',
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // ── Description ───────────────────────────────────
                    TextFormField(
                      controller: _descCtrl,
                      style: const TextStyle(color: AppColors.textPrimary),
                      maxLines:   5,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText:  'Tell viewers about your video',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Privacy ───────────────────────────────────────
                    const Text('Visibility',
                      style: TextStyle(color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: _privacyOptions.map((p) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label:        Text(p[0].toUpperCase() + p.substring(1)),
                          selected:     _selectedPrivacy == p,
                          onSelected:   (_) => setState(() => _selectedPrivacy = p),
                          selectedColor: AppColors.accentOrange.withOpacity(0.15),
                          backgroundColor: AppColors.darkElevated,
                          side: BorderSide(
                            color: _selectedPrivacy == p ? AppColors.accentOrange : AppColors.darkBorder),
                          labelStyle: TextStyle(
                            color: _selectedPrivacy == p ? AppColors.accentOrange : AppColors.textSecondary,
                            fontWeight: _selectedPrivacy == p ? FontWeight.w700 : FontWeight.normal,
                            fontSize: 12,
                          ),
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 32),

                    if (!_uploading)
                      SizedBox(
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient:     _filePath != null ? AppColors.brandGradient : null,
                            color:        _filePath == null ? AppColors.darkElevated : null,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor:     Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _filePath != null ? _upload : null,
                            icon: const Icon(Icons.upload_rounded, color: Colors.white),
                            label: const Text('Upload & Transcode',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                    // Transcoding info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:        AppColors.darkElevated,
                        borderRadius: BorderRadius.circular(12),
                        border:       Border.all(color: AppColors.darkBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Row(children: [
                            Icon(Icons.info_outline, color: AppColors.accentOrange, size: 16),
                            SizedBox(width: 8),
                            Text('What happens after upload?',
                              style: TextStyle(color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                          SizedBox(height: 10),
                          _InfoRow(icon: Icons.lock_rounded, text: 'AES-128 encryption applied to all segments'),
                          _InfoRow(icon: Icons.hd_rounded,   text: 'Transcoded to 1080p, 720p, 480p HLS'),
                          _InfoRow(icon: Icons.speed_rounded, text: 'Adaptive bitrate streaming enabled'),
                          _InfoRow(icon: Icons.storage_rounded, text: 'Stored securely in private MinIO buckets'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSuccess() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient:     AppColors.brandGradient,
              shape:        BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
          const SizedBox(height: 20),
          Text('Upload successful!', style: Theme.of(context).textTheme.headlineSmall)
              .animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 8),
          Text('Your video is being transcoded to AES-128 encrypted HLS.\nIt will be available in a few minutes.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium)
              .animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 8),
          Text('Video ID: $_uploadedVideoId',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11))
              .animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _uploadedVideoId = null; _filePath = null;
              _titleCtrl.clear(); _descCtrl.clear(); _uploadProgress = 0;
            }),
            icon: const Icon(Icons.cloud_upload_rounded),
            label: const Text('Upload another'),
          ).animate().fadeIn(delay: 500.ms),
        ],
      ),
    ),
  );
}

class _UploadProgress extends StatelessWidget {
  final double progress;
  const _UploadProgress({required this.progress});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Uploading…', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text('${(progress * 100).round()}%',
            style: const TextStyle(color: AppColors.accentOrange,
                fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: AppColors.darkDivider,
          valueColor: const AlwaysStoppedAnimation(AppColors.accentOrange),
          minHeight: 6,
        ),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 14, color: AppColors.accentOrange),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
      ],
    ),
  );
}
