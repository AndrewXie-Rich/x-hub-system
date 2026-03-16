# X-Hub Local Bench Fixture Pack

- version: v1.0
- updatedAt: 2026-03-14
- owner: Hub Runtime / QA
- status: active
- scope: quick bench fixture profiles shared by Hub UI, local runtime, and future require-real captures

## 1) Purpose

This document freezes the shared fixture-pack contract used by Hub quick bench.

The goal is to keep bench results comparable across providers and across machines without
committing large binary assets into the repository.

The fixture pack is intentionally:

- task-aware
- offline-only
- deterministic
- fail-closed on missing or invalid fixture metadata

## 2) Source Of Truth

- Resource pack:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/Resources/BenchFixtures/bench_fixture_pack.v1.json`
- Swift catalog loader:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelQuickBench.swift`
- Runtime materialization / execution:
  - `x-hub/python-runtime/python_service/providers/transformers_provider.py`
  - `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`

The pack schema version is fixed to:

- `xhub.local_bench_fixture_pack.v1`

Any schema mismatch must fail closed.

## 3) Required Fixture Profiles

The v1 pack must provide at least the following fixture IDs:

- `text_short`
- `legacy_text_loop`
- `embed_small_docs`
- `asr_short_clip`
- `vision_single_image`
- `ocr_dense_doc`

These IDs are stable product contract, not incidental test names.

## 4) Task Mapping

### `text_generate`

- `text_short`
  - deterministic short prompt for capability and latency checks
- `legacy_text_loop`
  - MLX-only legacy bench loop
  - reserved for resident legacy MLX runtime compatibility

### `embedding`

- `embed_small_docs`
  - small mixed-purpose text batch
  - used to produce latency, throughput, and fallback verdicts

### `speech_to_text`

- `asr_short_clip`
  - generator-backed silence WAV
  - no binary audio asset is committed

### `vision_understand`

- `vision_single_image`
  - generator-backed PNG header
  - supports preview-only and fallback verdict paths

### `ocr`

- `ocr_dense_doc`
  - generator-backed tall PNG header
  - tuned for preview-style OCR checks

## 5) Generator Rules

Binary fixture blobs are not committed for v1.

The runtime materializes deterministic assets from the JSON pack:

- WAV generator:
  - `silence_wav`
- PNG generator:
  - `png_header`

Materialized files are written under:

- `REL_FLOW_HUB_BASE_DIR/generated_bench_fixtures/`

This keeps the pack reviewable in Git while still exercising local input validators.

## 6) Fail-Closed Rules

The bench path must reject, not silently skip, when any of the following happens:

- fixture pack file missing
- fixture pack JSON invalid
- schema version mismatch
- requested fixture ID missing
- fixture task kind mismatches model task
- generator metadata invalid

The local runtime must return machine-readable reason codes such as:

- `fixture_pack_missing`
- `fixture_pack_invalid`
- `fixture_pack_version_mismatch`
- `fixture_missing`

## 7) Shared Hook For Require-Real

The require-real hook in v1 is an ID-level contract:

- quick bench and require-real artifacts must reuse the same fixture IDs
- future capture bundles must not rename or fork these IDs silently
- any require-real capture that proves a bench path should reference the same `fixture_profile`

This means the pack is already reusable by require-real flows even though v1 still generates
lightweight local assets instead of storing canonical captured media inside the repo.

## 8) Operator Notes

- Bench is a quick capability probe, not a full benchmark suite.
- Non-MLX providers currently run quick bench through one-shot local runtime subprocesses.
- Verdicts such as `Fast`, `Balanced`, `Heavy`, `Preview only`, and `CPU fallback` are intended
  to help model selection, not replace full workload evaluation.
