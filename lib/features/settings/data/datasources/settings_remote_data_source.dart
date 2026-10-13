import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/services/screen_security_service.dart';
import 'package:itaaleem/features/settings/data/models/app_settings_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsRemoteDataSource {
  SettingsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<AppSettingsModel> getAppSettings() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.publicSettings,
      options: skipAuthOptions,
    );
    ScreenSecurityService.updateShieldFlag(response.data, fromProfile: false);
    final data = response.data?['data'];
    final body = data is Map<String, dynamic>
        ? data
        : (response.data ?? const <String, dynamic>{});
    // `rate_app` sits beside `settings` (not inside it) — look at every
    // level it could be on.
    final root = response.data ?? const <String, dynamic>{};
    final rateApp = [
      root['rate_app'],
      body['rate_app'],
      if (body['settings'] is Map) (body['settings'] as Map)['rate_app'],
    ].firstWhere((e) => e is Map, orElse: () => null);
    final settings = body['settings'] is Map<String, dynamic>
        ? {...body, ...body['settings'] as Map<String, dynamic>}
        : body;
    return AppSettingsModel.fromJson(settings, rateApp: rateApp);
  }
}

final settingsRemoteDataSourceProvider = Provider<SettingsRemoteDataSource>((
  ref,
) {
  return SettingsRemoteDataSource(ref.watch(dioClientProvider));
});
