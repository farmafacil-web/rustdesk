import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../common.dart';
import 'model.dart';
import 'platform_model.dart';

class UserModel {
  final RxString userName = ''.obs;
  final RxBool isAdmin = false.obs;
  WeakReference<FFI> parent;

  UserModel(this.parent);

  void refreshCurrentUser() async {
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token == '') {
      await updateOtherModels();
      return;
    }
    _updateLocalUserInfo();
    final url = await bind.mainGetApiServer();
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid()
    };
    try {
      final response = await http.post(Uri.parse('$url/api/currentUser'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token'
          },
          body: json.encode(body));
      final status = response.statusCode;
      if (status == 401 || status == 400) {
        reset();
        return;
      }
      final data = json.decode(utf8.decode(response.bodyBytes));
      final error = data['error'];
      if (error != null) {
        throw error;
      }

      final user = UserPayload.fromJson(data);
      _parseAndUpdateUser(user);
    } catch (e) {
      print('Failed to refreshCurrentUser: $e');
    } finally {
      await updateOtherModels();
    }
  }

  static Map<String, dynamic>? getLocalUserInfo() {
    try {
      return json.decode(bind.mainGetLocalOption(key: 'user_info'));
    } catch (e) {
      print('Failed to get local user info: $e');
    }
    return null;
  }

  _updateLocalUserInfo() {
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      userName.value = userInfo['name'];
    }
  }

  Future<void> reset() async {
    await bind.mainSetLocalOption(key: 'access_token', value: '');
    await gFFI.abModel.reset();
    await gFFI.groupModel.reset();
    userName.value = '';
    gFFI.peerTabModel.check_dynamic_tabs();
  }

  _parseAndUpdateUser(UserPayload user) {
    userName.value = user.name;
    isAdmin.value = user.isAdmin;
  }

  // update ab and group status
  static Future<void> updateOtherModels() async {
    await gFFI.abModel.pullAb();
    await gFFI.groupModel.pull();
  }

  Future<void> logOut() async {
    final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
    try {
      final url = await bind.mainGetApiServer();
      final authHeaders = getHttpHeaders();
      authHeaders['Content-Type'] = "application/json";
      await http
          .post(Uri.parse('$url/api/logout'),
              body: jsonEncode({
                'id': await bind.mainGetMyId(),
                'uuid': await bind.mainGetUuid(),
              }),
              headers: authHeaders)
          .timeout(Duration(seconds: 2));
    } catch (e) {
      print("request /api/logout failed: err=$e");
    } finally {
      await reset();
      gFFI.dialogManager.dismissByTag(tag);
    }
  }

  /// throw [RequestException]
  Future<LoginResponse> login(LoginRequest loginRequest) async {
    final url = await bind.mainGetApiServer();
    final resp = await http.post(Uri.parse('$url/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(loginRequest.toJson()));

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (e) {
      print("login: jsonDecode resp body failed: ${e.toString()}");
      rethrow;
    }
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, body['error'] ?? '');
    }

    return getLoginResponseFromAuthBody(body);
  }

  LoginResponse getLoginResponseFromAuthBody(Map<String, dynamic> body) {
    final LoginResponse loginResponse;
    try {
      loginResponse = LoginResponse.fromJson(body);
    } catch (e) {
      print("login: jsonDecode LoginResponse failed: ${e.toString()}");
      rethrow;
    }

    if (loginResponse.user != null) {
      _parseAndUpdateUser(loginResponse.user!);
    }

    return loginResponse;
  }

  static Future<List<dynamic>> queryLoginOptions() async {
    try {
      final url = await bind.mainGetApiServer();
      final resp = await http.get(Uri.parse('$url/api/login-options'));
      return jsonDecode(resp.body);
    } catch (e) {
      print("queryLoginOptions: jsonDecode resp body failed: ${e.toString()}");
      return [];
    }
  }
}
