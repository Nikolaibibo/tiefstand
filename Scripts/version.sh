#!/usr/bin/env bash
#
# version.sh — the single source of truth for Tiefstand's version.
#
# Two build paths produce an app: Scripts/make-app.sh (SwiftPM, what the
# releases ship) and XcodeGen + Xcode (the one path that can register the
# WidgetKit extension). They used to carry their own numbers, and drifted:
# on 2026-08-15 the released build said 0.4.0 while the installed Xcode build
# said 1.0, from a project.yml still pinned at 0.1.1. Both now source this.
export VERSION="0.4.1"
export BUILD_NUMBER="6"
