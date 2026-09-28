import 'dart:io';

import 'package:in_app_version_control/src/cli/runner.dart';

Future<void> main(List<String> args) async {
  final exitCode = await runIavc(args, out: stdout, err: stderr);
  if (exitCode != 0) {
    exit(exitCode);
  }
}
