import 'dart:ffi';
import 'package:godot_dart/godot_dart.dart';

part 'menu_overlay.g.dart';

@GodotScript()
class MenuOverlay extends Control {
  @pragma('vm:entry-point')
  static ExtensionTypeInfo<MenuOverlay> get sTypeInfo => _$MenuOverlayTypeInfo();
  @override
  ExtensionTypeInfo<MenuOverlay> get typeInfo => MenuOverlay.sTypeInfo;

  @pragma('vm:entry-point')
  MenuOverlay() : super();
  @pragma('vm:entry-point')
  MenuOverlay.withNonNullOwner(Pointer<Void> owner) : super.withNonNullOwner(owner);

  // -----------------------------------------------------------
  // Panel bottom
  // -----------------------------------------------------------
  final double _panelW = 700;
  final double _panelH = 210;
  final double _margin = 24;

  late final Panel _panel;
  late final VBoxContainer _rootVbox;

  // Stepper UI
  late final HBoxContainer _header;
  late final Label _step1Label;
  late final Label _step2Label;

  late final Control _body;
  late final VBoxContainer _step1Container;
  late final VBoxContainer _step2Container;

  late final LineEdit _nameEdit;
  late final Label _nameHint;

  // Resource buttons (existing)
  late final HBoxContainer _iconsRow;
  final List<TextureButton> _resourceButtons = [];

  late final HBoxContainer _footer;
  late final Button _backBtn;
  late final Button _nextBtn;

  // state
  int _currentStep = 0; // 0=name, 1=resource
  bool _enabled = false; // dépend de la sélection de tuile (comme avant)
  String _name = '';

  @override
  void vReady() {
    setAnchorsPreset(ControlLayoutPreset.presetFullRect);

    _panel = Panel();
    _panel.setAnchorsPreset(ControlLayoutPreset.presetTopLeft);
    _panel.setMouseFilter(ControlMouseFilter.stop);
    _panel.setSize(Vector2(x: _panelW, y: _panelH));
    addChild(_panel);

    _rootVbox = VBoxContainer();
    _rootVbox.setAnchorsPreset(ControlLayoutPreset.presetFullRect);
    _rootVbox.setSize(Vector2(x: _panelW, y: _panelH));
    _panel.addChild(_rootVbox);

    // ---------------- Header (step indicators)
    _header = HBoxContainer();
    _header.setAlignment(BoxContainerAlignmentMode.alignmentCenter);
    _rootVbox.addChild(_header);

    _step1Label = Label()..setText('1  Nom');
    _step2Label = Label()..setText('2  Ressource');

    _header.addChild(_step1Label);
    _header.addChild(_spacer(24));
    _header.addChild(_step2Label);

    // ---------------- Body (two containers)
    _body = Control();
    _body.setCustomMinimumSize(Vector2(x: _panelW, y: 120));
    _rootVbox.addChild(_body);

    // Step 1 container
    _step1Container = VBoxContainer();
    _step1Container.setAnchorsPreset(ControlLayoutPreset.presetFullRect);
    _body.addChild(_step1Container);

    _nameHint = Label()..setText('Step 1: Name');
    _step1Container.addChild(_nameHint);

    _nameEdit = LineEdit();
    _nameEdit.setPlaceholder('Ex: mon-projet');
    _step1Container.addChild(_nameEdit);

    _nameEdit.textChanged.connect(this, (String newText) {
      _name = newText.trim();
      _refreshFooter();
    });

    // Step 2 container
    _step2Container = VBoxContainer();
    _step2Container.setAnchorsPreset(ControlLayoutPreset.presetFullRect);
    _body.addChild(_step2Container);

    final step2Title = Label()..setText('Step 2: Choose a resource');
    _step2Container.addChild(step2Title);

    _iconsRow = HBoxContainer();
    _iconsRow.setAlignment(BoxContainerAlignmentMode.alignmentCenter);
    _step2Container.addChild(_iconsRow);

    _addResourceItem(
      tooltip: 'GCP · Cloud Storage',
      path: 'res://src/assets/gcp_cloud_storage.png',
      kind: 'gcp:cloud_storage',
    );

    _addResourceItem(
      tooltip: 'GCP · Compute Engine',
      path: 'res://src/assets/gcp_compute_engine.png',
      kind: 'gcp:compute_engine',
    );

    // ---------------- Footer (Back / Next)
    _footer = HBoxContainer();
    _footer.setAlignment(BoxContainerAlignmentMode.alignmentCenter);
    _rootVbox.addChild(_footer);

    _backBtn = Button()..setText('Back');
    _nextBtn = Button()..setText('Next');

    _backBtn.pressed.connect(this, () => _goBack());
    _nextBtn.pressed.connect(this, () => _goNext());

    _footer.addChild(_backBtn);
    _footer.addChild(_spacer(18));
    _footer.addChild(_nextBtn);

    // initial
    setProcess(true);
    _positionBottomCenter();
    _panel.show();

    setEnabled(false);  // comme avant : dépend de la tuile sélectionnée
    _setStep(0);
  }

  @override
  void vProcess(double delta) => _positionBottomCenter();

  // -----------------------------------------------------------
  // Public API (appelé par AppRoot en fonction du state selectedTile)
  // -----------------------------------------------------------
  void setEnabled(bool enabled) {
    _enabled = enabled;
    // règle simple: on peut avancer au step 2 seulement si tuile sélectionnée + nom non vide
    _refreshFooter();

    for (final b in _resourceButtons) {
      b.setDisabled(!enabled);
      b.setModulate(Color.fromRGBA(1, 1, 1, enabled ? 1.0 : 0.4));
    }
  }

  // -----------------------------------------------------------
  // Step logic
  // -----------------------------------------------------------
  void _setStep(int step) {
    _currentStep = step;

    _step1Container.setVisible(step == 0);
    _step2Container.setVisible(step == 1);

    // Indicateur simple (tu pourras styliser)
    _step1Label.setModulate(Color.fromRGBA(1, 1, 1, step == 0 ? 1.0 : 0.5));
    _step2Label.setModulate(Color.fromRGBA(1, 1, 1, step == 1 ? 1.0 : 0.5));

    _refreshFooter();
  }

  void _goBack() {
    if (_currentStep <= 0) return;
    _setStep(_currentStep - 1);
  }

  void _goNext() {
    if (_currentStep == 0) {
      final name = _name.trim();
      if (name.isEmpty) return;

      // Notifier AppRoot du nom validé (optionnel mais utile)
      final parent = getParent();
      if (parent != null) {
        parent.call('onStepperNameSubmitted', vargs: [Variant(name)]);
      }

      _setStep(1);
      return;
    }

    // step 2: pas de "next" obligatoire -> on pourrait mettre Finish, ou rien
    // Ici on ne fait rien : le choix de ressource se fait via clic sur icône.
  }

  void _refreshFooter() {
    _backBtn.setDisabled(_currentStep == 0);

    if (_currentStep == 0) {
      // Step 1: Next activé seulement si nom non vide
      final ok = _name.trim().isNotEmpty;
      _nextBtn.setText('Next');
      _nextBtn.setDisabled(!ok);
      _nextBtn.setModulate(Color.fromRGBA(1, 1, 1, ok ? 1.0 : 0.4));
      return;
    }

    // Step 2: on peut laisser Next désactivé ou faire un "Finish"
    _nextBtn.setText('Submit');
    _nextBtn.setDisabled(true);
    _nextBtn.setModulate(Color.fromRGBA(1, 1, 1, 0.4));
  }

  // -----------------------------------------------------------
  // Resource buttons
  // -----------------------------------------------------------
  void _addResourceItem({
    required String tooltip,
    required String path,
    required String kind,
  }) {
    final btn = TextureButton();
    btn.setTooltipText(tooltip);
    btn.setCustomMinimumSize(Vector2(x: 64, y: 64));
    btn.setIgnoreTextureSize(true);
    btn.setStretchMode(TextureButtonStretchMode.stretchKeepAspectCentered);

    final tex = _loadTexture(path);
    if (tex != null) {
      btn.setTextureNormal(tex);
      btn.setTextureHover(tex);
      btn.setTexturePressed(tex);
      btn.setTextureDisabled(tex);
    }

    btn.pressed.connect(this, () {
      if (!_enabled) return;

      final parent = getParent();
      if (parent == null) return;

      // re-use existing hook AppRoot.onMenuItemChosen
      parent.call('onMenuItemChosen', vargs: [Variant(kind)]);
    });

    _resourceButtons.add(btn);
    _iconsRow.addChild(btn);
    _iconsRow.addChild(_spacer(16));
  }

  Control _spacer(double w) {
    final c = Control();
    c.setCustomMinimumSize(Vector2(x: w, y: 0));
    c.setMouseFilter(ControlMouseFilter.ignore);
    return c;
  }

  void _positionBottomCenter() {
    final vp = getViewport();
    if (vp == null) return;

    final sz = vp.getVisibleRect().size;
    final px = (sz.x - _panelW) * 0.5;
    final py = (sz.y - _panelH) - _margin;

    _panel.setPosition(Vector2(x: px, y: py));
    _panel.setSize(Vector2(x: _panelW, y: _panelH));
    _rootVbox.setSize(Vector2(x: _panelW, y: _panelH));
  }

  Texture2D? _loadTexture(String path) {
    final res = ResourceLoader.singleton.load(path);
    return (res is Texture2D) ? res : null;
  }
}