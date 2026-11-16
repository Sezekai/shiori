import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

/// The three library sections.
enum Section {
  comics('Comics'),
  artbooks('Art Books'),
  manga('Manga');

  const Section(this.label);
  final String label;

  static Section byName(String n) =>
      Section.values.firstWhere((s) => s.name == n, orElse: () => Section.comics);
}

enum ReadDirection { ltr, rtl, ttb }

enum VerticalStyle { paged, strip }

enum PageLayout { single, double, auto }

enum FitMode { screen, width, height, original }

enum SplitMode { off, split, singleOnly }

enum SaveFormat { original, jpg, png }

/// Per-section settings.
class SectionSettings {
  List<String> folders;
  List<String> excluded; // folder names skipped anywhere under the roots
  String saveFolder;
  ReadDirection direction;
  VerticalStyle verticalStyle;
  PageLayout layout;
  FitMode fit;
  bool coverOffset;
  SplitMode split;
  bool crop;
  String gridStyle; // comfortable, compact, cover, staggered
  double tileSize;
  bool listView;
  String sort;
  bool sortDesc;
  bool comicsFolderView;
  double coverRadius; // corner rounding of covers in the grid
  bool coverFill; // fill the tile (crop) instead of fitting inside it
  Map<String, String> presets; // name -> json of filter + sort

  SectionSettings({
    required this.folders,
    required this.excluded,
    required this.saveFolder,
    required this.direction,
    this.verticalStyle = VerticalStyle.paged,
    this.layout = PageLayout.auto,
    this.fit = FitMode.screen,
    this.coverOffset = true,
    this.split = SplitMode.singleOnly,
    this.crop = false,
    this.gridStyle = 'comfortable',
    this.tileSize = 180,
    this.listView = false,
    this.sort = 'title',
    this.sortDesc = false,
    this.comicsFolderView = true,
    this.coverRadius = 6,
    this.coverFill = true,
    Map<String, String>? presets,
  }) : presets = presets ?? {};

  Map<String, dynamic> toJson() => {
        'folders': folders,
        'excluded': excluded,
        'saveFolder': saveFolder,
        'direction': direction.name,
        'verticalStyle': verticalStyle.name,
        'layout': layout.name,
        'fit': fit.name,
        'coverOffset': coverOffset,
        'split': split.name,
        'crop': crop,
        'gridStyle': gridStyle,
        'tileSize': tileSize,
        'listView': listView,
        'sort': sort,
        'sortDesc': sortDesc,
        'comicsFolderView': comicsFolderView,
        'coverRadius': coverRadius,
        'coverFill': coverFill,
        'presets': presets,
      };

  static T _enum<T extends Enum>(List<T> values, Object? v, T fallback) =>
      values.firstWhere((e) => e.name == v, orElse: () => fallback);

  static SectionSettings fromJson(Map m, SectionSettings d) => SectionSettings(
        folders: (m['folders'] as List?)?.cast<String>() ?? d.folders,
        excluded: (m['excluded'] as List?)?.cast<String>() ?? d.excluded,
        saveFolder: m['saveFolder'] as String? ?? d.saveFolder,
        direction: _enum(ReadDirection.values, m['direction'], d.direction),
        verticalStyle:
            _enum(VerticalStyle.values, m['verticalStyle'], d.verticalStyle),
        layout: _enum(PageLayout.values, m['layout'], d.layout),
        fit: _enum(FitMode.values, m['fit'], d.fit),
        coverOffset: m['coverOffset'] as bool? ?? d.coverOffset,
        split: _enum(SplitMode.values, m['split'], d.split),
        crop: m['crop'] as bool? ?? d.crop,
        gridStyle: m['gridStyle'] as String? ?? d.gridStyle,
        tileSize: (m['tileSize'] as num?)?.toDouble() ?? d.tileSize,
        listView: m['listView'] as bool? ?? d.listView,
        sort: m['sort'] as String? ?? d.sort,
        sortDesc: m['sortDesc'] as bool? ?? d.sortDesc,
        comicsFolderView: m['comicsFolderView'] as bool? ?? d.comicsFolderView,
        coverRadius: (m['coverRadius'] as num?)?.toDouble() ?? d.coverRadius,
        coverFill: m['coverFill'] as bool? ?? d.coverFill,
        presets: (m['presets'] as Map?)?.cast<String, String>() ?? {},
      );

  static SectionSettings defaults(Section s) {
    switch (s) {
      case Section.manga:
        return SectionSettings(
          folders: [r'E:\Pictures\IMGs\Doujinshi'],
          excluded: ['.yacreaderlibrary'],
          saveFolder: r'E:\Pictures\Shiori\Saved Pages\Manga',
          direction: ReadDirection.rtl,
        );
      case Section.comics:
        return SectionSettings(
          folders: [r'E:\Documents\COMICS'],
          excluded: ['.yacreaderlibrary'],
          saveFolder: r'E:\Pictures\Shiori\Saved Pages\Comics',
          direction: ReadDirection.ltr,
        );
      case Section.artbooks:
        return SectionSettings(
          folders: [r'E:\Documents\ART BOOKS & GUIDES'],
          excluded: ['.yacreaderlibrary', 'Archives'],
          saveFolder: r'E:\Pictures\Shiori\Saved Pages\Art Books',
          direction: ReadDirection.ltr,
          coverOffset: false,
          layout: PageLayout.single,
          split: SplitMode.off,
        );
    }
  }
}

class Settings extends ChangeNotifier {
  Settings._();
  static final Settings I = Settings._();

  final Map<Section, SectionSettings> sections = {
    for (final s in Section.values) s: SectionSettings.defaults(s),
  };
  SaveFormat saveFormat = SaveFormat.original;
  int jpgQuality = 92;
  int idleMinutes = 5;
  bool pageNumbers = true;
  bool progressLine = true;
  bool skipRead = false;
  bool watchFolders = true;
  bool yacImportOffered = false;
  String clickAction = 'select'; // select | tick
  Map<String, dynamic> windowState = {};
  double sidePanelWidth = 292;

  SectionSettings of(Section s) => sections[s]!;

  void load() {
    try {
      final f = File(AppPaths.I.settingsFile);
      if (!f.existsSync()) return;
      final m = jsonDecode(f.readAsStringSync()) as Map;
      final secs = m['sections'] as Map? ?? {};
      for (final s in Section.values) {
        final sm = secs[s.name];
        if (sm is Map) {
          sections[s] = SectionSettings.fromJson(sm, SectionSettings.defaults(s));
        }
      }
      saveFormat = SaveFormat.values.firstWhere(
          (e) => e.name == m['saveFormat'],
          orElse: () => SaveFormat.original);
      jpgQuality = ((m['jpgQuality'] as num?)?.toInt() ?? 92).clamp(1, 100);
      idleMinutes = ((m['idleMinutes'] as num?)?.toInt() ?? 5).clamp(1, 60);
      pageNumbers = m['pageNumbers'] as bool? ?? true;
      progressLine = m['progressLine'] as bool? ?? true;
      skipRead = m['skipRead'] as bool? ?? false;
      watchFolders = m['watchFolders'] as bool? ?? true;
      yacImportOffered = m['yacImportOffered'] as bool? ?? false;
      clickAction = m['clickAction'] as String? ?? 'select';
      windowState = (m['window'] as Map?)?.cast<String, dynamic>() ?? {};
      sidePanelWidth = (m['sidePanelWidth'] as num?)?.toDouble() ?? 292;
    } catch (_) {}
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'sections': {for (final e in sections.entries) e.key.name: e.value.toJson()},
        'saveFormat': saveFormat.name,
        'jpgQuality': jpgQuality,
        'idleMinutes': idleMinutes,
        'pageNumbers': pageNumbers,
        'progressLine': progressLine,
        'skipRead': skipRead,
        'watchFolders': watchFolders,
        'yacImportOffered': yacImportOffered,
        'clickAction': clickAction,
        'window': windowState,
        'sidePanelWidth': sidePanelWidth,
      };

  /// Changes apply straight away; there's no Save button.
  void save() {
    try {
      writeStringSafelySync(AppPaths.I.settingsFile,
          const JsonEncoder.withIndent('  ').convert(toJson()));
    } catch (_) {}
    notifyListeners();
  }

  void changedQuiet() => notifyListeners();

  void resetToDefaults() {
    for (final s in Section.values) {
      sections[s] = SectionSettings.defaults(s);
    }
    saveFormat = SaveFormat.original;
    jpgQuality = 92;
    idleMinutes = 5;
    pageNumbers = true;
    progressLine = true;
    skipRead = false;
    watchFolders = true;
    clickAction = 'select';
    save();
  }
}
