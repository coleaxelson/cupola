import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/write_outcome.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

DioException _dio(DioExceptionType type, {int? status}) {
  final options = RequestOptions(path: '/api');
  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response(requestOptions: options, statusCode: status),
  );
}

void main() {
  group('writeMayHaveLanded', () {
    test('a write that was sent and got nothing readable back may have '
        'landed', () {
      expect(writeMayHaveLanded(_dio(DioExceptionType.receiveTimeout)), isTrue);
      expect(
        writeMayHaveLanded(_dio(DioExceptionType.badResponse, status: 502)),
        isTrue,
      );
      expect(writeMayHaveLanded(const FormatException('cut')), isTrue);
    });

    test('a write that never arrived changed nothing', () {
      expect(
        writeMayHaveLanded(const SocketException('Connection refused')),
        isFalse,
      );
      expect(
        writeMayHaveLanded(_dio(DioExceptionType.badResponse, status: 401)),
        isFalse,
      );
      expect(
        writeMayHaveLanded(const ServiceNotConfigured(ServiceKey.seerr)),
        isFalse,
      );
    });
  });
}
