import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_version_control/src/cli/runner.dart';

void main() {
  test('rule:validate accepts a valid rule file', () async {
    final file = File(
      '${Directory.systemTemp.path}/iavc-rule-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() async {
      if (await file.exists()) {
        await file.delete();
      }
    });

    await file.writeAsString(
      jsonEncode({
        'minVersion': '1.0.0',
        'latestVersion': '1.2.0',
        'maintenance': false,
        'supportedPlatforms': ['android', 'ios'],
      }),
    );

    final out = StringBuffer();
    final err = StringBuffer();
    final exitCode = await runIavc(
      ['rule:validate', file.path],
      out: out,
      err: err,
    );

    expect(exitCode, 0);
    expect(out.toString(), contains('Rule is valid.'));
    expect(err.toString(), isEmpty);
  });

  test('endpoint:test fetches and prints the normalized rule', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'minVersion': '1.0.0',
            'latestVersion': '1.2.0',
            'maintenance': false,
          }),
        );
      await request.response.close();
    });

    final out = StringBuffer();
    final err = StringBuffer();
    final exitCode = await runIavc(
      [
        'endpoint:test',
        'http://${server.address.host}:${server.port}/rule',
        '--platform',
        'android',
      ],
      out: out,
      err: err,
    );

    expect(exitCode, 0);
    expect(out.toString(), contains('Endpoint rule fetch succeeded.'));
    expect(out.toString(), contains('"latestVersion": "1.2.0"'));
    expect(err.toString(), isEmpty);
  });

  test(
    'app:firebase configure checks firebase state and writes config files',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('iavc-firebase');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final out = StringBuffer();
      final err = StringBuffer();
      final runner = _FakeProcessRunner([
        _ProcessCall(
          executable: 'firebase',
          args: const ['--version'],
          result: const IavcCommandResult(
            exitCode: 0,
            stdout: '14.22.0',
            stderr: '',
          ),
        ),
        _ProcessCall(
          executable: 'firebase',
          args: const ['--json', 'projects:list'],
          result: IavcCommandResult(
            exitCode: 0,
            stdout: jsonEncode({
              'status': 'success',
              'result': [
                {'projectId': 'demo-project', 'displayName': 'Demo Project'},
              ],
            }),
            stderr: '',
          ),
        ),
        _ProcessCall(
          executable: 'firebase',
          args: const ['--json', 'apps:list', '--project', 'demo-project'],
          result: IavcCommandResult(
            exitCode: 0,
            stdout: jsonEncode({'status': 'success', 'result': []}),
            stderr: '',
          ),
        ),
        _ProcessCall(
          executable: 'firebase',
          args: const [
            'apps:create',
            'ANDROID',
            'Android App',
            '--package-name',
            'com.example.app',
            '--project',
            'demo-project',
          ],
          result: const IavcCommandResult(exitCode: 0, stdout: '', stderr: ''),
        ),
        _ProcessCall(
          executable: 'firebase',
          args: const ['--json', 'apps:list', '--project', 'demo-project'],
          result: IavcCommandResult(
            exitCode: 0,
            stdout: jsonEncode({
              'status': 'success',
              'result': [
                {
                  'appId': '1:123:android:abc',
                  'platform': 'ANDROID',
                  'displayName': 'Android App',
                },
              ],
            }),
            stderr: '',
          ),
        ),
      ]);

      final exitCode = await runIavc(
        [
          'app:firebase',
          'configure',
          '--project',
          'demo-project',
          '--android-package',
          'com.example.app',
          '--write-alias',
          'default',
          '--out-dir',
          tempDir.path,
        ],
        out: out,
        err: err,
        processRunner: runner,
        workingDirectory: tempDir.path,
      );

      expect(exitCode, 0);
      expect(
        out.toString(),
        contains('Firebase Remote Config setup completed.'),
      );
      expect(out.toString(), contains('version_rule_android'));
      expect(out.toString(), contains('demo-project'));
      expect(err.toString(), isEmpty);
      expect(
        File('${tempDir.path}/remoteconfig.template.json').existsSync(),
        isTrue,
      );
      expect(File('${tempDir.path}/firebase.json').existsSync(), isTrue);
      expect(File('${tempDir.path}/.firebaserc').existsSync(), isTrue);
      expect(runner.calls.length, 5);
    },
  );

  test('app:firebase configure can deploy remote config', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'iavc-firebase-deploy',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final out = StringBuffer();
    final err = StringBuffer();
    final runner = _FakeProcessRunner([
      _ProcessCall(
        executable: 'firebase',
        args: const ['--version'],
        result: const IavcCommandResult(
          exitCode: 0,
          stdout: '14.22.0',
          stderr: '',
        ),
      ),
      _ProcessCall(
        executable: 'firebase',
        args: const ['--json', 'projects:list'],
        result: IavcCommandResult(
          exitCode: 0,
          stdout: jsonEncode({
            'status': 'success',
            'result': [
              {'projectId': 'demo-project', 'displayName': 'Demo Project'},
            ],
          }),
          stderr: '',
        ),
      ),
      _ProcessCall(
        executable: 'firebase',
        args: const ['--json', 'apps:list', '--project', 'demo-project'],
        result: IavcCommandResult(
          exitCode: 0,
          stdout: jsonEncode({
            'status': 'success',
            'result': [
              {
                'appId': '1:123:web:abc',
                'platform': 'WEB',
                'displayName': 'Web App',
              },
            ],
          }),
          stderr: '',
        ),
      ),
      _ProcessCall(
        executable: 'firebase',
        args: const ['--json', 'apps:list', '--project', 'demo-project'],
        result: IavcCommandResult(
          exitCode: 0,
          stdout: jsonEncode({
            'status': 'success',
            'result': [
              {
                'appId': '1:123:web:abc',
                'platform': 'WEB',
                'displayName': 'Web App',
              },
            ],
          }),
          stderr: '',
        ),
      ),
      _ProcessCall(
        executable: 'firebase',
        args: const [
          'deploy',
          '--only',
          'remoteconfig',
          '--project',
          'demo-project',
        ],
        result: const IavcCommandResult(
          exitCode: 0,
          stdout: 'Deployed',
          stderr: '',
        ),
      ),
    ]);

    final exitCode = await runIavc(
      [
        'app:firebase',
        'configure',
        '--project',
        'demo-project',
        '--out-dir',
        tempDir.path,
        '--deploy-remoteconfig',
        'true',
      ],
      out: out,
      err: err,
      processRunner: runner,
      workingDirectory: tempDir.path,
    );

    expect(exitCode, 0);
    expect(out.toString(), contains('Remote Config deployed to Firebase'));
    expect(err.toString(), isEmpty);
    expect(runner.calls.length, 5);
  });

  test('help prints available commands', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final exitCode = await runIavc([], out: out, err: err);

    expect(exitCode, 0);
    expect(out.toString(), contains('iavc commands:'));
    expect(out.toString(), contains('rule:validate'));
    expect(err.toString(), isEmpty);
  });
}

class _FakeProcessRunner implements IavcProcessRunner {
  final List<_ProcessCall> _calls;
  int _index = 0;

  _FakeProcessRunner(this._calls);

  List<_ProcessCall> get calls => _calls.take(_index).toList();

  @override
  Future<IavcCommandResult> run(
    String executable,
    List<String> args, {
    required String workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (_index >= _calls.length) {
      throw StateError(
        'Unexpected process call: $executable ${args.join(' ')}',
      );
    }

    final call = _calls[_index++];
    expect(executable, call.executable);
    expect(args, call.args);
    return call.result;
  }
}

class _ProcessCall {
  final String executable;
  final List<String> args;
  final IavcCommandResult result;

  const _ProcessCall({
    required this.executable,
    required this.args,
    required this.result,
  });
}
