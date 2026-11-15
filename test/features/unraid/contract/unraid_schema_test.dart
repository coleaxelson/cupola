import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';

import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';

/// Tier-3 contract test (plan §7.4). Unraid has no formal OpenAPI spec, so its
/// GraphQL schema is the contract, and two untouched captures of the upstream
/// `api/generated-schema.graphql` stand for it:
///
/// - `schema_v4.25.3.graphql`: the API Unraid 7.2.0 ships, the oldest we
///   support (the floor).
/// - `schema_v4.37.11.graphql`: the API Unraid 7.3.5 ships, the newest we know.
///
/// Every document the [UnraidClient] sends must validate against **both**:
/// each selected field resolved on its parent type from the root operation
/// down, each argument on its field, each variable's type in the schema. A
/// GraphQL server rejects the whole document over one unknown field, which is
/// how `dockerContainers` (gone from the schema before 4.9.0) took the Docker
/// tab and the rail's figures down on every Unraid from 7.2 on, past a suite
/// that only checked identifiers against a hand-written SDL.
///
/// Refresh: capture a new tag's file with the same one-line source header,
/// add it to [_schemaFiles], and fix what fails.
const _schemaFiles = {
  'Unraid 7.2.0 (API 4.25.3)': 'test/fixtures/unraid/schema_v4.25.3.graphql',
  'Unraid 7.3.5 (API 4.37.11)': 'test/fixtures/unraid/schema_v4.37.11.graphql',
};

void main() {
  for (final MapEntry(key: label, value: path) in _schemaFiles.entries) {
    group('Unraid GraphQL schema contract, $label', () {
      final source = File(path).readAsStringSync();
      final schema = _Schema.parse(source);

      test('the capture is the upstream file, with its source line', () {
        final first = source.split('\n').first;
        expect(
          first,
          startsWith('# Source: https://raw.githubusercontent.com'),
        );
      });

      test('the capability probe reads what the schema declares', () {
        // `me { roles permissions { resource actions } }`: the probe grants a
        // write only on the three `_ANY` write actions and the ADMIN role.
        expect(schema.enumValues('Role'), contains('ADMIN'));
        expect(
          schema.enumValues('AuthAction'),
          containsAll(UnraidCapabilities.writeActions),
        );
        expect(
          schema.enumValues('Resource'),
          containsAll(['VMS', 'NOTIFICATIONS', 'SHARE']),
        );
        expect(schema.fieldType('UserAccount', 'roles'), 'Role');
        expect(schema.fieldType('Permission', 'resource'), 'Resource');
        expect(schema.fieldType('Permission', 'actions'), 'AuthAction');
      });

      test('every document the client sends validates against the schema', () {
        expect(UnraidClient.graphQlDocuments, isNotEmpty);
        UnraidClient.graphQlDocuments.forEach((call, document) {
          expect(
            schema.validate(document),
            isEmpty,
            reason:
                '$call does not validate against $label. One unknown field '
                'fails the entire document.',
          );
        });
      });

      test('the variables the client builds fit the schema', () {
        // `getNotifications` sends `{'filter': {'type': …, 'offset': …,
        // 'limit': …}}` as a `NotificationFilter!`.
        final fields = schema.inputFields('NotificationFilter');
        expect(fields, containsAll(['type', 'offset', 'limit']));
        expect(
          schema.enumValues(
            schema.inputFieldType('NotificationFilter', 'type'),
          ),
          containsAll(UnraidNotificationType.values.map((t) => t.graphQl)),
        );
      });

      test('the walker rejects a required argument left out', () {
        final problems = schema.validate(
          'query { notifications { list { id } } }',
        );
        expect(problems, hasLength(1));
        expect(problems.single, contains('filter'));
        expect(problems.single, contains('required'));
        expect(
          schema.validate(
            r'query Q($f: NotificationFilter!) { '
            r'notifications { list(filter: $f) { id } } }',
          ),
          isEmpty,
        );
      });

      test('the walker rejects the root the client used to ask for', () {
        final problems = schema.validate('query { dockerContainers { id } }');
        expect(problems, hasLength(1));
        expect(problems.single, contains('dockerContainers'));
        expect(problems.single, contains('Query'));
      });

      test('the walker rejects an unknown nested field', () {
        final problems = schema.validate(
          'query { docker { containers { id noSuchField } } }',
        );
        expect(problems, hasLength(1));
        expect(problems.single, contains('noSuchField'));
        expect(problems.single, contains('DockerContainer'));
      });

      test('the walker rejects a leaf with a selection, an object without', () {
        expect(
          schema.validate('query { docker { containers { id { x } } } }'),
          isNotEmpty,
        );
        expect(schema.validate('query { docker { containers } }'), isNotEmpty);
      });

      test('the walker rejects an unknown argument and variable type', () {
        expect(
          schema.validate('query { docker { containers(nope: 1) { id } } }'),
          isNotEmpty,
        );
        expect(
          schema.validate(
            r'query Q($x: NoSuchType!) { docker { containers { id } } }',
          ),
          isNotEmpty,
        );
      });

      test('the walker refuses fragments, which the client never uses', () {
        expect(
          () => schema.validate(
            'query { docker { containers { ...F } } } '
            'fragment F on DockerContainer { id }',
          ),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });
  }
}

/// A schema parsed from SDL, with a walker that validates a document against
/// it: the part of GraphQL's validation that matters to a client that only
/// asks for fields (fields on their types, leaves and objects, arguments,
/// variable types). Fragments are refused, not skipped: a silent skip is a
/// hole in the check.
class _Schema {
  _Schema._(this._types, this._roots);

  factory _Schema.parse(String sdl) {
    final types = <String, TypeDefinitionNode>{};
    final roots = <OperationType, String>{};
    for (final definition in parseString(sdl).definitions) {
      if (definition is TypeDefinitionNode) {
        types[definition.name.value] = definition;
      } else if (definition is SchemaDefinitionNode) {
        for (final op in definition.operationTypes) {
          roots[op.operation] = op.type.name.value;
        }
      } else if (definition is DirectiveDefinitionNode) {
        // Declared, never used by a client document: nothing to check.
        continue;
      } else {
        throw UnsupportedError(
          'Unhandled schema definition ${definition.runtimeType}',
        );
      }
    }
    // No `schema { … }` block: the conventional names.
    roots.putIfAbsent(OperationType.query, () => 'Query');
    roots.putIfAbsent(OperationType.mutation, () => 'Mutation');
    roots.putIfAbsent(OperationType.subscription, () => 'Subscription');
    return _Schema._(types, roots);
  }

  final Map<String, TypeDefinitionNode> _types;
  final Map<OperationType, String> _roots;

  Set<String> enumValues(String name) {
    final type = _types[name];
    if (type is! EnumTypeDefinitionNode) {
      throw StateError('"$name" is not an enum in this schema');
    }
    return type.values.map((v) => v.name.value).toSet();
  }

  /// The field names of the input object [name].
  Set<String> inputFields(String name) {
    final type = _types[name];
    if (type is! InputObjectTypeDefinitionNode) {
      throw StateError('"$name" is not an input object in this schema');
    }
    return type.fields.map((f) => f.name.value).toSet();
  }

  /// The named type of the input field `input.field`, wrappers removed.
  String inputFieldType(String input, String field) {
    final type = _types[input];
    if (type is! InputObjectTypeDefinitionNode) {
      throw StateError('"$input" is not an input object in this schema');
    }
    return _named(type.fields.firstWhere((f) => f.name.value == field).type);
  }

  /// The named type of `type.field`, wrappers removed.
  String fieldType(String type, String field) {
    final found = _fieldsOf(type)?.where((f) => f.name.value == field);
    if (found == null || found.isEmpty) {
      throw StateError('"$type.$field" is not in this schema');
    }
    return _named(found.first.type);
  }

  List<FieldDefinitionNode>? _fieldsOf(String type) => switch (_types[type]) {
    ObjectTypeDefinitionNode(:final fields) => fields,
    InterfaceTypeDefinitionNode(:final fields) => fields,
    _ => null,
  };

  static String _named(TypeNode type) => switch (type) {
    NamedTypeNode(:final name) => name.value,
    ListTypeNode(:final type) => _named(type),
    _ => throw StateError('Unknown type node ${type.runtimeType}'),
  };

  /// What is wrong with [document] against this schema; empty when nothing.
  List<String> validate(String document) {
    final problems = <String>[];
    final parsed = parseString(document);
    for (final definition in parsed.definitions) {
      if (definition is! OperationDefinitionNode) {
        throw UnsupportedError(
          'Only operations are supported, found ${definition.runtimeType}',
        );
      }
      for (final variable in definition.variableDefinitions) {
        final name = _named(variable.type);
        if (!_types.containsKey(name) && !_builtInScalars.contains(name)) {
          problems.add(
            'Variable \$${variable.variable.name.value}: '
            'unknown type "$name"',
          );
        }
      }
      final root = _roots[definition.type]!;
      if (!_types.containsKey(root)) {
        problems.add('The schema has no $root type');
        continue;
      }
      _walk(root, definition.selectionSet, problems, root);
    }
    return problems;
  }

  static const _builtInScalars = {'String', 'Int', 'Float', 'Boolean', 'ID'};

  void _walk(
    String parent,
    SelectionSetNode selectionSet,
    List<String> problems,
    String path,
  ) {
    final fields = _fieldsOf(parent);
    for (final selection in selectionSet.selections) {
      if (selection is! FieldNode) {
        throw UnsupportedError(
          'Fragments are not supported by this walker '
          '(${selection.runtimeType} under $path)',
        );
      }
      final name = selection.name.value;
      if (name == '__typename') continue;
      final matches = fields?.where((f) => f.name.value == name);
      if (matches == null || matches.isEmpty) {
        problems.add('Cannot query field "$name" on type "$parent"');
        continue;
      }
      final field = matches.first;
      for (final argument in selection.arguments) {
        if (!field.args.any((a) => a.name.value == argument.name.value)) {
          problems.add(
            'Unknown argument "${argument.name.value}" on "$parent.$name"',
          );
        }
      }
      // A non-null argument with no default must be there, or the server
      // rejects the document.
      for (final arg in field.args) {
        final required = arg.type.isNonNull && arg.defaultValue == null;
        if (required &&
            !selection.arguments.any((a) => a.name.value == arg.name.value)) {
          problems.add(
            'Missing required argument "${arg.name.value}" on "$parent.$name"',
          );
        }
      }
      final type = _named(field.type);
      final definition = _types[type];
      final isLeaf =
          definition is ScalarTypeDefinitionNode ||
          definition is EnumTypeDefinitionNode ||
          (definition == null && _builtInScalars.contains(type));
      final sub = selection.selectionSet;
      if (isLeaf) {
        if (sub != null) {
          problems.add('Field "$parent.$name" is a leaf ($type): no selection');
        }
      } else if (definition is ObjectTypeDefinitionNode ||
          definition is InterfaceTypeDefinitionNode) {
        if (sub == null) {
          problems.add('Field "$parent.$name" ($type) needs a selection');
        } else {
          _walk(type, sub, problems, '$path.$name');
        }
      } else {
        throw UnsupportedError(
          '"$parent.$name" is a ${definition.runtimeType}: needs fragments',
        );
      }
    }
  }
}
