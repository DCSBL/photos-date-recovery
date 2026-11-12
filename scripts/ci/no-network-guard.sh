#!/usr/bin/env bash
# Phtofxr never touches the internet (PLAN.md §6). Fails when app or core code reaches for networking APIs,
# web URLs, or any package from outside the repository.
set -euo pipefail
cd "$(dirname "$0")/../.."

status=0
pattern='URLSession|URLRequest|import Network\b|NWConnection|NWPathMonitor|import WebKit|WKWebView|import SafariServices|SFSafariViewController|ASWebAuthenticationSession|CFNetwork|https?://'
if hits="$(grep -rnE "$pattern" --include='*.swift' App PhtofxrCore/Sources)"; then
  echo "::error::Networking code or web URLs found in app or core sources:"
  echo "$hits"
  status=1
fi

if grep -q "XCRemoteSwiftPackageReference" Phtofxr.xcodeproj/project.pbxproj; then
  echo "::error::Phtofxr.xcodeproj references a remote Swift package. Phtofxr has no external dependencies."
  status=1
fi

if grep -qE '\.package\(' PhtofxrCore/Package.swift; then
  echo "::error::PhtofxrCore/Package.swift declares a package dependency. Phtofxr has no external dependencies."
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "No networking code, web URLs or external packages found."
fi
exit "$status"
