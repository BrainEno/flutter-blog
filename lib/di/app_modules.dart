import 'package:belog/di/auth_module.dart';
import 'package:belog/di/authors_module.dart';
import 'package:belog/di/blog_module.dart';
import 'package:belog/di/categories_module.dart';
import 'package:belog/di/comments_module.dart';
import 'package:belog/di/core_module.dart';
import 'package:belog/di/dependency_context.dart';
import 'package:belog/di/editor_module.dart';
import 'package:belog/di/inbox_module.dart';
import 'package:belog/di/publish_queue_module.dart';
import 'package:belog/di/user_module.dart';
import 'package:get_it/get_it.dart';

/// Every feature module, in the order `initDependencies` registers them.
///
/// The order is kept stable for readable diffs, not for correctness: modules
/// only register factories and lazy singletons, so none of them resolves
/// anything while registering. The one eager registration -
/// `ConnectionChecker`, which owns the shared HTTP client - is made by the
/// composition root *before* these run. A new feature adds one file under
/// `lib/di/` and one line here.
const List<DependencyModule> appModules = [
  registerEditorModule,
  registerAuthModule,
  registerBlogModule,
  registerCommentsModule,
  registerAuthorsModule,
  registerCategoriesModule,
  registerUserModule,
  registerInboxModule,
  registerPublishQueueModule,
  registerCoreModule,
];

/// Registers [modules] (all of [appModules] by default) on [locator].
///
/// Registering the same module twice throws: GetIt refuses a second
/// registration of a type, which is how an accidental double wiring shows up.
void registerAppModules(
  GetIt locator,
  DependencyContext context, {
  List<DependencyModule> modules = appModules,
}) {
  for (final register in modules) {
    register(locator, context);
  }
}
