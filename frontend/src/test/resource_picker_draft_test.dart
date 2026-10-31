import 'dart:async';
import 'package:blacksmith_front/domain/models/grid_position.dart';
import 'package:blacksmith_front/domain/models/resource_kind.dart';
import 'package:blacksmith_front/prototypes/isometric_3d/resource_picker_draft.dart';
import 'package:test/test.dart';

void main() {
  const target = GridPos(4, 3);
  test('row choice is a draft and cannot confirm without eligibility',
      () async {
    final draft = ResourcePickerDraft()
      ..open(target)
      ..choose(ResourceKind.computeEngine);
    var calls = 0;
    expect(
        await draft.confirm(
            eligible: false,
            place: (kind, pos) async {
              calls++;
            }),
        isFalse);
    expect(calls, 0);
    expect(draft.chosen, ResourceKind.computeEngine);
    expect(draft.target, target);
  });
  test('missing tile or choice prevents dispatch', () async {
    final draft = ResourcePickerDraft()
      ..open(null)
      ..choose(ResourceKind.computeEngine);
    expect(draft.canConfirm(eligible: true), isFalse);
    draft.open(target);
    expect(draft.canConfirm(eligible: true), isFalse);
  });
  test('double confirmation dispatches once and uses the captured tile',
      () async {
    final done = Completer<void>();
    final draft = ResourcePickerDraft()
      ..open(target)
      ..choose(ResourceKind.cloudVpn);
    var calls = 0;
    Future<void> place(ResourceKind kind, GridPos pos) {
      calls++;
      expect(pos, target);
      expect(kind, ResourceKind.cloudVpn);
      return done.future;
    }

    final first = draft.confirm(eligible: true, place: place);
    expect(draft.pending, isTrue);
    expect(await draft.confirm(eligible: true, place: place), isFalse);
    draft.choose(ResourceKind.computeEngine);
    expect(draft.chosen, ResourceKind.cloudVpn);
    done.complete();
    expect(await first, isTrue);
    expect(calls, 1);
  });
  test('changed selection stays invalid even if the same coordinates return',
      () {
    final draft = ResourcePickerDraft()
      ..open(target)
      ..choose(ResourceKind.computeEngine);
    draft.observe(null);
    draft.observe(target);
    expect(draft.canConfirm(eligible: true), isFalse);
    expect(draft.error, contains('selected tile changed'));
    draft.open(target);
    draft.choose(ResourceKind.computeEngine);
    expect(draft.canConfirm(eligible: true), isTrue);
  });
  test('failure remains visible and allows a retry on the same draft',
      () async {
    final draft = ResourcePickerDraft()
      ..open(target)
      ..choose(ResourceKind.computeEngine);
    expect(
        await draft.confirm(
            eligible: true,
            place: (kind, pos) async {
              throw const ResourcePickerFailure('Existing validation feedback');
            }),
        isFalse);
    expect(draft.active, isTrue);
    expect(draft.pending, isFalse);
    expect(draft.error, 'Existing validation feedback');
    expect(await draft.confirm(eligible: true, place: (kind, pos) async {}),
        isTrue);
  });
  test('late completion cannot close or alter a reopened dialog', () async {
    final done = Completer<void>();
    final draft = ResourcePickerDraft()
      ..open(target)
      ..choose(ResourceKind.computeEngine);
    final pending =
        draft.confirm(eligible: true, place: (kind, pos) => done.future);
    draft.close();
    draft.open(const GridPos(1, 2));
    done.complete();
    expect(await pending, isFalse);
    expect(draft.target, const GridPos(1, 2));
    expect(draft.active, isTrue);
    expect(draft.chosen, isNull);
  });
  test('cancel removes the pending choice without calling placement', () {
    final draft = ResourcePickerDraft()
      ..open(target)
      ..choose(ResourceKind.computeEngine);
    draft.close();
    expect(draft.active, isFalse);
    expect(draft.chosen, isNull);
  });
}
