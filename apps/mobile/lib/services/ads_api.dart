import 'api_client.dart';

class AdsApi {
  final ApiClient _api;
  AdsApi(this._api);

  /// Submit an advertisement inquiry.
  Future<Map<String, dynamic>> submitInquiry({
    required String name,
    String? email,
    String? phone,
    required String product,
    String? message,
  }) async {
    return await _api.post('/ads', {
      'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'product': product,
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }
}
