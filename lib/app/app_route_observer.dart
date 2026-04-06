import 'package:flutter/material.dart';

/// Shared [RouteObserver] for [RouteAware] widgets (e.g. start-screen BGM pause/resume).
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
