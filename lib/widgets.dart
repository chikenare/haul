/// haul's ready-made download list: every download, a parent (a show) as
/// one row that opens into its children ([HaulParentView]), each row with
/// its progress and its menu. Optional — an app wanting another look draws
/// its own list off the engine (`watchEntries`, `watchParent`, `pause`,
/// `delete`…). It follows the app's theme; [HaulTheme] for sizes and
/// colours, [HaulStrings] for its texts, [HaulMenuItem] for the app's own
/// entries in its menus.
library;

export 'src/widgets/download_widgets.dart' show HaulMenuItem, HaulMenuItems;
export 'src/widgets/haul_controller.dart';
export 'src/widgets/haul_strings.dart';
export 'src/widgets/parent_widgets.dart'
    show HaulDownloadList, HaulParentActions, HaulParentView;
