import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:config_moodle/core/theme/app_theme.dart';
import 'package:config_moodle/presentation/controllers/auth_controller.dart';
import 'package:config_moodle/presentation/controllers/config_controller.dart';
import 'package:config_moodle/presentation/controllers/sync_controller.dart';
import 'package:config_moodle/presentation/widgets/common_widgets.dart';

class SyncPreviewPage extends StatefulWidget {
  final String courseConfigId;
  const SyncPreviewPage({super.key, required this.courseConfigId});

  @override
  State<SyncPreviewPage> createState() => _SyncPreviewPageState();
}

class _SyncPreviewPageState extends State<SyncPreviewPage> {
  int _step = 0; // 0 = escolher curso, 1 = preview matches, 2 = syncing

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final configCtrl = context.read<ConfigController>();
      final auth = context.read<AuthController>();
      final sync = context.read<SyncController>();

      configCtrl.loadById(widget.courseConfigId);

      if (auth.isLoggedIn) {
        sync.loadCourses(auth.token, auth.baseUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final configCtrl = context.watch<ConfigController>();
    final syncCtrl = context.watch<SyncController>();
    final config = configCtrl.current;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context, config),
              _buildStepIndicator(),
              Expanded(
                child: !auth.isLoggedIn
                    ? const EmptyState(
                        icon: Icons.cloud_off,
                        title: 'Não conectado ao Moodle',
                        subtitle:
                            'Faça login no Moodle pela tela inicial primeiro.',
                      )
                    : config == null
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary))
                        : _buildContent(context, auth, configCtrl, syncCtrl),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, dynamic config) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => context.go('/editor/${widget.courseConfigId}'),
          ),
          const SizedBox(width: 8),
          const Text(
            'Sincronizar com Moodle',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          if (config?.moodleCourseName != null)
            StatusChip(
              label: config!.moodleCourseName!,
              color: AppTheme.accentGreen,
              icon: Icons.school,
            ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _stepDot(0, 'Disciplina'),
          _stepLine(0),
          _stepDot(1, 'Preview'),
          _stepLine(1),
          _stepDot(2, 'Sincronizar'),
        ],
      ),
    );
  }

  Widget _stepDot(int idx, String label) {
    final isActive = _step >= idx;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isActive ? AppTheme.primaryGradient : null,
            color: isActive ? null : AppTheme.bgCard,
            border: Border.all(
              color: isActive ? AppTheme.primary : AppTheme.divider,
            ),
          ),
          child: Center(
            child: isActive && _step > idx
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '${idx + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _stepLine(int afterIdx) {
    final isActive = _step > afterIdx;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 16),
        color: isActive ? AppTheme.primary : AppTheme.divider,
      ),
    );
  }

  Widget _buildContent(BuildContext context, AuthController auth,
      ConfigController configCtrl, SyncController syncCtrl) {
    switch (_step) {
      case 0:
        return _buildCourseSelector(context, auth, configCtrl, syncCtrl);
      case 1:
        return _buildMatchPreview(context, auth, configCtrl, syncCtrl);
      case 2:
        return _buildSyncProgress(context, auth, configCtrl, syncCtrl);
      default:
        return const SizedBox();
    }
  }

  // ── Step 0: Selecionar disciplina ─────────────────────────────────────────

  Widget _buildCourseSelector(BuildContext context, AuthController auth,
      ConfigController configCtrl, SyncController syncCtrl) {
    if (syncCtrl.loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }

    if (syncCtrl.courses.isEmpty) {
      return const EmptyState(
        icon: Icons.school,
        title: 'Nenhuma disciplina encontrada',
        subtitle: 'Não foram encontradas disciplinas no Moodle.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: syncCtrl.courses.length,
      itemBuilder: (context, index) {
        final course = syncCtrl.courses[index];
        final isSelected = configCtrl.current?.moodleCourseId == course.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            useGradient: isSelected,
            onTap: () async {
              configCtrl.linkMoodleCourse(course.id, course.fullname);
              await syncCtrl.loadMoodleSections(
                  auth.token, auth.baseUrl, course.id);
              syncCtrl.generateMatches(configCtrl.current!);
              setState(() => _step = 1);
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withAlpha(50)
                        : AppTheme.bgCardAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.school,
                    color:
                        isSelected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.fullname,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        course.shortname,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: AppTheme.accentGreen),
                const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Step 1: Preview dos matches ───────────────────────────────────────────

  Widget _buildMatchPreview(BuildContext context, AuthController auth,
      ConfigController configCtrl, SyncController syncCtrl) {
    if (syncCtrl.matches.isEmpty) {
      return const EmptyState(
        icon: Icons.compare_arrows,
        title: 'Sem correspondências',
        subtitle: 'Não foi possível encontrar correspondências.',
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: syncCtrl.matches.length,
            itemBuilder: (context, index) {
              final m = syncCtrl.matches[index];
              return _buildMatchCard(m);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _step = 0),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Voltar'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GradientButton(
                  label: 'Sincronizar Agora',
                  icon: Icons.sync,
                  onPressed: () {
                    setState(() => _step = 2);
                    syncCtrl.syncToMoodle(
                      auth.token,
                      auth.baseUrl,
                      configCtrl.current!,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMatchCard(SectionMatch match) {
    final hasMatch = match.moodleSection != null;
    final scoreColor = match.score > 0.8
        ? AppTheme.accentGreen
        : match.score > 0.5
            ? AppTheme.warning
            : AppTheme.danger;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LOCAL',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      Text(match.local.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Icon(
                  hasMatch ? Icons.link : Icons.link_off,
                  color: hasMatch ? AppTheme.accentGreen : AppTheme.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('MOODLE',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                      Text(
                        hasMatch
                            ? match.moodleSection!.name
                            : 'Sem correspondência',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: hasMatch
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  label: '${(match.score * 100).toStringAsFixed(0)}%',
                  color: scoreColor,
                ),
              ],
            ),
            if (match.activityMatches.isNotEmpty) ...[
              const Divider(color: AppTheme.divider, height: 20),
              ...match.activityMatches.map((am) => Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Row(
                      children: [
                        StatusChip(
                          label: am.local.activityType,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(am.local.name,
                                style: const TextStyle(fontSize: 12))),
                        Icon(
                          am.moodleModule != null
                              ? Icons.check_circle_outline
                              : Icons.help_outline,
                          size: 16,
                          color: am.moodleModule != null
                              ? AppTheme.accentGreen
                              : AppTheme.warning,
                        ),
                        if (am.moodleModule != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${(am.score * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ── Step 2: Progresso da sincronização ────────────────────────────────────

  Widget _buildSyncProgress(BuildContext context, AuthController auth,
      ConfigController configCtrl, SyncController syncCtrl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (syncCtrl.syncing)
                const SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              else
                Icon(
                  syncCtrl.error != null
                      ? Icons.error_outline
                      : Icons.check_circle,
                  size: 60,
                  color: syncCtrl.error != null
                      ? AppTheme.danger
                      : AppTheme.accentGreen,
                ),
              const SizedBox(height: 24),
              Text(
                syncCtrl.progressMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: syncCtrl.progress,
                  backgroundColor: AppTheme.bgCardAlt,
                  color: AppTheme.primary,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(syncCtrl.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              if (syncCtrl.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  syncCtrl.error!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
              if (!syncCtrl.syncing) ...[
                const SizedBox(height: 24),
                GradientButton(
                  label: 'Concluído',
                  icon: Icons.done,
                  onPressed: () =>
                      context.go('/editor/${widget.courseConfigId}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
