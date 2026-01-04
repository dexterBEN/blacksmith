import 'dart:ffi';
import 'dart:math' as math;
import 'package:godot_dart/godot_dart.dart';

// 🔗 DI + BLoC + model
import 'package:blacksmith_front/core/di/service_locator.dart';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_bloc.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_event.dart';
import 'package:blacksmith_front/domain/bloc/isomap_grid/isomap_grid_state.dart';

import 'package:blacksmith_front/domain/models/grid_resource.dart';

part 'isomap_grid.g.dart';

@GodotScript()
class IsoMapGrid extends Node2D {
  @pragma('vm:entry-point')
  static ExtensionTypeInfo<IsoMapGrid> get sTypeInfo =>
      _$IsoMapGridTypeInfo();
  @override
  ExtensionTypeInfo<IsoMapGrid> get typeInfo => IsoMapGrid.sTypeInfo;

  @pragma('vm:entry-point')
  IsoMapGrid() : super();

  @pragma('vm:entry-point')
  IsoMapGrid.withNonNullOwner(Pointer<Void> owner)
      : super.withNonNullOwner(owner);

  // ---- register BLoC ----
  IsomapGridBloc? get _bloc =>
      sl.isRegistered<IsomapGridBloc>() ? sl<IsomapGridBloc>() : null;

  // ---- params ----
  final int rows = 6;
  final int cols = 6;
  final double tileW = 64.0;
  final double tileH = 32.0;

  // grid background + highlight
  final Color fillColor    = Color.html('#FFFFFFFF'); // white
  final Color lineColor    = Color.html('#B0B0B0FF');
  final Color selectedFill = Color.html('#F1C40FFF'); // yellow
  final Color selectedLine = Color.html('#D4AC0DFF');

  late final List<List<Polygon2D>> _tiles;
  late final List<List<Line2D>> _edges;
  late final List<List<Sprite2D?>> _icons; // sprites in tiles

  int _selR = -1; // use by placeIconOnSelected (fallback)
  int _selC = -1;

  Vector2? _lastVpSize;

  // ======================================================================
  // lifecycle
  // ======================================================================

  @override
  void vReady() {
    _buildGrid();

    setProcess(true);
    setProcessInput(true);
    setProcessUnhandledInput(true);

    _recenterByBounds();

    // BLoC initial setup
    final bloc = _bloc;
    if (bloc != null) {
      render(bloc.state);
      GD.print(Variant('[IsoMapGrid] (vReady): BLoC is loaded'));
    } else {
      GD.print(Variant('[IsoMapGrid] (vReady): BLoC not loaded'));
    }
  }

  @override
  void vProcess(double delta) {
    final vp = getViewport();
    if (vp == null) return;
    final size = vp.getVisibleRect().size;

    if (_lastVpSize == null ||
        size.x != _lastVpSize!.x ||
        size.y != _lastVpSize!.y) {
      _lastVpSize = Vector2(x: size.x, y: size.y);
      _recenterByBounds();
    }
  }

  // ======================================================================
  // Input
  // ======================================================================

  @override
  void vInput(InputEvent? event) =>
      _handleClick(event, source: 'vInput');

  @override
  void vUnhandledInput(InputEvent? event) =>
      _handleClick(event, source: 'vUnhandledInput');

  void _handleClick(InputEvent? event, {required String source}) {
    if (event is! InputEventMouseButton) return;
    if (event.getButtonIndex() != MouseButton.left) return;
    if (!event.isPressed()) return;

    final global = event.getPosition();
    final gp = getGlobalPosition();
    final localPos = Vector2(x: global.x - gp.x, y: global.y - gp.y);

    GD.print(Variant(
        '[IsoMapGrid][$source] click global=$global local=$localPos'));

    final rc = _localToGrid(localPos);
    if (rc == null) return;

    final r = rc.$1;
    final c = rc.$2;
    if (r < 0 || r >= rows || c < 0 || c >= cols) return;

    final bloc = _bloc;
    if (bloc != null) {
      // 🔁 driven by the BLoC
      bloc.add(TileClicked(GridPos(r, c)));
    } else {
      // 🔁 fallback
      _selectTile(r, c);
    }
  }

  // ======================================================================
  // Construction de la grille
  // ======================================================================

  void _buildGrid() {
    _tiles = List.generate(rows, (_) => List.filled(cols, Polygon2D()));
    _edges = List.generate(rows, (_) => List.filled(cols, Line2D()));
    _icons =
        List.generate(rows, (_) => List<Sprite2D?>.filled(cols, null));

    final diamond = _tileDiamond();

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final pos = _gridToIso(r, c);

        // conteneur positionné (origin = centre du losange)
        final area = Node2D();
        area.setPosition(pos);
        addChild(area);

        // tuile visuelle
        final tile = Polygon2D();
        tile.setPolygon(diamond);
        tile.setColor(fillColor);
        tile.setZAsRelative(false);
        tile.setZIndex((r + c) * 2);
        area.addChild(tile);
        _tiles[r][c] = tile;

        // contour
        final edges = Line2D();
        edges.setDefaultColor(lineColor);
        edges.setWidth(1.0); // fin
        edges.setAntialiased(true);

        final outline = PackedVector2Array()
          ..pushBack(Vector2(x: -tileW * 0.5, y: 0))
          ..pushBack(Vector2(x: 0, y: -tileH * 0.5))
          ..pushBack(Vector2(x: tileW * 0.5, y: 0))
          ..pushBack(Vector2(x: 0, y: tileH * 0.5))
          ..pushBack(Vector2(x: -tileW * 0.5, y: 0));
        edges.setPoints(outline);

        edges.setZAsRelative(false);
        edges.setZIndex((r + c) * 2 + 1);
        area.addChild(edges);
        _edges[r][c] = edges;
      }
    }
  }

  PackedVector2Array _tileDiamond() {
    final verts = PackedVector2Array()
      ..pushBack(Vector2(x: -tileW * 0.5, y: 0))
      ..pushBack(Vector2(x: 0, y: -tileH * 0.5))
      ..pushBack(Vector2(x: tileW * 0.5, y: 0))
      ..pushBack(Vector2(x: 0, y: tileH * 0.5));
    return verts;
  }

  Vector2 _gridToIso(int r, int c) {
    final x = (c - r) * (tileW * 0.5);
    final y = (c + r) * (tileH * 0.5);
    return Vector2(x: x, y: y);
  }

  (int, int)? _localToGrid(Vector2 p) {
    final a = (2.0 * p.x) / tileW; // c - r
    final b = (2.0 * p.y) / tileH; // c + r
    final c = (a + b) * 0.5;
    final r = (b - a) * 0.5;

    final rr = _roundToInt(r);
    final cc = _roundToInt(c);

    if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) return null;
    return (rr, cc);
  }

  int _roundToInt(double v) {
    final f = v.floor();
    final frac = v - f;
    return (frac >= 0.5) ? (f + 1) : f;
  }

  /// Ancien comportement local (fallback quand pas de BLoC)
  void _selectTile(int r, int c) {
    if (_selR >= 0 && _selC >= 0) {
      _tiles[_selR][_selC].setColor(fillColor);
      _edges[_selR][_selC].setDefaultColor(lineColor);
    }

    _tiles[r][c].setColor(selectedFill);
    _edges[r][c].setDefaultColor(selectedLine);

    _selR = r;
    _selC = c;
  }

  void _recenterByBounds() {
    final vp = getViewport();
    if (vp == null) return;
    final vpSize = vp.getVisibleRect().size;

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    final hx = tileW * 0.5, hy = tileH * 0.5;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        // IMPORTANT : position du conteneur (parent de la tuile), pas (0,0)
        final area = _tiles[r][c].getParent() as Node2D;
        final p = area.getPosition();

        if (p.x - hx < minX) minX = p.x - hx;
        if (p.y - hy < minY) minY = p.y - hy;
        if (p.x + hx > maxX) maxX = p.x + hx;
        if (p.y + hy > maxY) maxY = p.y + hy;
      }
    }

    final gridW = maxX - minX;
    final gridH = maxY - minY;

    final offsetX = (vpSize.x - gridW) * 0.5 - minX;
    final offsetY = (vpSize.y - gridH) * 0.5 - minY;

    setPosition(Vector2(x: offsetX, y: offsetY));
  }

  // ======================================================================
  // Rendu piloté par le BLoC
  // ======================================================================

  /// Appelé par AppRoot à chaque nouveau state du BLoC.
  void render(IsomapGridState state) {
    _applySelectionHighlight(state.selected);
    _syncIconsWithState(state.tiles);
  }

  void _applySelectionHighlight(GridPos? selected) {
    // reset
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        _tiles[r][c].setColor(fillColor);
        _edges[r][c].setDefaultColor(lineColor);
      }
    }

    if (selected == null) return;

    final r = selected.row;
    final c = selected.col;
    if (r < 0 || r >= rows || c < 0 || c >= cols) return;

    _tiles[r][c].setColor(selectedFill);
    _edges[r][c].setDefaultColor(selectedLine);
  }

  void _syncIconsWithState(Map<GridPos, GridResource> tilesMap) {
    // 1) supprimer les sprites qui ne sont plus dans le state
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final pos = GridPos(r, c);
        final shouldHave = tilesMap.containsKey(pos);
        final existing = _icons[r][c];

        if (!shouldHave && existing != null) {
          existing.queueFree();
          _icons[r][c] = null;
        }
      }
    }

    // 2) ajouter les sprites manquants
    tilesMap.forEach((pos, resource) {
      final r = pos.row;
      final c = pos.col;

      if (r < 0 || r >= rows || c < 0 || c >= cols) return;

      if (_icons[r][c] != null) return;

      _placeIconAt(r, c, resource.texturePath);
    });
  }

  // ======================================================================
  // Placement d'icône (utilisé par le BLoC + fallback public)
  // ======================================================================

  /// Fallback "ancienne API" : place sur la tuile sélectionnée locale.
  void placeIconOnSelected(String path) {
    if (_selR < 0 || _selC < 0) {
      GD.print(Variant(
          '[IsoMapGrid] placeIconOnSelected: aucune tuile sélectionnée'));
      return;
    }
    _placeIconAt(_selR, _selC, path);
  }

  /// Placement d’icône sur une tuile précise (r,c).
  void _placeIconAt(int r, int c, String path) {
    final texRes = ResourceLoader.singleton.load(path);
    if (texRes is! Texture2D) {
      GD.pushWarning(
        Variant(
            '[IsoMapGrid] _placeIconAt: échec load Texture2D -> $path'),
      );
      return;
    }
    final tex = texRes as Texture2D;

    // supprimer l'icône précédente s'il y en a une
    final existing = _icons[r][c];
    if (existing != null) {
      existing.queueFree();
      _icons[r][c] = null;
    }

    final sprite = Sprite2D();
    sprite.setTexture(tex);
    sprite.setCentered(true);

    // --- Mise à l'échelle en fonction de la largeur de la tuile ---
    final texSize = tex.getSize(); // ex: 1024 x 1024

    // on veut que la base du cube recouvre un peu plus que la largeur du losange
    const double baseFactor = 1.25; // 1.1 = pile-poil, 1.25 = recouvre bien
    final double targetW = tileW * baseFactor;

    // échelle uniforme basée UNIQUEMENT sur la largeur
    final double uniformScale = targetW / texSize.x;
    sprite.setScale(Vector2(x: uniformScale, y: uniformScale));

    // --- Position pour "poser" le cube sur le bas du losange ---
    final double spriteHeight = texSize.y * uniformScale;

    // bas du losange (en local) = tileH * 0.5
    final double tileBottomY = tileH * 0.5;

    // bottomSprite = posY + spriteHeight / 2 ≈ tileBottomY
    // => posY = tileBottomY - spriteHeight / 2 + yNudge
    const double yNudge = 7.5; // ajusté à ton feeling
    final double posY = tileBottomY - spriteHeight / 2 + yNudge;

    const double xNudge = 0.0; // pas de décalage en X pour l’instant
    sprite.setPosition(Vector2(x: xNudge, y: posY));

    // --- Z-index : au-dessus des tuiles et des edges ---
    sprite.setZAsRelative(false);
    sprite.setZIndex((r + c) * 2 + 2);

    final area = _tiles[r][c].getParent() as Node2D;
    area.addChild(sprite);
    _icons[r][c] = sprite;

    GD.print(
      Variant('[IsoMapGrid] +sprite ($r,$c) path=$path scale=$uniformScale'),
    );
  }
}