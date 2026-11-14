## [Unreleased]

- Fix: `perform_async`, `perform_in` and `perform_at` of a raw worker with several queues (an Array, or a lambda that
  returns several) raise an `ArgumentError` that names the worker and its queues and asks for `queue:` when called
  without `queue:`
  - It raised `NoMethodError: undefined method 'start_with?' for an instance of Array`
  - A one-element Array sends to its queue; it raised the same `NoMethodError`
  - An empty Array raises an `ArgumentError` that asks for `queue:`; it raised a `NoMethodError`

- Fix: ActiveJob `perform_all_later` delays a job set with `wait` or `wait_until` and splits each batch at 1 MiB in
  total, not only at 10 messages
  - A delay was ignored: every job became visible at once
  - A batch over 1 MiB raised `Aws::SQS::Errors::BatchRequestTooLong` (ElasticMQ: `InvalidAttributeValue`): the
    batches before it were sent, that batch and the later jobs were not
  - Delays follow `enqueue_at`: a time in the past is sent with a delay of 0, a delay over 15 minutes raises
    `Shoryuken::Errors::InvalidDelayError` and a delay on a FIFO queue raises
    `Shoryuken::Errors::FifoDelayNotSupportedError`, both before any job is sent

- Change: A raw worker `perform_at`/`perform_in` sends a time in the past or a negative interval with a delay of 0
  and raises `Shoryuken::Errors::FifoDelayNotSupportedError` for a delay on a FIFO queue, as the ActiveJob adapter does
  - Both cases raised `Aws::SQS::Errors::InvalidParameterValue` from SQS
  - The FIFO check runs before the send; code that rescues `Aws::SQS::Errors::InvalidParameterValue` for it must
    rescue `Shoryuken::Errors::FifoDelayNotSupportedError` instead
  - An interval of 0 on a FIFO queue is still sent

- Fix: An ActiveJob `retry_on` retry or an `ActiveJob::Continuable` resume keeps the `message_group_id` and the custom
  `message_attributes` given with `.set`
  - The retry or resume was sent without the custom attributes, and on a FIFO queue in the default `ShoryukenMessage`
    group, so per-group ordering was lost
  - The `message_deduplication_id` is not kept: a FIFO retry still gets a new one

- Enhancement: Require `concurrent-ruby` `>= 1.3.7`, which fixes GHSA-h8w8-99g7-qmvj (CVE-2026-54904),
  GHSA-wv3x-4vxv-whpp (CVE-2026-54905) and GHSA-6wx8-w4f5-wwcr (CVE-2026-54906)
  - Hardening only: Shoryuken does not use the affected `AtomicReference`, `ReadWriteLock` and
    `ReentrantReadWriteLock`

- Breaking: Remove support for Rails 7.2
  - Rails 7.2 reached end-of-life (August 2026) and gets no fix for GHSA-8474-xrp6-wh69 (Active Support
    `safe_constantize` DoS)
  - Supported Rails versions: 8.0 and 8.1
  - Users on Rails 7.2 should upgrade or remain on Shoryuken 7.0.x

- Fix: `shoryuken sqs` prints `[FAIL] The specified queue <name> does not exist` when SQS reports a missing queue as
  `QueueDoesNotExist`, as ElasticMQ does
  - `purge`, `delete`, `dump`, `requeue` and `mv` printed a backtrace

- Fix: `active_job_queue_name_prefixing` no longer puts ActiveJob's `queue_name_prefix` in front of queues configured
  as a URL of any scheme, such as the `http://` URLs ElasticMQ and LocalStack return, or an upper-case `HTTPS://`
  - Only lower-case `https://` URLs and ARNs were skipped, so the prefixed URL pointed to no queue

- Fix: `shoryuken sqs mv` looks up the target queue before it receives from the source
  - With a missing target, all source messages stayed in flight for the source's visibility timeout

- Fix: Shoryuken loads when `lib/shoryuken.rb` is a symlink to a file elsewhere, as in a Bazel sandbox, which links
  each file of a gem
  - `loader.ignore("#{__dir__}/active_job")` named the resolved directory, outside the root `Zeitwerk::Loader.for_gem`
    takes from the path Shoryuken was loaded by, so the loader managed `lib/active_job`. Loading raised
    `Zeitwerk::NameError` for `ActiveJob::Extensions`, or a `NameError` when Active Job wasn't loaded

- Fix: `ShoryukenConcurrentSendAdapter` keeps the CurrentAttributes registered with
  `Shoryuken::ActiveJob::CurrentAttributes.persist`
  - The message was built on the executor thread, so every job was sent without them

- Fix: A job that leaves a Fiber scheduler set (`Fiber.set_scheduler`) no longer breaks later jobs on its thread
  - Shoryuken sets the scheduler of the thread back to the one before the job and logs a warning
  - A later job using Async's `Sync` with a blocking call waited forever on the scheduler left behind

- Fix: A batch worker with `retry_intervals` or `auto_visibility_timeout` logs the "isn't supported for batch workers"
  warning once per worker class, not on every batch
  - The warning names the worker class; both options stay skipped for batches

- Fix: `Shoryuken::Worker::InlineExecutor` runs a worker that never calls `shoryuken_options`
  - It raised `NoMethodError`; the worker now uses `Shoryuken.default_worker_options`, so `batch` set only there
    gives the batch call shape

- Fix: A batch worker registered again for its queue no longer raises `Shoryuken::Errors::InvalidWorkerRegistrationError`
  (#623)
  - Covers a worker file loaded twice and a Rails code reload that defines the worker class again
  - A worker with a different class name on a queue with a batch worker still raises

- Breaking: `shoryuken sqs` exits with status 1 when `-e`/`--endpoint` comes before the command
  - `sqs -e URL ls` printed the help of `ls` and exited with status 0 without running it; it now fails with
    "Options must follow the command" and shows the command with the options after it (`sqs ls -e URL`)
  - `sqs -e URL` with no command still prints the command list and exits with status 0

- Enhancement: `launcher_executor` accepts any object that responds to `post`, `running?`, `shutdown`,
  `wait_for_termination` and `kill`, not only a concurrent-ruby executor
  - `post` must run the block on another thread and return without waiting for it
  - A plain executor used to process no message: each one failed with `executor not recognized`

- Breaking: `shoryuken start` exits with status 1 when a fatal dispatch error stops it
  - When SQS still failed after the fetch retries, the process soft-shut down and exited with status 0, so a
    supervisor (systemd `Restart=on-failure`, Kubernetes, ...) took the crash for a clean stop and did not restart it
  - A USR1 sent by an operator and a TERM or INT shutdown still exit with status 0

- Removed: `shoryuken` no longer requires `optparse`; nothing in Shoryuken used `OptionParser`
  - Code loaded with `-r` that uses `OptionParser` must `require 'optparse'` itself

- Breaking: An unsupported worker `body_parser` raises `Shoryuken::Errors::InvalidConfigurationError` when the worker
  class loads
  - A value other than `:json`, `:text`, `nil`, a Proc or an object responding to `parse` or `load` (e.g. `:JSON`,
    `'json'`, `JSON.method(:parse)`) was accepted and every message got a `nil` body; with `auto_delete` the message
    was then deleted. A worker with such a value now fails at boot. A value from `default_worker_options` is checked too

- Feature: `shoryuken check` validates the configuration without starting to process
  - Takes the same options as `start` (`-C`, `-r`, `-q`, `-R`, ...), loads the config and the workers and validates
    the queues and workers, then exits 0 with `Configuration OK`
  - Exits 1 with the problem and no backtrace on a missing or malformed config file, an invalid option value, `-d`
    without `-L`, a missing `-r` path or queue, missing AWS credentials or region, no queues configured, or a queue
    without a worker (the last two are only warnings on `start`)

- Fix: A missing queue reported by SQS as `QueueDoesNotExist` (the error the current SQS JSON protocol raises) now
  gets the same "queue(s) do not exist" error on startup as `NonExistentQueue`, instead of the raw SQS error

- Breaking: `shoryuken` exits with status 1 on an unknown command, an unknown option or an extra argument
  - Thor printed the error and exited with status 0, for `start`, `version` and the `sqs` subcommands, so scripts and
    process managers took a command that did nothing for a success
  - An unknown option now fails with `Unknown switches`; `sqs ls --bogus` took it as the queue name prefix
  - An argument after `--` that starts with `-` fails with `Unknown switches` too, so `sqs purge -- -queue` no
    longer reaches a queue whose name starts with `-`

- Feature: `Shoryuken::Message#last_receive?` tells whether a message is on its last receive before the dead-letter queue
  - It compares the message's `ApproximateReceiveCount` with the queue's `RedrivePolicy` `maxReceiveCount`, read
    once per queue (`Shoryuken::Queue#max_receive_count`) and cached; it returns false when the queue has no redrive
    policy. On a FIFO queue a worker can use it to alert or stop the group before the next message of the group runs

- Enhancement: The gem ships only the files it needs at runtime
  - `lib/`, `bin/shoryuken`, `bin/cli/`, `config/locales/`, `README.md`, `CHANGELOG.md` and `LICENSE`; specs, dev
    scripts and repo config are no longer packaged (247 files, 840 KB unpacked, down to 65 files, 317 KB)

- Fix: A message body that the body parser turns into `nil` or `false` is parsed once per message
  - The falsy result was not cached, so the parser ran three times per message (log context, server middleware and
    `perform`); a parser with side effects (metrics, decryption, a payload fetch) repeated them

- Fix: TERM, INT or USR1 after a completed TSTP stop no longer fires the lifecycle events again
  - The second signal ran the whole shutdown sequence again, so `shutdown` and `stopped` handlers (and the
    `stop_callback`) ran twice
  - `Launcher#stop` and `Launcher#stop!` now do nothing once a stop has completed; the process still exits

- Fix: Enqueueing the same ActiveJob job instance again sends its current arguments
  - The second `enqueue` (or `perform_all_later`) resent the previous send's body, delay and generated FIFO
    deduplication id, so the job ran with its old arguments, or a FIFO queue dropped it as a duplicate. Other
    `sqs_send_message_parameters` (e.g. `set(message_group_id:)`, also when changed after the send) still apply

- Fix: ActiveJob `set(wait_until:)` with a time in the past now sends the job at once
  - The adapter sent a negative `DelaySeconds`, which SQS rejects (`Aws::SQS::Errors::InvalidParameterValue`, on FIFO
    queues too); it now sends `delay_seconds: 0`

- Breaking: ActiveJob `set(wait:)`/`set(wait_until:)` over 15 minutes raises `Shoryuken::Errors::InvalidDelayError`
  - It raised a bare `RuntimeError` with the same message; it now raises the error `perform_in` on a worker raises
  - `rescue RuntimeError` no longer catches it; rescue `Shoryuken::Errors::InvalidDelayError` or
    `Shoryuken::Errors::BaseError`

- Fix: ActiveJob `executions` keeps ActiveJob's count across `retry_on` retries
  - Shoryuken replaced the serialized `executions` with the SQS receive count minus one, so it read 1 on every
    `retry_on` retry (also in ActiveJob's "Retrying ... after N attempts" logs and retry events); it now adds the
    past receives to the serialized value
  - Behaviour change: `executions` is higher for jobs that `retry_on` retried. An SQS redelivery still counts as one
    more execution, so after a redelivery `executions` is one above plain ActiveJob's value

- Fix: `shoryuken sqs dump` and `mv` check their input before they receive any message
  - `dump -p` with a missing or read-only directory received the messages and then raised `Errno::ENOENT` (missing)
    or `Errno::EACCES` (read-only), which left them in flight until their visibility timeout ended; it now fails with
    `[FAIL] Path ... is not a directory` (or `is not writable`)
  - `dump`/`mv -n` below 1 raised `Aws::SQS::Errors::InvalidAttributeValue`; they now fail with
    `[FAIL] Number of messages must be at least 1`
  - `delete` now prints `Queue ... was successfully deleted` (was `delete`)

- Fix: `shoryuken sqs requeue` no longer drops FIFO messages requeued within 5 minutes of their dump
  - It sent each message with its original `MessageDeduplicationId`, so SQS accepted but did not deliver it; it now
    sends a new deduplication id per message (also in `mv`) and keeps the `MessageGroupId`. Requeueing the same dump
    file twice now delivers its messages twice

- Fix: `shoryuken sqs dump` handles Binary message attributes and leaves no file when it fails
  - A Binary value that is not valid UTF-8 raised `JSON::GeneratorError`; `dump` now stores Binary values as base64,
    marked with `"binary_value_encoding": "base64"`, and `requeue` decodes them. Dump files without the mark still
    requeue
  - A dump that failed or stopped while writing left its file, so every later dump of the queue that day failed with
    `File ... already exists`; it now removes the file

- Fix: `shoryuken sqs mv` and `requeue` no longer lose or miscount messages the target queue rejects
  - `mv` deleted every received message from the source, also the ones the target rejected (e.g. a FIFO target and
    messages without a group id); it now deletes only the accepted ones, so the rejected ones stay in the source
  - `mv` and `requeue` count only the accepted messages, print every rejected entry (also on a failed delete, before
    only the first of each batch) and exit with status 1 when an entry was rejected; so does `dump` when a delete fails

- Fix: A raising `retry_intervals` lambda is now logged as such
  - `ExponentialBackoffRetry` logged it as `Failed to set backoff visibility timeout`, although no visibility change
    was attempted; it now logs `retry_intervals raised for <message id>: <error class>: <message>`. The original worker
    error is still re-raised

- Fix: Shoryuken now drains in-flight `ShoryukenConcurrentSendAdapter` sends on shutdown (mensfeld)
  - A job enqueued with the concurrent adapter shortly before the process stopped (e.g. by a worker) was lost: the
    TERM/USR1 handlers exit right after the launcher stops, which killed the background send
  - `Launcher#stop`/`#stop!` now call `wait_for_pending_sends` on every loaded ActiveJob adapter that supports it
    (including adapters set on a single job class) after the executor shutdown
  - The executor shutdown and the drain together stay within `timeout`; a drain that runs out of time or fails is
    logged and does not break shutdown

- Breaking: Drop support for Ruby 3.2 (EOL March 2026)
  - Minimum required Ruby version is now 3.3.0
  - Supported Ruby versions: 3.3, 3.4, 4.0
  - Users on Ruby 3.2 should upgrade or remain on Shoryuken 7.0.x

- Breaking: `shoryuken_options` rejects unknown worker option keys when the worker class loads
  - A mistyped key (e.g. `auto_delte`) now raises `Shoryuken::Errors::InvalidConfigurationError` naming the worker
    and the key, instead of being silently ignored
  - Workers with any other key, including the formerly documented but unused `sqs`, no longer load
  - Known keys: `queue`, `delete`, `auto_delete`, `auto_visibility_timeout`, `retry_intervals`, `batch`,
    `body_parser` and `non_retryable_exceptions`

- Fix: Lifecycle event handlers registered with `Shoryuken.on` no longer leak into `Shoryuken::Options::DEFAULTS`
  - `options` copied the defaults shallowly, so handlers were appended to the shared nested arrays and fired for
    every later `Shoryuken::Options` instance; the defaults are now deep-copied

- Enhancement: Global options are validated when the server loads its configuration
  - Invalid values from the config file, the CLI or Ruby code (e.g. `concurrency: 0`, a `delay` or `timeout` that is
    not a non-negative number, a malformed `queues` entry or group) now raise
    `Shoryuken::Errors::InvalidConfigurationError` naming the option, instead of failing later or being ignored
  - Unknown keys, globally or in a group (e.g. a mistyped `concurency`), log a warning naming the key; they are not
    rejected, so custom keys kept in the options keep working
  - Validation runs on `Shoryuken::Contractable`, a copy of the karafka-core contract layer (MIT), with no new
    dependency

- Fix: `auto_visibility_timeout` now extends a message by the `visibility_timeout` set in
  `sqs_client_receive_message_opts` when there is one
  - It used only the queue's `VisibilityTimeout`, so a shorter receive-time timeout let the message become visible
    again during processing, and it was performed more than once

- Fix: `TimerTask#kill` no longer hangs concurrent callers when it kills the timer thread during shutdown
  - The timer loop's `ensure` took the task mutex; a thread killed while waiting on a `Mutex` can swallow the
    unlock wakeup, so the other `#kill` callers slept forever
  - The loop now clears its running flag without the mutex

- Fix: Fetched messages that are never started are now released at once instead of staying in flight
  - `Manager#assign` dropped a fetched message when the manager was no longer running (stop) or the executor
    rejected the worker post, so it stayed invisible until its visibility timeout expired
  - Such messages now get a visibility timeout of 0, so another consumer can receive them right away; a failed
    release is logged and does not break dispatch or shutdown

- Feature: `ShoryukenConcurrentSendAdapter#wait_for_pending_sends` to drain in-flight async sends (mensfeld)
  - The concurrent send adapter enqueues by scheduling the SQS send on a background future and returning
    immediately, so jobs enqueued shortly before the process exits could be silently dropped
  - `wait_for_pending_sends(timeout = nil)` blocks until every in-flight send has finished (returning
    false if the optional timeout elapses first); call it from your shutdown sequence to flush pending sends
  - In-flight futures are tracked and removed as they resolve, so the set does not grow unbounded

- Fix: A failing shutdown step no longer skips the rest of `Launcher#stop`/`#stop!`
  - An error raised by `stop_callback`, a manager's `stop_new_dispatching`/`await_dispatching_in_progress` or the
    executor shutdown propagated out of the stop sequence, so the remaining steps - including the executor
    shutdown and the `:shutdown`/`:stopped` events - never ran
  - Each step now runs in its own rescue and logs the error, so the remaining steps always run
  - A graceful stop awaits only the managers it signalled, so a manager whose `stop_new_dispatching` raised no
    longer hangs the shutdown

- Fix: `Fetcher` retries now use a deterministic bounded backoff instead of a random sleep (mensfeld)
  - `fetch_with_auto_retry` slept for a random 1-5s between retries (`sleep((1..5).to_a.sample)`) on the
    dispatch thread, which was non-deterministic and untestable
  - It now backs off incrementally (1s, 2s, 3s, ... via `backoff_interval`), naturally bounded because
    `attempts` never exceeds `max_attempts`; the broad rescue is unchanged (the AWS SDK already retries
    throttling/5xx/networking internally) and now carries specs for retry, exhaustion, and the backoff schedule

## [7.0.4] - 2026-09-23

- Fix: `shoryuken sqs dump`/`mv` no longer stop early on real SQS (mensfeld)
  - Real (distributed) SQS often returns an empty batch while the queue still has messages, so dump/mv
    processed only part of the queue. They now long-poll and stop only after several empty batches in a row
  - Messages received again after the visibility timeout expires are no longer dumped, moved or counted twice
  - Messages are still deleted only after the dump/mv, so a failed run deletes nothing and a queue larger than
    the SQS in-flight limit (~120k standard / ~20k FIFO) drains over several runs - no message is lost

- Fix: Graceful stop no longer deadlocks when a manager's dispatch loop never started (mensfeld)
  - `Launcher#stop` deadlocked when the stop arrived before the dispatch loop started, or when an embedded
    host's executor pool was saturated so `manager.start` never ran

- Feature: `Shoryuken.fifo_message_deduplication` to opt out of content-based dedup id generation for raw sends (mensfeld)
  - On FIFO queues, raw sends (`Worker.perform_async`, `Queue#send_message`/`#send_messages`) without a
    `message_deduplication_id` got a SHA256 of the body as that id, so a second identical body within SQS's
    5-minute window was silently dropped. ActiveJob got an opt-out in #1017
  - Set `Shoryuken.fifo_message_deduplication = false` to stop generating that id (provide a
    `message_deduplication_id` yourself or enable `ContentBasedDeduplication` on the queue)
  - Defaults to `true`, preserving the existing behavior; an explicit `message_deduplication_id` is still honored

- Fix: Harden `ExponentialBackoffRetry` visibility handling (mensfeld)
  - A job that ran past the 12h SQS ceiling no longer gets a negative visibility timeout, which SQS rejects;
    it is clamped to 0, so the message is retried as soon as possible
  - A failed visibility change (e.g. an expired receipt handle) is now logged and no longer masks the original
    worker error from exception handlers/notifiers; the message falls back to the queue's default visibility timeout
  - A batch worker's error no longer raises a `NoMethodError` that masked the original error

- Fix: `perform_async` no longer mutates the caller-supplied options hash (mensfeld)
  - In `DefaultExecutor` and `InlineExecutor`, a caller reusing one options hash across enqueues had `:queue`
    stripped after the first call, so later jobs silently went to the worker's default queue

- Fix: `Shoryuken::Client.queues` no longer builds the same queue more than once under concurrency (mensfeld)
  - Concurrent first access built the queue several times: redundant SQS API calls, and a corrupt cache on
    JRuby/TruffleRuby. Access to the cache is now guarded by a mutex

- Fix: Busy-processor counter no longer leaks when the executor rejects a worker post (mensfeld)
  - When the executor rejected a worker with `Concurrent::RejectedExecutionError` (a hard stop racing the
    `running?` check, or a saturated bounded custom `launcher_executor`), the rejected worker stayed counted as busy
  - With a bounded executor, dispatch stalled and the group silently stopped processing (#1029)

## [7.0.3] - 2026-07-10

- Feature: `Shoryuken.active_job_fifo_message_deduplication` to opt out of FIFO dedup id generation (mensfeld)
  - For FIFO queues the ActiveJob adapter derives a content-based `message_deduplication_id` from the
    serialized job minus `job_id`/`enqueued_at` (#457 / #750), so two distinct enqueues of the same job
    class and arguments within SQS's 5-minute window silently collapse into one
  - Set `Shoryuken.active_job_fifo_message_deduplication = false` to stop generating that id (rely on the
    queue's content-based deduplication or explicit ids)
  - Defaults to `true`, preserving the existing behavior; an explicit `message_deduplication_id` is still honored

- Fix: Polling strategies are now thread-safe, and WeightedRoundRobin unpauses processed queues reliably (mensfeld)
  - For FIFO queues, processor-completion threads and the dispatch thread changed the strategy state without
    synchronization: benign on MRI (GVL), but it corrupts state on JRuby/TruffleRuby. Both `WeightedRoundRobin`
    and `StrictPriority` now guard it with a mutex
  - `WeightedRoundRobin` no longer leaves a queue marked ready stuck behind an earlier-paused queue

- Fix: `TimerTask#kill` no longer deadlocks on Ruby 3.2 under concurrent callers (mensfeld)

- Fix: Stopping the launcher no longer destroys the process-global IO executor (mensfeld)
  - With no `launcher_executor` configured, stopping the launcher shut down concurrent-ruby's global `:io`
    pool. This broke anything else using it (including Shoryuken's own `ShoryukenConcurrentSendAdapter`)
    and prevented starting a new launcher in the same process
  - The launcher now owns a dedicated `Concurrent::CachedThreadPool`

- Fix: `Queue#delete_messages` now logs every batch-delete failure and returns a robust boolean (mensfeld)
  - Only the first failure of a batch was logged, and the return value depended on what the logger returned
  - It now returns whether any delete failed, so `NonRetryableException`/`AutoDelete` reliably see that some
    messages may remain and need reprocessing

- Fix: Lifecycle events fired in reverse no longer alternate handler order (mensfeld)
  - An event fired more than once with `reverse: true` (e.g. `:shutdown` via `stop` then `stop!`) flipped
    its handler order each time

- Fix: A fatal dispatch error no longer hard-kills an embedded host process (mensfeld)
  - After a dispatch error (e.g. SQS still failing once the fetcher exhausted its retries) Shoryuken sent USR1
    to its own process. A host embedding `Shoryuken::Launcher` does not trap USR1, so the whole process - and
    its in-flight workers - was terminated
  - When embedded, the failing manager now stops itself and `Launcher#healthy?` reports the failure; in server
    (CLI) mode USR1 is still sent, preserving the supervisor-restart behavior

- Fix: Graceful stop is now bounded by the configured timeout (mensfeld)
  - A graceful stop (USR1/TSTP) waited without limit, so a single hung worker blocked shutdown forever
  - `Launcher#stop` and `Launcher#stop!` now wait up to `Shoryuken.options[:timeout]` seconds for in-flight
    workers, then force-kill the executor so the process can exit

- Docs: Correct the `retry_intervals` exponential backoff documentation (mensfeld)
  - Retries do not stop after the last configured interval: that interval is reused for every later attempt,
    and SQS's redrive policy (maxReceiveCount) is what moves a message to a dead-letter queue

- Fix: `CurrentAttributes.persist` no longer drops a class when called once per class (mensfeld)
  - Registering classes across separate `persist` calls made the third call silently overwrite the second
    class, so its attributes were never serialized or restored. Single-call `persist(A, B, C)` is unchanged

- Fix: Busy-processor accounting no longer breaks when processor completion raises (mensfeld)
  - An exception in completion (SQS lookups or a polling strategy's `message_processed` callback) decremented
    the busy counter twice for one message, silently breaking the configured concurrency limit for the life
    of the process
  - Completion now runs exactly once, and errors from the FIFO bookkeeping are logged instead of raised

- Fix: Repeated graceful stop no longer deadlocks the process (mensfeld)
  - A second `Launcher#stop` (e.g. TSTP then USR1) blocked forever, leaving the process stuck where even
    TERM/INT were no longer handled (only SIGKILL worked)

- Fix: `non_retryable_exceptions` is no longer ignored when `retry_intervals` is also configured (mensfeld)
  - `ExponentialBackoffRetry` swallowed every exception after scheduling a retry, so poison messages were
    retried indefinitely (with the last interval repeated) instead of being deleted immediately
  - It now re-raises non-retryable exceptions so the message gets deleted. The classification is shared by
    both middlewares via `NonRetryableException.non_retryable?`

- Enhancement: Use dynamic Ruby warning category opt-in in test helpers (mensfeld)
  - Test helpers enable all non-deprecated, non-experimental warning categories via `Warning.categories`
    instead of a version-gated `Warning[:performance]`

## [7.0.2] - 2026-04-16

- Enhancement: Replace LocalStack with ElasticMQ for SQS integration tests (mensfeld)
  - ElasticMQ is free, open-source, and requires no auth token (LocalStack 2026.x requires paid account)
  - Uses `softwaremill/elasticmq-native` image (~30MB vs ~1GB+, starts in milliseconds)
  - Rename `setup_localstack` to `setup_sqs` and `bin/clean_localstack` to `bin/clean_sqs`

- Fix: Allow custom polling strategy to be configured per-group via `add_group` (mensfeld)
  - `add_group` now accepts a `polling_strategy:` keyword argument; a group in the YAML config can set `polling_strategy` too
  - [#925](https://github.com/ruby-shoryuken/shoryuken/issues/925)

## [7.0.1] - 2026-02-07

- Enhancement: Add non-retryable exception middleware (Saidbek)
  - [#958](https://github.com/ruby-shoryuken/shoryuken/pull/958)

- Fix: ActiveJob keyword arguments support (mensfeld)
  - Jobs with keyword arguments were broken by incorrect argument forwarding
  - [#962](https://github.com/ruby-shoryuken/shoryuken/pull/962)

- Fix: Replace `ArgumentError` with custom `FifoDelayNotSupportedError` for FIFO delay errors
  - Provides more specific error type for programmatic error handling
  - [#957](https://github.com/ruby-shoryuken/shoryuken/pull/957)

## [7.0.0] - 2026-01-19

**See the [Upgrading to 7.0](https://github.com/ruby-shoryuken/shoryuken/wiki/Upgrading-to-7.0) guide for detailed migration instructions.**

- Breaking: Add `Shoryuken::Errors` module with domain-specific error classes
  - Introduces `Shoryuken::Errors::BaseError` as base class for all Shoryuken errors
  - `Shoryuken::Errors::QueueNotFoundError` for non-existent or inaccessible SQS queues
  - `Shoryuken::Errors::InvalidConfigurationError` for configuration validation failures
  - `Shoryuken::Errors::InvalidWorkerRegistrationError` for worker registration conflicts
  - `Shoryuken::Errors::InvalidPollingStrategyError` for invalid polling strategy configuration
  - `Shoryuken::Errors::InvalidEventError` for invalid lifecycle event names
  - `Shoryuken::Errors::InvalidDelayError` for delays exceeding SQS 15-minute maximum
  - `Shoryuken::Errors::InvalidArnError` for invalid ARN format
  - Replaces generic Ruby exceptions (ArgumentError, RuntimeError) with specific error types

- Removed: `Shoryuken::Shutdown` class
  - This class was unused since the Celluloid removal in 2016
  - Originally used to raise on worker threads during hard shutdown
  - Current shutdown flow uses `Interrupt` and executor-level shutdown instead

- Fix: Raise ArgumentError when using delay with FIFO queues
  - FIFO queues do not support per-message DelaySeconds
  - Previously caused confusing AWS errors with ActiveJob's `retry_on` (Rails 6.1+ defaults to `wait: 3.seconds`)
  - Now raises clear ArgumentError with guidance to use `wait: 0`
  - Fixes #924

- Enhancement: Use fiber-local storage for logging context
  - Replaces thread-local storage with Fiber[] for proper isolation in async environments
  - Ensures logging context doesn't leak between fibers in the same thread
  - Leverages Ruby 3.2+ fiber-local storage API

- Enhancement: Add yard-lint with comprehensive YARD documentation
  - Adds yard-lint gem for documentation linting
  - Documents all public classes, modules, and methods with YARD tags
  - Ensures 100% documentation coverage

- Enhancement: Add `enqueue_all` for bulk ActiveJob enqueuing (Rails 7.1+)
  - Implements efficient bulk enqueuing using SQS `send_message_batch` API
  - Called by `ActiveJob.perform_all_later` for batching multiple jobs
  - Batches jobs in groups of 10 (SQS limit) per queue
  - Groups jobs by queue name for efficient multi-queue handling

- Enhancement: Add ActiveJob Continuations support (Rails 8.1+)
  - Implements `stopping?` method in ActiveJob adapters to signal graceful shutdown
  - Enables jobs to checkpoint progress and resume after interruption
  - Handles past timestamps correctly (SQS treats negative delays as immediate delivery)
  - Tracks shutdown state via the `Launcher#stopping?` flag
  - See Rails PR #55127 for more details on ActiveJob Continuations

- Enhancement: Add CurrentAttributes persistence support
  - Enables Rails `ActiveSupport::CurrentAttributes` to flow from enqueue to job execution
  - Automatically serializes current attributes into job payload when enqueuing
  - Restores attributes before job execution and resets them afterward
  - Supports multiple CurrentAttributes classes
  - Based on Sidekiq's approach using `ActiveJob::Arguments` for serialization
  - Usage: `require 'shoryuken/active_job/current_attributes'` and
    `Shoryuken::ActiveJob::CurrentAttributes.persist('MyApp::Current')`

- Breaking: Drop support for Ruby 3.1 (EOL March 2025)
  - Minimum required Ruby version is now 3.2.0
  - Supported Ruby versions: 3.2, 3.3, 3.4
  - Users on Ruby 3.1 should upgrade or remain on Shoryuken 6.x

- Breaking: Remove support for Rails versions older than 7.2
  - Rails 7.0 and 7.1 have reached end-of-life (April 2025) and are no longer supported
  - Supported Rails versions: 7.2, 8.0, and 8.1
  - Users on older Rails versions should upgrade or remain on Shoryuken 6.x

- Enhancement: Replace Concurrent::AtomicFixnum with pure Ruby AtomicCounter
  - Removes external dependency on concurrent-ruby for atomic fixnum operations
  - Introduces Shoryuken::Helpers::AtomicCounter as a thread-safe alternative using Mutex
  - Reduces gem footprint while maintaining full functionality

- Enhancement: Replace Concurrent::AtomicBoolean with pure Ruby AtomicBoolean
  - Removes external dependency on concurrent-ruby for atomic boolean operations
  - Introduces Shoryuken::Helpers::AtomicBoolean extending AtomicCounter
  - Further reduces gem footprint while maintaining full functionality

- Enhancement: Replace Concurrent::Hash with pure Ruby AtomicHash
  - Removes external dependency on concurrent-ruby for hash operations
  - Introduces Shoryuken::Helpers::AtomicHash with mutex-protected writes and concurrent reads
  - Ensures JRuby compatibility while maintaining high performance for read-heavy workloads
  - [#866](https://github.com/ruby-shoryuken/shoryuken/pull/866)
  - [#867](https://github.com/ruby-shoryuken/shoryuken/pull/867)
  - [#868](https://github.com/ruby-shoryuken/shoryuken/pull/868)

- Enhancement: Replace core class extensions with helper utilities
  - Removes all core Ruby class monkey-patching (Hash and String extensions)
  - Introduces Shoryuken::Helpers::HashUtils.deep_symbolize_keys for configuration processing
  - Introduces Shoryuken::Helpers::StringUtils.constantize for dynamic class loading
  - Eliminates unnecessary ActiveSupport dependencies
  - Completely removes lib/shoryuken/core_ext.rb file

- Enhancement: Implement Zeitwerk autoloading
  - Replaces manual require statements with Zeitwerk-based autoloading
  - Adds zeitwerk dependency for modern Ruby module loading
  - Splits polling classes into properly named files (BaseStrategy, QueueConfiguration)

- Enhancement: Increase `SendMessageBatch` to 1MB to align with AWS
  - [#864](https://github.com/ruby-shoryuken/shoryuken/pull/864)

- Enhancement: Replace OpenStruct usage with Struct for inline execution
  - [#860](https://github.com/ruby-shoryuken/shoryuken/pull/860)

- Enhancement: Configure server side logging (BenMorganMY)
  - [#844](https://github.com/ruby-shoryuken/shoryuken/pull/844)

- Enhancement: Use -1 as thread priority
  - [#825](https://github.com/ruby-shoryuken/shoryuken/pull/825)

- Enhancement: Add Support for message_attributes to InlineExecutor
  - [#835](https://github.com/ruby-shoryuken/shoryuken/pull/835)

- Enhancement: Introduce trusted publishing
  - [#840](https://github.com/ruby-shoryuken/shoryuken/pull/840)

- Enhancement: Add enqueue_after_transaction_commit? for Rails 7.2 compatibility
  - [#777](https://github.com/ruby-shoryuken/shoryuken/pull/777)

- Enhancement: Bring Ruby 3.4 into the CI
  - [#805](https://github.com/ruby-shoryuken/shoryuken/pull/805)

- Fix integration tests by updating aws-sdk-sqs and replacing moto with LocalStack
  - [#782](https://github.com/ruby-shoryuken/shoryuken/pull/782)
  - [#783](https://github.com/ruby-shoryuken/shoryuken/pull/783)

- Breaking: Remove support of Ruby versions older than 3.1
  - [#783](https://github.com/ruby-shoryuken/shoryuken/pull/783)
  - [#850](https://github.com/ruby-shoryuken/shoryuken/pull/850)

- Breaking: Remove support of Rails versions older than 7.0
  - [#783](https://github.com/ruby-shoryuken/shoryuken/pull/783)
  - [#850](https://github.com/ruby-shoryuken/shoryuken/pull/850)

- Breaking: Require `aws-sdk-sqs` `>=` `1.66`:
  - [#783](https://github.com/ruby-shoryuken/shoryuken/pull/783)

## [v6.2.1] - 2024-02-09

- Bugfix: Not able to use extended polling strategy (#759)
  - [#759](https://github.com/ruby-shoryuken/shoryuken/pull/759)

## [v6.2.0] - 2024-02-04

- Enable hot-reload via adding ActiveSupport::Reloader delegate (#756)
  - [#756](https://github.com/ruby-shoryuken/shoryuken/pull/756)

## [v6.1.2] - 2024-01-30

- Fix activerecord 7.1 deprecation warnings
  - [#755](https://github.com/ruby-shoryuken/shoryuken/pull/755)

## [v6.1.1] - 2023-11-27

- Fix SQS API Changes causing nil returns instead of empty arrays
  - [#754](https://github.com/ruby-shoryuken/shoryuken/pull/754)
  - [#753](https://github.com/ruby-shoryuken/shoryuken/pull/753)

## [v6.1.0] - 2023-11-01

- Add GitHub Codespaces

  - [#698](https://github.com/ruby-shoryuken/shoryuken/pull/698)

- Fix spec for ruby 3.0

  - [#727](https://github.com/ruby-shoryuken/shoryuken/pull/727)

- Upgrade test matrix. Add Ruby 3.1, Ruby 3.2 and Rails 7

  - [#739](https://github.com/ruby-shoryuken/shoryuken/pull/739)

- Fire stopped event after executor is stopped

  - [#741](https://github.com/ruby-shoryuken/shoryuken/pull/741)

- Allow setup custom exception handlers for failing jobs

  - [#742](https://github.com/ruby-shoryuken/shoryuken/pull/742)

- Configure dependabot to update GH Actions

  - [#745](https://github.com/ruby-shoryuken/shoryuken/pull/745)

- Stop the dispatching of new messages when a SIGTERM signal has been received
  - [#750](https://github.com/ruby-shoryuken/shoryuken/pull/750)

## [v6.0.0] - 2022-02-18

- Breaking changes: Initialize Rails before parsing config file
  - [#686](https://github.com/ruby-shoryuken/shoryuken/pull/686)
  - With `--rails`/`-R`, Rails is now initialized first, then the YAML config file is read, then CLI arguments. Before, Rails came last, so the config file could not use environment variables set by Rails (e.g. with `dotenv`)
  - Most applications need no changes, but the new load order can change behavior depending on the YAML config file or Rails initializers

## [v5.3.2] - 2022-01-19

- (Bugfix) Preserve queue weights when unpausing queues

  - [#687](https://github.com/ruby-shoryuken/shoryuken/pull/687)

- Improve error message on startup when shoryuken has insufficient permissions to access a queue
  - [#691](https://github.com/ruby-shoryuken/shoryuken/pull/691)

## [v5.3.1] - 2022-01-07

- (Bugfix) Fix issue where, when using the TSTP or USR1 signals for soft shutdowns, it was possible for shoryuken to terminate without first attempting to handle all messages it fetched from SQS
  - [#676](https://github.com/ruby-shoryuken/shoryuken/pull/676)

## [v5.3.0] - 2021-10-31

- (Refactor) Use Forwardable within Message to avoid method boilerplate

  - [#681](https://github.com/ruby-shoryuken/shoryuken/pull/681)

- Add basic health check API
  - [#679](https://github.com/ruby-shoryuken/shoryuken/pull/679)

## [v5.2.3] - 2021-07-29

- Fire new `:utilization_update` event any time a worker pool's utilization changes
  - [#673](https://github.com/ruby-shoryuken/shoryuken/pull/673)

## [v5.2.2] - 2021-06-22

- When using ActiveJob queue name prefixing, avoid applying prefix to queues configured with a URL or ARN
  - [#667](https://github.com/ruby-shoryuken/shoryuken/pull/667)

## [v5.2.1] - 2021-04-06

- Reduce message batch sizes in `shoryuken sqs requeue` and `shoryuken sqs mv` commands

  - [#666](https://github.com/ruby-shoryuken/shoryuken/pull/666)

- Fix bug in `shoryuken sqs requeue` and `shoryuken sqs mv` where those commands would exceed the SQS `SendMessageBatch` maximum payload size

  - [#663](https://github.com/ruby-shoryuken/shoryuken/issues/663)
  - [#664](https://github.com/ruby-shoryuken/shoryuken/pull/664)

- Remove test stub for `Concurrent.global_io_executor`

  - [#662](https://github.com/ruby-shoryuken/shoryuken/pull/662)

- Run integration tests on CI
  - [#660](https://github.com/ruby-shoryuken/shoryuken/pull/660)

## [v5.2.0] - 2021-02-26

- Set `executions` correctly for ActiveJob jobs
  - [#657](https://github.com/ruby-shoryuken/shoryuken/pull/657)

## [v5.1.1] - 2021-02-10

- Fix regression in Ruby 3.0 introduced in Shoryuken 5.1.0, where enqueueing jobs with ActiveJob to workers that used keyword arguments would fail
  - [#654](https://github.com/ruby-shoryuken/shoryuken/pull/654)

## [v5.1.0] - 2021-02-06

- Add support for specifying SQS SendMessage parameters with ActiveJob `.set`

  - [#635](https://github.com/ruby-shoryuken/shoryuken/pull/635)
  - [#648](https://github.com/ruby-shoryuken/shoryuken/pull/648)
  - [#651](https://github.com/ruby-shoryuken/shoryuken/pull/651)

- Unpause FIFO queues on worker completion

  - [#644](https://github.com/ruby-shoryuken/shoryuken/pull/644)

- Add multiple versions of Rails to test matrix

  - [#647](https://github.com/ruby-shoryuken/shoryuken/pull/647)

- Migrate from Travis CI to Github Actions
  - [#649](https://github.com/ruby-shoryuken/shoryuken/pull/649)
  - [#650](https://github.com/ruby-shoryuken/shoryuken/pull/650)
  - [#652](https://github.com/ruby-shoryuken/shoryuken/pull/652)

## [v5.0.6] - 2020-12-30

- Load ShoryukenConcurrentSendAdapter when loading Rails
  - [#642](https://github.com/ruby-shoryuken/shoryuken/pull/642)

## [v5.0.5] - 2020-06-07

- Add ability to configure queue by ARN
  - [#603](https://github.com/ruby-shoryuken/shoryuken/pull/603)

## [v5.0.4] - 2020-02-20

- Add endpoint option to SQS CLI
  - [#595](https://github.com/ruby-shoryuken/shoryuken/pull/595)

## [v5.0.3] - 2019-11-30

- Add support for sending messages asynchronous with Active Job using `shoryuken_concurrent_send`
  - [#589](https://github.com/ruby-shoryuken/shoryuken/pull/589)
  - [#588](https://github.com/ruby-shoryuken/shoryuken/pull/588)

## [v5.0.2] - 2019-11-02

- Fix Queue order is reversed if passed through CLI
  - [#571](https://github.com/ruby-shoryuken/shoryuken/pull/583)

## [v5.0.1] - 2019-06-19

- Add back attr_accessor for `stop_callback`
  - [#571](https://github.com/ruby-shoryuken/shoryuken/pull/571)

## [v5.0.0] - 2019-06-18

- Fix bug where empty queues were not paused in batch processing mode

  - [#569](https://github.com/ruby-shoryuken/shoryuken/pull/569)

- Preserve batch limit when receiving messages from a FIFO queue

  - [#563](https://github.com/ruby-shoryuken/shoryuken/pull/563)

- Replace static options with instance options
  - [#534](https://github.com/ruby-shoryuken/shoryuken/pull/534)

## [v4.0.3] - 2019-01-06

- Support delay per processing group
  - [#543](https://github.com/ruby-shoryuken/shoryuken/pull/543)

## [v4.0.2] - 2018-11-26

- Fix the delegated methods to public warning

  - [#536](https://github.com/ruby-shoryuken/shoryuken/pull/536)

- Specify exception class to `raise_error` matcher warning

  - [#537](https://github.com/ruby-shoryuken/shoryuken/pull/537)

- Fix spelling of "visibility"
  - [#538](https://github.com/ruby-shoryuken/shoryuken/pull/538)

## [v4.0.1] - 2018-11-21

- Allow caching visibility_timeout lookups

  - [#533](https://github.com/ruby-shoryuken/shoryuken/pull/533)

- Add queue name to inline executor
  - [#532](https://github.com/ruby-shoryuken/shoryuken/pull/532)

## [v4.0.0] - 2018-11-01

- Process messages to the same message group ID one by one
  - [#530](https://github.com/ruby-shoryuken/shoryuken/pull/530)

## [v3.3.1] - 2018-10-30

- Memoization of boolean causes extra calls to SQS
  - [#529](https://github.com/ruby-shoryuken/shoryuken/pull/529)

## [v3.3.0] - 2018-09-30

- Add support for TSTP

  - [#492](https://github.com/ruby-shoryuken/shoryuken/pull/492)

- Support an empty list of queues as a CLI argument

  - [#507](https://github.com/ruby-shoryuken/shoryuken/pull/507)

- Add batch support for inline workers

  - [#514](https://github.com/ruby-shoryuken/shoryuken/pull/514)

- Make InlineExecutor to behave as the DefaultExecutor when calling perform_in
  - [#518](https://github.com/ruby-shoryuken/shoryuken/pull/518)

## [v3.2.3] - 2018-03-25

- Don't force eager load for Rails 5

  - [#480](https://github.com/ruby-shoryuken/shoryuken/pull/480)

- Allow Batch Size to be Specified for Requeue

  - [#478](https://github.com/ruby-shoryuken/shoryuken/pull/478)

- Support FIFO queues in `shoryuken sqs` commands
  - [#473](https://github.com/ruby-shoryuken/shoryuken/pull/473)

## [v3.2.2] - 2018-02-13

- Fix requeue' for FIFO queues
  - [#48fcb42](https://github.com/ruby-shoryuken/shoryuken/commit/48fcb4260c3b41a9e45fa29bb857e8fa37dcee82)

## [v3.2.1] - 2018-02-12

- Support FIFO queues in `shoryuken sqs` commands

  - [#473](https://github.com/ruby-shoryuken/shoryuken/pull/473)

- Allow customizing the default executor launcher

  - [#469](https://github.com/ruby-shoryuken/shoryuken/pull/469)

- Exclude job_id from message deduplication when ActiveJob
  - [#462](https://github.com/ruby-shoryuken/shoryuken/pull/462)

## [v3.2.0] - 2018-01-03

- Preserve parent worker class options

  - [#451](https://github.com/ruby-shoryuken/shoryuken/pull/451)

- Add -t (shutdown timeout) option to CL

  - [#449](https://github.com/ruby-shoryuken/shoryuken/pull/449)

- Support inline (Active Job like) for standard workers
  - [#448](https://github.com/ruby-shoryuken/shoryuken/pull/448)

## [v3.1.12] - 2017-09-25

- Reduce fetch log verbosity
  - [#436](https://github.com/ruby-shoryuken/shoryuken/pull/436)

## [v3.1.11] - 2017-09-02

- Auto retry (up to 3 times) fetch errors
  - [#429](https://github.com/ruby-shoryuken/shoryuken/pull/429)

## [v3.1.10] - 2017-09-02

- Make Shoryuken compatible with AWS SDK 3 and 2
  - [#433](https://github.com/ruby-shoryuken/shoryuken/pull/433)

## [v3.1.9] - 2017-08-24

- Add support for adding a middleware to the front of chain

  - [#427](https://github.com/ruby-shoryuken/shoryuken/pull/427)

- Add support for dispatch fire event
  - [#426](https://github.com/ruby-shoryuken/shoryuken/pull/426)

## [v3.1.8] - 2017-08-17

- Make Polling strategy backward compatibility
  - [#424](https://github.com/ruby-shoryuken/shoryuken/pull/424)

## [v3.1.7] - 2017-07-31

- Allow polling strategy per group

  - [#417](https://github.com/ruby-shoryuken/shoryuken/pull/417)

- Add support for creating FIFO queues

  - [#419](https://github.com/ruby-shoryuken/shoryuken/pull/419)

- Allow receive message options per queue
  - [#420](https://github.com/ruby-shoryuken/shoryuken/pull/420)

## [v3.1.6] - 2017-07-24

- Fix issue with dispatch_loop and delays
  - [#416](https://github.com/ruby-shoryuken/shoryuken/pull/416)

## [v3.1.5] - 2017-07-23

- Fix memory leak

  - [#414](https://github.com/ruby-shoryuken/shoryuken/pull/414)

- Fail fast on bad queue URLs
  - [#413](https://github.com/ruby-shoryuken/shoryuken/pull/413)

## [v3.1.4] - 2017-07-14

- Require forwardable allowding to call `shoryuken` without `bundle exec`
  - [#409](https://github.com/ruby-shoryuken/shoryuken/pull/409)

## [v3.1.3] - 2017-07-11

- Add queue prefixing support for groups

  - [#405](https://github.com/ruby-shoryuken/shoryuken/pull/405)

- Remove dead code
  - [#402](https://github.com/ruby-shoryuken/shoryuken/pull/402)

## [v3.1.2] - 2017-07-06

- Fix stack level too deep on Ubuntu
  - [#400](https://github.com/ruby-shoryuken/shoryuken/pull/400)

## [v3.1.1] - 2017-07-05

- Reduce log verbosity introduced in 3.1.0

  - [#397](https://github.com/ruby-shoryuken/shoryuken/pull/397)

- Try to prevent stack level too deep on Ubuntu
  - [#396](https://github.com/ruby-shoryuken/shoryuken/pull/396)

## [v3.1.0] - 2017-07-02

- Add shoryuken sqs delete command

  - [#395](https://github.com/ruby-shoryuken/shoryuken/pull/395)

- Add processing groups support; Concurrency per queue support

  - [#389](https://github.com/ruby-shoryuken/shoryuken/pull/389)

- Terminate Shoryuken if the fetcher crashes
  - [#389](https://github.com/ruby-shoryuken/shoryuken/pull/389)

## [v3.0.11] - 2017-06-24

- Add shoryuken sqs create command
  - [#388](https://github.com/ruby-shoryuken/shoryuken/pull/388)

## [v3.0.10] - 2017-06-24

- Allow aws sdk v3

  - [#381](https://github.com/ruby-shoryuken/shoryuken/pull/381)

- Allow configuring Rails via the config file
  - [#387](https://github.com/ruby-shoryuken/shoryuken/pull/387)

## [v3.0.9] - 2017-06-05

- Allow configuring queue URLs instead of names
  - [#378](https://github.com/ruby-shoryuken/shoryuken/pull/378)

## [v3.0.8] - 2017-06-02

- Fix miss handling empty batch fetches

  - [#376](https://github.com/ruby-shoryuken/shoryuken/pull/376)

- Various minor styling changes :lipstick:

  - [#373](https://github.com/ruby-shoryuken/shoryuken/pull/373)

- Logout when batch delete returns any failure
  - [#371](https://github.com/ruby-shoryuken/shoryuken/pull/371)

## [v3.0.7] - 2017-05-18

- Trigger events for dispatch

  - [#362](https://github.com/ruby-shoryuken/shoryuken/pull/362)

- Log (warn) exponential backoff tries

  - [#365](https://github.com/ruby-shoryuken/shoryuken/pull/365)

- Fix displaying of long queue names in `shoryuken sqs ls`
  - [#366](https://github.com/ruby-shoryuken/shoryuken/pull/366)

## [v3.0.6] - 2017-04-11

- Fix delay option type
  - [#356](https://github.com/ruby-shoryuken/shoryuken/pull/356)

## [v3.0.5] - 2017-04-09

- Pause endless dispatcher to avoid CPU overload

  - [#354](https://github.com/ruby-shoryuken/shoryuken/pull/354)

- Auto log processor errors

  - [#355](https://github.com/ruby-shoryuken/shoryuken/pull/355)

- Add a delay as a CLI param

  - [#350](https://github.com/ruby-shoryuken/shoryuken/pull/350)

- Add `sqs purge` command. See https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_PurgeQueue.html
  - [#344](https://github.com/ruby-shoryuken/shoryuken/pull/344)

## [v3.0.4] - 2017-03-24

- Add `sqs purge` command. See https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_PurgeQueue.html

  - [#344](https://github.com/ruby-shoryuken/shoryuken/pull/344)

- Fix "Thread exhaustion" error. This issue was most noticed when using long polling. @waynerobinson :beers: for pairing up on this.
  - [#345](https://github.com/ruby-shoryuken/shoryuken/pull/345)

## [v3.0.3] - 2017-03-19

- Update `sqs` CLI commands to use `get_queue_url` when appropriated
  - [#341](https://github.com/ruby-shoryuken/shoryuken/pull/341)

## [v3.0.2] - 2017-03-19

- Fix custom SQS client initialization
  - [#335](https://github.com/ruby-shoryuken/shoryuken/pull/335)

## [v3.0.1] - 2017-03-13

- Fix commands sqs mv and dump `options.delete` checker
  - [#332](https://github.com/ruby-shoryuken/shoryuken/pull/332)

## [v3.0.0] - 2017-03-12

- Replace Celluloid with Concurrent Ruby

  - [#291](https://github.com/ruby-shoryuken/shoryuken/pull/291)

- Remove AWS configuration from Shoryuken. Now AWS should be configured from outside. Check [this](https://github.com/ruby-shoryuken/shoryuken/wiki/Configure-the-AWS-Client) for more details

  - [#317](https://github.com/ruby-shoryuken/shoryuken/pull/317)

- Remove deprecation warnings

  - [#326](https://github.com/ruby-shoryuken/shoryuken/pull/326)

- Allow dynamic adding queues

  - [#322](https://github.com/ruby-shoryuken/shoryuken/pull/322)

- Support retry_intervals passed in as a lambda. Auto coerce intervals into integer

  - [#329](https://github.com/ruby-shoryuken/shoryuken/pull/329)

- Add SQS commands `shoryuken help sqs`, such as `ls`, `mv`, `dump` and `requeue`
  - [#330](https://github.com/ruby-shoryuken/shoryuken/pull/330)

## [v2.1.3] - 2017-01-27

- Show a warn message when batch isn't supported

  - [#302](https://github.com/ruby-shoryuken/shoryuken/pull/302)

- Require Celluloid ~> 17

  - [#305](https://github.com/ruby-shoryuken/shoryuken/pull/305)

- Fix excessive logging when 0 messages found
  - [#307](https://github.com/ruby-shoryuken/shoryuken/pull/307)

## [v2.1.2] - 2016-12-22

- Fix loading `logfile` from shoryuken.yml

  - [#296](https://github.com/ruby-shoryuken/shoryuken/pull/296)

- Add support for Strict priority polling (pending documentation)

  - [#288](https://github.com/ruby-shoryuken/shoryuken/pull/288)

- Add `test_workers` for end-to-end testing supporting

  - [#286](https://github.com/ruby-shoryuken/shoryuken/pull/286)

- Update README documenting `configure_client` and `configure_server`

  - [#283](https://github.com/ruby-shoryuken/shoryuken/pull/283)

- Fix memory leak caused by async tracking busy threads

  - [#289](https://github.com/ruby-shoryuken/shoryuken/pull/289)

- Refactor fetcher, polling strategy and manager
  - [#284](https://github.com/ruby-shoryuken/shoryuken/pull/284)

## [v2.1.1] - 2016-12-05

- Fix aws deprecation warning message
  - [#279](https://github.com/ruby-shoryuken/shoryuken/pull/279)

## [v2.1.0] - 2016-12-03

- Fix celluloid "running in BACKPORTED mode" warning

  - [#260](https://github.com/ruby-shoryuken/shoryuken/pull/260)

- Allow setting the aws configuration in 'Shoryuken.configure_server'

  - [#252](https://github.com/ruby-shoryuken/shoryuken/pull/252)

- Allow requiring a file or dir a through `-r`

  - [#248](https://github.com/ruby-shoryuken/shoryuken/pull/248)

- Reduce info log verbosity

  - [#243](https://github.com/ruby-shoryuken/shoryuken/pull/243)

- Fix auto extender when using ActiveJob

  - [#3213](https://github.com/ruby-shoryuken/shoryuken/pull/213)

- Add FIFO queue support

  - [#272](https://github.com/ruby-shoryuken/shoryuken/issues/272)

- Deprecates initialize_aws

  - [#269](https://github.com/ruby-shoryuken/shoryuken/pull/269)

- [Other miscellaneous updates](https://github.com/ruby-shoryuken/shoryuken/compare/v2.0.11...v2.1.0)

## [v2.0.11] - 2016-07-02

- Same as 2.0.10. Unfortunately 2.0.10 was removed `yanked` by mistake from RubyGems.
  - [#b255bc3](https://github.com/ruby-shoryuken/shoryuken/commit/b255bc3)

## [v2.0.10] - 2016-06-09

- Fix manager #225
  - [#226](https://github.com/ruby-shoryuken/shoryuken/pull/226)

## [v2.0.9] - 2016-06-08

- Fix daemonization broken in #219
  - [#224](https://github.com/ruby-shoryuken/shoryuken/pull/224)

## [v2.0.8] - 2016-06-07

- Fix daemonization
  - [#223](https://github.com/ruby-shoryuken/shoryuken/pull/223)

## [v2.0.7] - 2016-06-06

- Daemonize before loading environment

  - [#219](https://github.com/ruby-shoryuken/shoryuken/pull/219)

- Fix initialization when using rails

  - [#197](https://github.com/ruby-shoryuken/shoryuken/pull/197)

- Improve message fetching

  - [#214](https://github.com/ruby-shoryuken/shoryuken/pull/214)
  - [#f4640d9](https://github.com/ruby-shoryuken/shoryuken/commit/f4640d9)

- Fix hard shutdown if there are some busy workers when signal received

  - [#215](https://github.com/ruby-shoryuken/shoryuken/pull/215)

- Fix `rake console` task

  - [#208](https://github.com/ruby-shoryuken/shoryuken/pull/208)

- Isolate `MessageVisibilityExtender` as new middleware

  - [#199](https://github.com/ruby-shoryuken/shoryuken/pull/190)

- Fail on non-existent queues
  - [#196](https://github.com/ruby-shoryuken/shoryuken/pull/196)

## [v2.0.6] - 2016-04-18

- Fix log initialization introduced by #191
  - [#195](https://github.com/ruby-shoryuken/shoryuken/pull/195)

## [v2.0.5] - 2016-04-17

- Fix log initialization when using `Shoryuken::EnvironmentLoader#load`

  - [#191](https://github.com/ruby-shoryuken/shoryuken/pull/191)

  - Fix `enqueue_at` in the ActiveJob Adapter
  - [#182](https://github.com/ruby-shoryuken/shoryuken/pull/182)

## [v2.0.4] - 2016-02-04

- Add Rails 3 support

  - [#175](https://github.com/ruby-shoryuken/shoryuken/pull/175)

- Allow symbol as a queue name in shoryuken_options

  - [#177](https://github.com/ruby-shoryuken/shoryuken/pull/177)

- Make sure bundler is always updated on Travis CI

  - [#176](https://github.com/ruby-shoryuken/shoryuken/pull/176)

- Add Rails 5 compatibility
  - [#174](https://github.com/ruby-shoryuken/shoryuken/pull/174)

## [v2.0.3] - 2015-12-30

- Allow multiple queues per worker

  - [#164](https://github.com/ruby-shoryuken/shoryuken/pull/164)

- Fix typo
  - [#166](https://github.com/ruby-shoryuken/shoryuken/pull/166)

## [v2.0.2] - 2015-10-27

- Fix warnings that are triggered in some cases with the raise_error matcher

  - [#144](https://github.com/ruby-shoryuken/shoryuken/pull/144)

- Add lifecycle event registration support

  - [#141](https://github.com/ruby-shoryuken/shoryuken/pull/141)

- Allow passing array of messages to send_messages

  - [#140](https://github.com/ruby-shoryuken/shoryuken/pull/140)

- Fix Active Job queue prefixing in Rails apps

  - [#139](https://github.com/ruby-shoryuken/shoryuken/pull/139)

- Enable override the default queue with a :queue option
  - [#147](https://github.com/ruby-shoryuken/shoryuken/pull/147)

## [v2.0.1] - 2015-10-09

- Bump aws-sdk to ~> 2
  - [#138](https://github.com/ruby-shoryuken/shoryuken/pull/138)

## [v2.0.0] - 2015-09-22

- Allow configuration of SQS/SNS endpoints via environment variables

  - [#130](https://github.com/ruby-shoryuken/shoryuken/pull/130)

- Expose queue_name in the message object

  - [#127](https://github.com/ruby-shoryuken/shoryuken/pull/127)

- README updates
  - [#122](https://github.com/ruby-shoryuken/shoryuken/pull/122)
  - [#120](https://github.com/ruby-shoryuken/shoryuken/pull/120)
