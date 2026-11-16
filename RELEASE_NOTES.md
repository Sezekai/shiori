# Shiori 1.1.1

**Fixes the crash at start-up** (and very likely the earlier crashes while scanning and while resizing the grid).

Windows recorded an access violation inside Flutter's accessibility bridge (`AccessibilityBridge::CreateRemoveReparentedNodesUpdate` in `flutter_windows.dll`). That bridge describes the window to screen readers and similar tools. When a Windows tool switched it on, it crashed whenever the library's layout changed quickly. Shiori no longer exposes its controls to that bridge.

Also: safe mode (after two unclean exits) now really pauses background cover making, as its message says.
