import 'package:frun/src/data/datasources/self_vm_inspector.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart' as vm;

void main() {
  group('SelfVmInspector.mapProcessMemoryJson', () {
    test('maps a nested tree', () {
      final node = SelfVmInspector.mapProcessMemoryJson({
        'name': 'process',
        'description': 'whole process',
        'size': 100,
        'children': [
          {
            'name': 'vm',
            'size': 60,
            'children': [
              {'name': 'dart heap', 'size': 40, 'children': <Object?>[]},
            ],
          },
        ],
      });
      expect(node, isNotNull);
      expect(node!.name, 'process');
      expect(node.sizeBytes, 100);
      expect(node.children.single.name, 'vm');
      expect(node.children.single.children.single.name, 'dart heap');
      expect(node.children.single.children.single.sizeBytes, 40);
    });

    test('tolerates missing fields and children', () {
      final node = SelfVmInspector.mapProcessMemoryJson({'size': 5});
      expect(node!.name, '<unnamed>');
      expect(node.description, isNull);
      expect(node.children, isEmpty);
    });

    test('null in, null out', () {
      expect(SelfVmInspector.mapProcessMemoryJson(null), isNull);
    });
  });

  group('SelfVmInspector.mapClassStats', () {
    vm.ClassHeapStats stats(String name, int bytes, int instances) =>
        vm.ClassHeapStats(
          classRef: vm.ClassRef(
            id: 'classes/$name',
            name: name,
            library: vm.LibraryRef(
              id: 'libraries/1',
              name: 'x',
              uri: 'package:frun/x.dart',
            ),
          ),
          bytesCurrent: bytes,
          instancesCurrent: instances,
          accumulatedSize: 0,
          instancesAccumulated: 0,
        );

    test('filters zero-byte rows and sorts descending by bytes', () {
      final mapped = SelfVmInspector.mapClassStats([
        stats('Small', 10, 1),
        stats('Empty', 0, 0),
        stats('Big', 1000, 5),
      ]);
      expect(mapped.map((s) => s.className), ['Big', 'Small']);
      expect(mapped.first.bytes, 1000);
      expect(mapped.first.instances, 5);
      expect(mapped.first.libraryUri, 'package:frun/x.dart');
      expect(mapped.first.key, 'package:frun/x.dart|Big');
    });

    test('null members yields empty list', () {
      expect(SelfVmInspector.mapClassStats(null), isEmpty);
    });
  });
}
