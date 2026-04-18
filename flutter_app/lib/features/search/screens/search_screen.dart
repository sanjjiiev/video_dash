import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../home/widgets/video_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  const SearchScreen({super.key, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _ctrl;
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _activeFilter = 'All';

  static const _filters = ['All', 'Videos', 'Channels', 'Playlists', 'Shorts'];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery ?? '');
    if (widget.initialQuery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(searchProvider.notifier).search(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchProvider.notifier).search(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor:    AppColors.darkBg,
        surfaceTintColor:   Colors.transparent,
        leading:            BackButton(color: AppColors.textPrimary,
                              onPressed: () => context.pop()),
        title: TextField(
          controller:  _ctrl,
          focusNode:   _focusNode,
          autofocus:   widget.initialQuery == null,
          onChanged:   _onChanged,
          onSubmitted: (q) => ref.read(searchProvider.notifier).search(q),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            hintText:    'Search videos, channels…',
            hintStyle:   const TextStyle(color: AppColors.textTertiary),
            border:      InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textTertiary, size: 20),
                    onPressed: () {
                      _ctrl.clear();
                      ref.read(searchProvider.notifier).clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_rounded, color: AppColors.textSecondary),
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _FilterBar(
            filters:  _filters,
            selected: _activeFilter,
            onSelect: (f) => setState(() => _activeFilter = f),
          ),
        ),
      ),

      body: searchState.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentOrange))
          : searchState.videos.isEmpty && _ctrl.text.isEmpty
              ? _buildSearchSuggestions()
              : searchState.videos.isEmpty
                  ? _buildNoResults()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'About ${searchState.videos.length} results for "${_ctrl.text}"',
                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: searchState.videos.length,
                            itemBuilder: (_, i) => VideoCard(
                              video:      searchState.videos[i],
                              horizontal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildSearchSuggestions() {
    final trending = [
      'Flutter tutorial 2024',
      'HLS streaming explained',
      'media_kit flutter player',
      'AES-128 video encryption',
      'MinIO self-hosted storage',
      'FFmpeg transcoding guide',
    ];

    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Trending searches',
            style: TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w700, fontSize: 14)),
        ),
        ...trending.map((q) => ListTile(
          leading: const Icon(Icons.trending_up_rounded, color: AppColors.accentOrange, size: 20),
          title: Text(q, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          onTap: () {
            _ctrl.text = q;
            ref.read(searchProvider.notifier).search(q);
            setState(() {});
          },
        )),
      ],
    );
  }

  Widget _buildNoResults() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_off_rounded, size: 64, color: AppColors.textTertiary),
        const SizedBox(height: 16),
        Text('No results for "${_ctrl.text}"',
          style: const TextStyle(color: AppColors.textSecondary,
              fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        const Text('Try different keywords or check your spelling',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
      ],
    ),
  );
}

class _FilterBar extends StatelessWidget {
  final List<String>  filters;
  final String        selected;
  final ValueChanged<String> onSelect;

  const _FilterBar({required this.filters, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Container(
    height: 50, color: AppColors.darkBg,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: filters.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label:        Text(filters[i]),
          selected:     filters[i] == selected,
          onSelected:   (_) => onSelect(filters[i]),
          selectedColor: AppColors.accentOrange.withOpacity(0.2),
          backgroundColor: AppColors.darkElevated,
          side: BorderSide(
            color: filters[i] == selected ? AppColors.accentOrange : AppColors.darkBorder,
          ),
          labelStyle: TextStyle(
            color:      filters[i] == selected ? AppColors.accentOrange : AppColors.textSecondary,
            fontWeight: filters[i] == selected ? FontWeight.w700 : FontWeight.normal,
            fontSize: 12,
          ),
          showCheckmark: false,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    ),
  );
}
