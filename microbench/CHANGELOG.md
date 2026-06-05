# Changelog

## [1.0.0] - 2026-06-05

### Added
- Initial release of microbench skill
- JMH benchmark generation for Spring Boot and Quarkus projects
- Framework auto-detection from pom.xml
- All JMH modes: throughput, average time, sampling, single-shot
- Source code analysis for anti-patterns:
  - Thread.sleep in loops
  - N+1 query detection
  - synchronized method contention
  - Unbounded queries (no pagination)
  - Synchronous Kafka send
  - Missing optimistic locking (race conditions)
  - String concatenation in loops
  - Unbounded in-memory collections
- HTML report with dark/light theme toggle
- Results grouped by method with expandable mode details
- Bottleneck analysis with severity badges (critical/high/medium/low)
- Action plan with before/after code diffs
- Tooltips on all numbers explaining units and modes
- Auto-opens report in default browser
