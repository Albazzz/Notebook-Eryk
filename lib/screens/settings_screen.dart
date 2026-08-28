import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _SettingsSection { general, pencil, ai, privacy, about }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsSection section = _SettingsSection.general;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
      child: Column(
        children: [
          const PageHeader(
            title: 'Cài đặt',
            subtitle: 'Tùy chỉnh trải nghiệm viết, học và quyền riêng tư.',
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 210,
                  child: ListView(
                    children: _SettingsSection.values
                        .map(
                          (value) => _SectionTile(
                            section: value,
                            selected: section == value,
                            onTap: () => setState(() => section = value),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: _content(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() => switch (section) {
    _SettingsSection.general => _GeneralSettings(state: widget.state),
    _SettingsSection.pencil => _PencilSettings(state: widget.state),
    _SettingsSection.ai => _AiSettings(state: widget.state),
    _SettingsSection.privacy => const _PrivacySettings(),
    _SettingsSection.about => const _AboutSettings(),
  };
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final _SettingsSection section;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (section) {
      _SettingsSection.general => (Icons.tune_rounded, 'Chung'),
      _SettingsSection.pencil => (Icons.edit_outlined, 'Apple Pencil'),
      _SettingsSection.ai => (Icons.auto_awesome_outlined, 'AI'),
      _SettingsSection.privacy => (Icons.shield_outlined, 'Dữ liệu & riêng tư'),
      _SettingsSection.about => (Icons.info_outline_rounded, 'Giới thiệu'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        selected: selected,
        selectedTileColor: const Color(0xffdce1ff),
        selectedColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        leading: Icon(icon),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: onTap,
      ),
    );
  }
}

class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Chung', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 18),
      SectionCard(
        child: Column(
          children: [
            const _SettingRow(
              icon: Icons.language_rounded,
              title: 'Ngôn ngữ giao diện',
              subtitle: 'Tiếng Việt',
              trailing: Icon(Icons.chevron_right),
            ),
            const Divider(),
            _SettingRow(
              icon: Icons.contrast_rounded,
              title: 'Giao diện',
              subtitle: 'Chọn giao diện phù hợp',
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Sáng')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Tối')),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Hệ thống'),
                  ),
                ],
                selected: {state.themeMode},
                onSelectionChanged: (value) => state.setThemeMode(value.first),
              ),
            ),
            const Divider(),
            const _SettingRow(
              icon: Icons.article_outlined,
              title: 'Giấy mặc định',
              subtitle: 'Ô vuông 5 mm',
              trailing: Icon(Icons.chevron_right),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.cloud_done_outlined),
              title: const Text(
                'Tự động lưu',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Lưu stroke vector ngay khi nhấc bút'),
              value: state.autoSave,
              onChanged: (value) {
                state.autoSave = value;
                state.saveGeneralSettings();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hồ sơ hiển thị',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: state.studentName,
              decoration: const InputDecoration(
                labelText: 'Tên học viên',
                hintText: 'Ví dụ: Eryk',
              ),
              onChanged: (value) => state.studentName = value,
              onEditingComplete: state.saveGeneralSettings,
            ),
            const SizedBox(height: 16),
            const _FieldLabel('TRÌNH ĐỘ HIỂN THỊ'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const ['N5', 'N4', 'N3', 'N2', 'N1']
                  .map(
                    (value) => ButtonSegment(value: value, label: Text(value)),
                  )
                  .toList(),
              selected: {state.jlpt},
              onSelectionChanged: (value) {
                state.jlpt = value.first;
                state.saveGeneralSettings();
              },
            ),
          ],
        ),
      ),
    ],
  );
}

class _PencilSettings extends StatelessWidget {
  const _PencilSettings({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Apple Pencil', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 5),
      const Text(
        'Pencil để viết · Ngón tay để di chuyển và thu phóng',
        style: TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 18),
      SectionCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Nét theo lực bút',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Độ dày thay đổi theo lực nhấn nếu thiết bị hỗ trợ',
              ),
              secondary: const Icon(Icons.line_weight_rounded),
              value: state.pressureEnabled,
              onChanged: (value) {
                state.pressureEnabled = value;
                state.saveGeneralSettings();
              },
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Double-tap đổi sang tẩy',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              secondary: const Icon(Icons.touch_app_outlined),
              value: state.doubleTapEraser,
              onChanged: (value) {
                state.doubleTapEraser = value;
                state.saveGeneralSettings();
              },
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Palm rejection',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Không tạo nét ngoài ý muốn khi đặt tay lên màn hình',
              ),
              secondary: const Icon(Icons.pan_tool_outlined),
              value: state.palmRejection,
              onChanged: (value) {
                state.palmRejection = value;
                state.saveGeneralSettings();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Khu vực thử nét bút',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Container(
              height: 190,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xffdedbd3)),
              ),
              child: const Center(
                child: Text(
                  'Viết thử tại đây bằng Apple Pencil',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AiSettings extends StatefulWidget {
  const _AiSettings({required this.state});
  final AppState state;
  @override
  State<_AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<_AiSettings> {
  late final TextEditingController keyController;
  bool reveal = false;
  bool replacing = false;
  bool testing = false;
  bool tested = false;
  AiModelSlot activeSlot = AiModelSlot.translate;
  String? error;
  String modelSearch = '';

  @override
  void initState() {
    super.initState();
    keyController = TextEditingController();
  }

  @override
  void dispose() {
    keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.state.hasApiKey && !replacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.explain),
            const SizedBox(width: 10),
            Text(
              'AI qua OpenRouter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.translate.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.privacy_tip_outlined, color: AppColors.translate),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Các công cụ AI chỉ xử lý vùng bạn chủ động khoanh. Tra từ ngoại tuyến không gửi dữ liệu lên AI.',
                  style: TextStyle(height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('PROVIDER'),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Color(0xff1f2633),
                  child: Icon(Icons.route_rounded, color: Colors.white),
                ),
                title: Text(
                  'OpenRouter',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Một API key, nhiều model theo từng chức năng'),
                trailing: Chip(label: Text('Cố định')),
              ),
              const Divider(height: 28),
              const _FieldLabel('OPENROUTER API KEY'),
              const SizedBox(height: 8),
              if (configured)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.key_rounded),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '••••••••••••••••',
                          style: TextStyle(fontSize: 18, letterSpacing: 2),
                        ),
                      ),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppColors.dictionary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'Đã lưu',
                        style: TextStyle(
                          color: AppColors.dictionary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => replacing = true),
                        child: const Text('Thay key'),
                      ),
                      TextButton(
                        onPressed: _deleteKey,
                        child: const Text('Xóa key'),
                      ),
                    ],
                  ),
                )
              else ...[
                TextField(
                  controller: keyController,
                  obscureText: !reveal,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'sk-or-v1-...',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => reveal = !reveal),
                      icon: Icon(
                        reveal
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Lấy API key tại openrouter.ai/keys',
                  style: TextStyle(color: AppColors.primary, fontSize: 12),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(error!)),
                    ],
                  ),
                ),
              ],
              if (tested) ...[
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.dictionary),
                    SizedBox(width: 8),
                    Text(
                      'Kết nối thành công',
                      style: TextStyle(
                        color: AppColors.dictionary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: testing ? null : _testConnection,
                icon: testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cable_rounded),
                label: Text(testing ? 'Đang kiểm tra...' : 'Kiểm tra kết nối'),
              ),
              const Divider(height: 34),
              const _FieldLabel('MODEL THEO CHỨC NĂNG'),
              const SizedBox(height: 6),
              Text(
                'Chọn riêng model để cân bằng chất lượng, tốc độ và chi phí.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ...AiModelSlot.values.map(
                (slot) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ModelAssignmentTile(
                    state: widget.state,
                    slot: slot,
                    enabled: configured || tested,
                    onOpen: () {
                      activeSlot = slot;
                      _showModelPicker(slot);
                    },
                    onManual: () {
                      activeSlot = slot;
                      _showManualModelDialog(slot);
                    },
                  ),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: widget.state.useAiVision,
                onChanged: configured || tested
                    ? (value) =>
                          setState(() => widget.state.useAiVision = value)
                    : null,
                title: const Text('Dùng AI nhận diện ảnh'),
                subtitle: const Text(
                  'Tắt để dùng OCR ML Kit trên máy và không phát sinh phí.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cá nhân hóa lời giải',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('TRÌNH ĐỘ JLPT'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const ['N5', 'N4', 'N3', 'N2', 'N1']
                    .map(
                      (value) =>
                          ButtonSegment(value: value, label: Text(value)),
                    )
                    .toList(),
                selected: {widget.state.jlpt},
                onSelectionChanged: (value) =>
                    setState(() => widget.state.jlpt = value.first),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: widget.state.explanationLanguage,
                decoration: const InputDecoration(
                  labelText: 'Ngôn ngữ giải thích',
                ),
                items: const ['Tiếng Việt', 'English', '日本語']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    widget.state.explanationLanguage = value ?? 'Tiếng Việt',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                '🔒 Key được lưu an toàn trên thiết bị, không xuất hiện trong notebook hoặc analytics.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Lưu cài đặt'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _testConnection() async {
    final key = (widget.state.hasApiKey && !replacing)
        ? widget.state.apiKey
        : keyController.text.trim();
    if (key.isEmpty) {
      setState(() => error = 'Hãy nhập API key trước khi kiểm tra.');
      return;
    }
    setState(() {
      testing = true;
      error = null;
      tested = false;
    });
    try {
      await widget.state.aiService.testConnection(key);
      final models = await widget.state.aiService.listModels(key);
      if (!mounted) return;
      widget.state.availableModels = models;
      if (models.isNotEmpty) {
        final preferred = models.first;
        final visionPreferred =
            models.where((model) => model.vision).firstOrNull ?? preferred;
        for (final slot in AiModelSlot.values) {
          if ((widget.state.modelIds[slot] ?? '').isEmpty) {
            widget.state.setModelFor(
              slot,
              slot == AiModelSlot.vision ? visionPreferred : preferred,
            );
          }
        }
      }
      widget.state.availableModels = [
        ...models,
        ...widget.state.savedModels.where(
          (saved) => !models.any((model) => model.id == saved.id),
        ),
      ];
      setState(() => tested = true);
    } catch (exception) {
      if (mounted) setState(() => error = _friendlyError(exception));
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  String _friendlyError(Object exception) {
    final text = exception.toString();
    if (text.contains('401')) return 'API key không hợp lệ.';
    if (text.contains('SocketException')) {
      return 'Không thể kết nối. Hãy kiểm tra mạng.';
    }
    return 'Không thể kết nối. Hãy kiểm tra API key hoặc mạng.';
  }

  Future<void> _save() async {
    final key = replacing || !widget.state.hasApiKey
        ? keyController.text.trim()
        : widget.state.apiKey;
    if (key.isEmpty) {
      setState(() => error = 'API key chưa được nhập.');
      return;
    }
    if (widget.state.modelIds.values.every((id) => id.isEmpty) &&
        widget.state.selectedModelId.isEmpty) {
      setState(() => error = 'Hãy kiểm tra kết nối và chọn ít nhất một model.');
      return;
    }
    await widget.state.saveAiSettings(key: key);
    if (!mounted) return;
    setState(() {
      replacing = false;
      tested = true;
      error = null;
      keyController.clear();
    });
    showAppSnack(context, 'Đã lưu cài đặt AI');
  }

  Future<void> _deleteKey() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa API key?'),
        content: const Text(
          'Các công cụ AI sẽ tạm dừng. Notebook, Bút, Highlight, PDF và Tra từ vẫn hoạt động bình thường.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xóa key'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await widget.state.deleteApiKey();
      if (mounted) {
        setState(() {
          tested = false;
          replacing = false;
        });
      }
    }
  }

  Future<void> _showModelPicker(AiModelSlot slot) async {
    if (widget.state.availableModels.isEmpty) {
      setState(() => error = 'Bấm “Kiểm tra kết nối” để tải danh sách model.');
      return;
    }
    var visionOnly = slot == AiModelSlot.vision;
    var freeOnly = false;
    modelSearch = '';
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final models = widget.state.availableModels
              .where(
                (model) =>
                    (model.name.toLowerCase().contains(
                          modelSearch.toLowerCase(),
                        ) ||
                        model.id.toLowerCase().contains(
                          modelSearch.toLowerCase(),
                        )) &&
                    (!visionOnly || model.vision) &&
                    (!freeOnly || model.free),
              )
              .toList();
          return Dialog(
            child: SizedBox(
              width: 660,
              height: 620,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Chọn model OpenRouter',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      onChanged: (value) =>
                          setDialogState(() => modelSearch = value),
                      decoration: const InputDecoration(
                        hintText: 'Tìm model...',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Có hỗ trợ ảnh'),
                          selected: visionOnly,
                          onSelected: (value) =>
                              setDialogState(() => visionOnly = value),
                        ),
                        FilterChip(
                          label: const Text('Miễn phí'),
                          selected: freeOnly,
                          onSelected: (value) =>
                              setDialogState(() => freeOnly = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: models.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final model = models[index];
                          final selected =
                              model.id == widget.state.modelIds[slot];
                          return ListTile(
                            selected: selected,
                            selectedTileColor: const Color(0xffdce1ff),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Text(
                              model.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${model.id}\nContext ${(model.contextLength / 1000).round()}K',
                            ),
                            isThreeLine: true,
                            trailing: Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (model.vision)
                                  const Chip(label: Text('Vision')),
                                if (model.free) const Chip(label: Text('Free')),
                                if (selected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppColors.primary,
                                  ),
                              ],
                            ),
                            onTap: () {
                              setState(
                                () => widget.state.setModelFor(slot, model),
                              );
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showManualModelDialog(AiModelSlot slot) async {
    final controller = TextEditingController();
    final nameController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nhập model · ${slot.label}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Model ID',
                  hintText: 'google/gemini-2.0-flash-001',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên hiển thị (tùy chọn)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim().isNotEmpty),
            child: const Text('Lưu model'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final id = controller.text.trim();
      final model = OpenRouterModel(
        id: id,
        name: nameController.text.trim().isEmpty
            ? id
            : nameController.text.trim(),
        contextLength: 0,
        vision: slot == AiModelSlot.vision,
        free: id.endsWith(':free'),
      );
      widget.state.setModelFor(slot, model);
      await widget.state.saveAiSettings(key: '');
      if (mounted) setState(() {});
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    nameController.dispose();
  }
}

class _ModelAssignmentTile extends StatelessWidget {
  const _ModelAssignmentTile({
    required this.state,
    required this.slot,
    required this.enabled,
    required this.onOpen,
    required this.onManual,
  });
  final AppState state;
  final AiModelSlot slot;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onManual;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onOpen : null,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: enabled
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : Theme.of(context).disabledColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            _slotIcon(slot),
            color: enabled ? _slotColor(slot) : Colors.grey,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 118,
            child: Text(
              slot.label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: (state.modelIds[slot] ?? '').isEmpty
                ? const Text(
                    'Chọn model...',
                    style: TextStyle(color: Colors.grey),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.modelNameFor(slot).isEmpty
                            ? state.modelIds[slot]!
                            : state.modelNameFor(slot),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        state.modelIds[slot]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
          ),
          if ((state.modelIds[slot] ?? '').isNotEmpty)
            const Icon(
              Icons.check_circle,
              color: AppColors.dictionary,
              size: 19,
            ),
          IconButton(
            tooltip: 'Nhập model ID',
            onPressed: enabled ? onManual : null,
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
          const Icon(Icons.expand_more),
        ],
      ),
    ),
  );
}

IconData _slotIcon(AiModelSlot slot) => switch (slot) {
  AiModelSlot.vision => Icons.document_scanner_outlined,
  AiModelSlot.translate => Icons.translate_rounded,
  AiModelSlot.explain => Icons.auto_awesome_outlined,
  AiModelSlot.solve => Icons.fact_check_outlined,
  AiModelSlot.weakness => Icons.bookmark_add_outlined,
  AiModelSlot.dictionary => Icons.auto_stories_outlined,
};

Color _slotColor(AiModelSlot slot) => switch (slot) {
  AiModelSlot.vision => AppColors.dictionary,
  AiModelSlot.translate => AppColors.translate,
  AiModelSlot.explain => AppColors.explain,
  AiModelSlot.solve => AppColors.primary,
  AiModelSlot.weakness => AppColors.weakness,
  AiModelSlot.dictionary => AppColors.translate,
};

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Text(
    value,
    style: const TextStyle(
      fontSize: 11,
      letterSpacing: .8,
      fontWeight: FontWeight.w800,
      color: Colors.grey,
    ),
  );
}

class _PrivacySettings extends StatelessWidget {
  const _PrivacySettings();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Dữ liệu & quyền riêng tư',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 18),
      const SectionCard(
        child: Column(
          children: [
            _SettingRow(
              icon: Icons.phonelink_lock_outlined,
              title: 'Dữ liệu vở',
              subtitle: 'Lưu cục bộ trên thiết bị',
              trailing: Icon(Icons.check_circle, color: AppColors.dictionary),
            ),
            Divider(),
            _SettingRow(
              icon: Icons.crop_free_rounded,
              title: 'Vùng gửi tới AI',
              subtitle: 'Chỉ vùng bạn chủ động khoanh',
              trailing: Icon(Icons.check_circle, color: AppColors.dictionary),
            ),
            Divider(),
            _SettingRow(
              icon: Icons.menu_book_outlined,
              title: 'Tra từ',
              subtitle: 'Database ngoại tuyến, không gọi AI',
              trailing: Icon(Icons.check_circle, color: AppColors.dictionary),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AboutSettings extends StatelessWidget {
  const _AboutSettings();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Giới thiệu', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 18),
      SectionCard(
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
                width: 72,
                height: 72,
                cacheWidth: 216,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Note Eryk',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text('Notebook trước, AI sau.'),
            const SizedBox(height: 14),
            const Text('Phiên bản 1.0.0', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    ],
  );
}
