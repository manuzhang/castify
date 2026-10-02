# Episode summary providers

## Provider contract

`EpisodeSummaryService` accepts an injected `EpisodeSummaryProvider`. Both
`RemoteEpisodeSummaryProvider` and `LocalEpisodeSummaryProvider` implement that
contract. A request contains an episode ID, supplied transcript/show-notes text,
an optional source URL, and an output language code. A successful result contains
an overview, key points, and the input's provenance plus the provider ID.
Transcript provenance does not imply that the supplied text covers the full episode.

Providers report current availability and supported source types, optional
language restrictions, and optional input-length limits. The service validates
inputs/results and delivers exactly one asynchronous main-queue completion.
Its cancellation handle forwards cancellation to the injected operation and
reports `.cancelled`; whichever terminal result arrives first wins. Adapters
map transport/model failures to the shared `EpisodeSummaryError` cases.

## Offline extraction

`EpisodeSummaryService()` defaults to `LocalEpisodeSummaryProvider`, backed by
`OfflineExtractiveSummarizer`. It runs entirely on-device with the operating
system's NaturalLanguage sentence/word tokenization and language detection.
There are no credentials, network calls, model downloads, or external services.
`RemoteEpisodeSummaryProvider` remains opt-in and unavailable (`notConfigured`)
until an operation is injected. Other local engines can also be injected with
their own readiness checks and capabilities. Foundation callbacks and
NaturalLanguage APIs preserve the iOS 13 deployment target.

The offline method removes common caption metadata and isolated stage cues,
deduplicates sentences, and ranks sentences by average term frequency across
unique sentences, excluding common stop words. A small earlier-position bonus
breaks similar scores; exact ties follow source order. The overview is the
highest-ranked whole sentence; up to five key sentences follow source order.
Each sentence is limited to 320 characters, and input to 120,000 characters.
Long sentences are skipped rather than truncated; no usable sentence produces
`insufficientContent`. Results explicitly report the `extractive` method.

## Languages and limitations

English and simplified/traditional Chinese are supported. Text is preserved,
not rewritten or translated. Requested language must match the detected source
language; Chinese script changes and other language requests return
`unsupportedLanguage`. Language detection can be uncertain for very short or
mixed-language text. Sentences in another script are omitted, and repeated
wording, stop-word heuristics, or long sentences can affect coverage. Selection
is deterministic for the same system tokenizer/input and is not a guarantee of
full transcript or audio coverage. Cancellation stops work between processing
stages and during sentence enumeration; individual system NLP calls are bounded
by the input limit.

## Tests and follow-up work

Tests inject explicitly marked fixture output to verify interchangeable
providers, provenance, readiness, validation, errors, cancellation, and callback
delivery. Fixture summaries are test-only and never displayed by the app.
Additional tests exercise the real offline implementation with English/Chinese,
noise, repetition, bounds, language mismatches, determinism, and cancellation.
Remote provider/model selection and credentials/backend, transcript discovery
and fetching, caching, and episode UI integration remain follow-up work.

[Back to README](../README.md)
