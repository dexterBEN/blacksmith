import 'dart:ffi';
import 'package:godot_dart/godot_dart.dart';
import 'package:blacksmith_front/core/di/service_locator.dart';

part 'menu_overlay.g.dart';

@GodotScript()
class MenuOverlay extends Control {
  @pragma('vm:entry-point')
  static ExtensionTypeInfo<MenuOverlay> get sTypeInfo =>
      _$MenuOverlayTypeInfo();

  @override
  ExtensionTypeInfo<MenuOverlay> get typeInfo => MenuOverlay.sTypeInfo;

  @pragma('vm:entry-point')
  MenuOverlay() : super();

  @pragma('vm:entry-point')
  MenuOverlay.withNonNullOwner(Pointer<Void> owner)
      : super.withNonNullOwner(owner);

  // ---------------------------------------------------------------------------
  // Configuration d'affichage
  // ---------------------------------------------------------------------------

  final double _panelW = 560;
  final double _panelH = 120;  // un peu plus haut pour respirer
  final double _margin = 24;
  final double _gap = 16;

  late final Panel _panel;
  late final HBoxContainer _hbox;
  final List<TextureButton> _buttons = [];

  bool _enabled = false;

  @override
  void vReady() {
    // Le Control global
    setAnchorsPreset(ControlLayoutPreset.presetFullRect);

    // --- PANEL ---
    _panel = Panel();
    _panel.setAnchorsPreset(ControlLayoutPreset.presetTopLeft);
    _panel.setMouseFilter(ControlMouseFilter.stop);
    _panel.setSize(Vector2(x: _panelW, y: _panelH));
    addChild(_panel);

    // --- HBOX ---
    _hbox = HBoxContainer();
    _hbox.setAnchorsPreset(ControlLayoutPreset.presetTopLeft);
    _hbox.setAlignment(BoxContainerAlignmentMode.alignmentCenter);
    _hbox.setSize(Vector2(x: _panelW, y: _panelH));
    _panel.addChild(_hbox);

    // -------------------------------------------------------------------------
    // Les boutons du menu (MANUELS)
    // -------------------------------------------------------------------------

    _addItem(
      tooltip: 'GCP · Cloud Storage',
      path: 'res://src/assets/gcp_cloud_storage.png',
      kind: 'gcp:cloud_storage',
    );

    _addItem(
      tooltip: 'GCP · Compute Engine',
      path: 'res://src/assets/gcp_compute_engine.png',
      kind: 'gcp:compute_engine',
    );

    setProcess(true);
    _positionBottomCenter();

    _panel.show();
    setEnabled(false);
  }

  @override
  void vProcess(double delta) {
    _positionBottomCenter();
  }

  // ---------------------------------------------------------------------------
  // PUBLIC: Activation/désactivation (ex: dépend de selectedTile != null)
  // ---------------------------------------------------------------------------

  void setEnabled(bool enabled) {
    _enabled = enabled;
    for (final b in _buttons) {
      b.setDisabled(!enabled);
      b.setModulate(Color.fromRGBA(1, 1, 1, enabled ? 1.0 : 0.4));
    }
  }

  // ---------------------------------------------------------------------------
  // BUTTON CREATION
  // ---------------------------------------------------------------------------

  void _addItem({
    required String tooltip,
    required String path,
    required String kind,
  }) {
    if (_buttons.isNotEmpty) _addSpacer(_gap);

    final btn = TextureButton();
    btn.setTooltipText(tooltip);

    // Taille désirée : 64 × 64
    btn.setCustomMinimumSize(Vector2(x: 64, y: 64));

    // ESSENTIEL POUR NE PAS QUE L'IMAGE GÉANTE PRENNE LE DESSUS
    btn.setIgnoreTextureSize(true);

    // On garde le ratio, centré
    btn.setStretchMode(TextureButtonStretchMode.stretchKeepAspectCentered);

    // Charger l'icône
    final tex = _loadTexture(path);
    if (tex != null) {
      btn.setTextureNormal(tex);
      btn.setTextureHover(tex);
      btn.setTexturePressed(tex);
      btn.setTextureDisabled(tex);
    } else {
      GD.pushWarning(Variant('[MenuOverlay] Texture introuvable: $path'));
    }

    // Callback clic : pass à AppRoot
    btn.pressed.connect(this, () {
      GD.print(Variant('[MenuOverlay] pressed: $kind'));

      if (!_enabled) {
        GD.print(Variant('[MenuOverlay] (disabled) — clic ignoré'));
        return;
      }

      final parent = getParent();
      if (parent == null) {
        GD.pushWarning(
          Variant('[MenuOverlay] Parent null, impossible de notifier AppRoot.'),
        );
        return;
      }

      // NOTE : on appelle maintenant "onMenuItemChosen" (sans underscore),
      // et la méthode est exportée dans AppRoot avec @GodotExport().
      parent.call(
        'onMenuItemChosen',
        vargs: [Variant(kind)],
      );
    });


    _buttons.add(btn);
    _hbox.addChild(btn);
  }

  void _addSpacer(double width) {
    final spacer = Control();
    spacer.setCustomMinimumSize(Vector2(x: width, y: 0));
    spacer.setMouseFilter(ControlMouseFilter.ignore);
    _hbox.addChild(spacer);
  }

  // ---------------------------------------------------------------------------
  // POSITIONNEMENT DU PANEL (toujours centré en bas)
  // ---------------------------------------------------------------------------

  void _positionBottomCenter() {
    final vp = getViewport();
    if (vp == null) return;

    final sz = vp.getVisibleRect().size;
    final px = (sz.x - _panelW) * 0.5; // centré horizontalement
    final py = (sz.y - _panelH) - _margin; // en bas avec marge

    _panel.setPosition(Vector2(x: px, y: py));
    _panel.setSize(Vector2(x: _panelW, y: _panelH));
    _hbox.setSize(Vector2(x: _panelW, y: _panelH));
  }

  // ---------------------------------------------------------------------------
  // UTIL
  // ---------------------------------------------------------------------------

  Texture2D? _loadTexture(String path) {
    final res = ResourceLoader.singleton.load(path);
    return (res is Texture2D) ? res : null;
  }
}