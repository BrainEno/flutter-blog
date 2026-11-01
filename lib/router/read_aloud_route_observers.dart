import 'package:flutter/material.dart';

// PageRoute excludes transient dropdowns/dialogs: choosing a speed must not
// stop playback. One observer is attached to each independent navigator.
final rootReadAloudRouteObserver = RouteObserver<PageRoute<dynamic>>();
final feedReadAloudRouteObserver = RouteObserver<PageRoute<dynamic>>();
final searchReadAloudRouteObserver = RouteObserver<PageRoute<dynamic>>();
final savedReadAloudRouteObserver = RouteObserver<PageRoute<dynamic>>();
final profileReadAloudRouteObserver = RouteObserver<PageRoute<dynamic>>();

final readAloudBranchObservers = <RouteObserver<PageRoute<dynamic>>>[
  feedReadAloudRouteObserver,
  searchReadAloudRouteObserver,
  savedReadAloudRouteObserver,
  profileReadAloudRouteObserver,
];
