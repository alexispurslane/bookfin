// Runs one plan on the Mac with the same sherpa_onnx package, to test plans
// and model files before the phone run: dart run bin/mac_check.dart PLAN OUT
import 'dart:convert';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
import 'package:ttsbench/bench.dart';

void main(List<String> args) {
  so.initBindings();
  final plan = Plan.fromJson(
    jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>,
  );
  runPlan(plan, File(args[1]), print);
}
