import 'package:quartiers_mobile/account.dart';

class MemoryAccountTokenStore implements AccountTokenStore {
  final tokens = <String, String>{};
  @override
  Future<String?> read(String server) async => tokens[server];
  @override
  Future<void> write(String server, String token) async =>
      tokens[server] = token;
  @override
  Future<void> delete(String server) async => tokens.remove(server);
}

class SignedInTestAccount extends GoogleAccountController {
  SignedInTestAccount({this.unlockAll = false})
      : super(store: MemoryAccountTokenStore());
  final bool unlockAll;
  @override
  Future<void> restore(String address) async {
    server = address;
    account = {
      'id': 'test-account',
      'name': 'Joueur test',
      'picture': '',
      if (unlockAll)
        'soloProgress': {
          'completedLevels': ['beginner', 'easy', 'normal', 'hard', 'expert'],
          'unlockedLevels': [
            'beginner',
            'easy',
            'normal',
            'hard',
            'expert',
            'ultimate'
          ],
          'highestUnlocked': 'ultimate',
          'allCompleted': false
        }
    };
    token = 'test-account-bearer';
    notifyListeners();
  }
}
