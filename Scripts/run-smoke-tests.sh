#!/bin/zsh

set -euo pipefail

REDDICT_ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REDDICT_SMOKE_DIR="$REDDICT_ROOT_DIR/build-smoke"

cd "$REDDICT_ROOT_DIR"
mkdir -p "$REDDICT_SMOKE_DIR"

xcrun swiftc \
  Reddict/LearnerPreferences.swift \
  Tests/LanguagePreferencesSmoke.swift \
  -o "$REDDICT_SMOKE_DIR/language-preferences"
"$REDDICT_SMOKE_DIR/language-preferences"

xcrun swiftc \
  Reddict/TextSegmenter.swift \
  Tests/TextSegmenterSmoke.swift \
  -o "$REDDICT_SMOKE_DIR/text-segmenter"
"$REDDICT_SMOKE_DIR/text-segmenter"

xcrun swiftc \
  Reddict/LearnerPreferences.swift \
  Reddict/TextSegmenter.swift \
  Reddict/AnalysisModels.swift \
  Reddict/LLMConfiguration.swift \
  Tests/ConfigurationRoutingSmoke.swift \
  -o "$REDDICT_SMOKE_DIR/configuration-routing"
"$REDDICT_SMOKE_DIR/configuration-routing"

xcrun swiftc \
  Reddict/LearnerPreferences.swift \
  Reddict/TextSegmenter.swift \
  Reddict/AnalysisModels.swift \
  Reddict/LLMConfiguration.swift \
  Reddict/HistoryStore.swift \
  Tests/HistoryStoreSmoke.swift \
  -o "$REDDICT_SMOKE_DIR/history-store"
"$REDDICT_SMOKE_DIR/history-store"

xcrun swiftc \
  Reddict/LearnerPreferences.swift \
  Reddict/TextSegmenter.swift \
  Reddict/AnalysisModels.swift \
  Reddict/LLMConfiguration.swift \
  Reddict/LLMClient.swift \
  Tests/ModelDiscoverySmoke.swift \
  -o "$REDDICT_SMOKE_DIR/model-discovery"
"$REDDICT_SMOKE_DIR/model-discovery"

xcrun swiftc \
  Reddict/LearnerPreferences.swift \
  Reddict/TextSegmenter.swift \
  Reddict/AnalysisModels.swift \
  Reddict/GlobalHotKey.swift \
  Reddict/VoiceInputTranscriber.swift \
  Tests/ShortcutVoiceSmoke.swift \
  -o "$REDDICT_SMOKE_DIR/shortcut-voice"
"$REDDICT_SMOKE_DIR/shortcut-voice"

echo "ALL_SMOKE_TESTS_OK"
