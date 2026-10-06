import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

/// A tap-to-pick video area with dashed border.
class UploadZone extends StatelessWidget {
  final String? selectedPath;
  final ValueChanged<String> onFilePicked;

  const UploadZone({
    super.key,
    this.selectedPath,
    required this.onFilePicked,
  });

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      onFilePicked(result.files.single.path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = selectedPath != null;

    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFile
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.5),
            width: hasFile ? 2 : 1,
          ),
          color: theme.colorScheme.surface.withOpacity(0.3),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasFile ? Icons.videocam : Icons.upload_file,
                size: 40,
                color: hasFile
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(height: 12),
              Text(
                hasFile ? _fileName(selectedPath!) : 'Tap to select a video',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: hasFile
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
              if (hasFile) ...[
                const SizedBox(height: 4),
                Text(
                  'Tap to change',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }
}
