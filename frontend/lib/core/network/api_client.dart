import 'package:dio/dio.dart';
import '../secure_storage/secure_storage.dart';
import 'api_endpoints.dart';

class ApiClient {
  late final Dio dio;
  final SecureStorage _secureStorage = SecureStorage();
  bool _isRefreshing = false;
  final List<void Function(String)> _refreshQueue = [];

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStorage.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401 && !error.requestOptions.path.contains('/auth/')) {
            // Expired Access Token: Trigger refresh
            final requestOptions = error.requestOptions;
            
            if (_isRefreshing) {
              // Queue other requests while refreshing
              _refreshQueue.add((newToken) {
                requestOptions.headers['Authorization'] = 'Bearer $newToken';
                dio.fetch(requestOptions).then(
                  (res) => handler.resolve(res),
                  onError: (err) => handler.reject(err as DioException),
                );
              });
              return;
            }

            _isRefreshing = true;
            try {
              final refreshToken = await _secureStorage.getRefreshToken();
              if (refreshToken == null) {
                throw DioException(requestOptions: requestOptions);
              }

              // Execute token refresh
              final response = await dio.post(
                ApiEndpoints.refresh,
                data: {'refresh_token': refreshToken},
              );

              final data = response.data as Map<String, dynamic>;
              final tokens = data['tokens'] as Map<String, dynamic>;
              final newAccessToken = tokens['accessToken'] as String;
              final newRefreshToken = tokens['refreshToken'] as String;

              await _secureStorage.saveTokens(
                accessToken: newAccessToken,
                refreshToken: newRefreshToken,
              );

              // Retry original request
              requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
              final retryResponse = await dio.fetch(requestOptions);
              
              // Flush queued requests
              for (final callback in _refreshQueue) {
                callback(newAccessToken);
              }
              _refreshQueue.clear();

              return handler.resolve(retryResponse);
            } catch (e) {
              // Refresh failed, clear session
              await _secureStorage.clearAll();
              // In production we would broadcast a logout event or redirect to login
              return handler.reject(error);
            } finally {
              _isRefreshing = false;
            }
          }
          return handler.next(error);
        },
      ),
    );
  }
}
