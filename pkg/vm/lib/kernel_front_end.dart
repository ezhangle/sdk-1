// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Defines the VM-specific translation of Dart source code to kernel binaries.
library vm.kernel_front_end;

import 'dart:async';

import 'package:front_end/src/api_prototype/compiler_options.dart'
    show CompilerOptions, ErrorHandler;
import 'package:front_end/src/api_prototype/kernel_generator.dart'
    show kernelForProgram;
import 'package:front_end/src/api_prototype/compilation_message.dart'
    show CompilationMessage, Severity;
import 'package:front_end/src/fasta/severity.dart' show Severity;
import 'package:kernel/ast.dart' show Component;
import 'package:kernel/core_types.dart' show CoreTypes;

import 'transformations/devirtualization.dart' as devirtualization
    show transformComponent;
import 'transformations/no_dynamic_invocations_annotator.dart'
    as no_dynamic_invocations_annotator show transformComponent;
import 'transformations/type_flow/transformer.dart' as globalTypeFlow
    show transformComponent;

/// Generates a kernel representation of the program whose main library is in
/// the given [source]. Intended for whole program (non-modular) compilation.
///
/// VM-specific replacement of [kernelForProgram].
///
Future<Component> compileToKernel(Uri source, CompilerOptions options,
    {bool aot: false,
    bool useGlobalTypeFlowAnalysis: false,
    List<String> entryPoints}) async {
  // Replace error handler to detect if there are compilation errors.
  final errorDetector =
      new ErrorDetector(previousErrorHandler: options.onError);
  options.onError = errorDetector;

  final component = await kernelForProgram(source, options);

  // Restore error handler (in case 'options' are reused).
  options.onError = errorDetector.previousErrorHandler;

  // Run global transformations only if component is correct.
  if (aot && (component != null) && !errorDetector.hasCompilationErrors) {
    _runGlobalTransformations(
        component, options.strongMode, useGlobalTypeFlowAnalysis, entryPoints);
  }

  return component;
}

_runGlobalTransformations(Component component, bool strongMode,
    bool useGlobalTypeFlowAnalysis, List<String> entryPoints) {
  if (strongMode) {
    final coreTypes = new CoreTypes(component);

    if (useGlobalTypeFlowAnalysis) {
      globalTypeFlow.transformComponent(coreTypes, component, entryPoints);
    } else {
      devirtualization.transformComponent(coreTypes, component);
    }

    no_dynamic_invocations_annotator.transformComponent(component);
  }
}

class ErrorDetector {
  final ErrorHandler previousErrorHandler;
  bool hasCompilationErrors = false;

  ErrorDetector({this.previousErrorHandler});

  void call(CompilationMessage message) {
    if (message.severity == Severity.error) {
      hasCompilationErrors = true;
    }

    previousErrorHandler?.call(message);
  }
}
