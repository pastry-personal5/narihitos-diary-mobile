# P1-M1: Qwen transcription research

Status: Active

This historical research compares hosted Qwen ASR models for recorded English (en-US) and Korean (ko-KR) diary clips capped at five minutes. It reports published Singapore and Beijing pay-as-you-go prices and a provisional integration recommendation; it does not select a model for the product. Sources were checked on 2026-11-01. The owner's filtered [QwenCloud model marketplace](https://www.qwencloud.com/models?region=cn-beijing&task=audio%2Faudio-understanding%2Freal-time-audio-understanding%2Caudio%2Faudio-understanding%2Fnon-real-time-audio-understanding%2Caudio%2Fspeech-recognition%2Freal-time-speech-recognition%2Fsimplex-real-time-speech-recognition%2Caudio%2Fspeech-recognition%2Fnon-real-time-speech-recognition%2Caudio%2Fspeech-synthesis%2Freal-time-speech-synthesis%2Fsimplex-real-time-speech-synthesis%2Caudio%2Fspeech-synthesis%2Fnon-real-time-speech-synthesis%2Caudio%2Fspeech-interaction%2Freal-time-speech-interaction%2Ffull-duplex%2Caudio%2Fspeech-interaction%2Freal-time-speech-interaction%2Fother-real-time-speech-interaction&sort=lowest) could not be read by the research tool, so prices below come from the provider's [regional pricing table](https://www.alibabacloud.com/help/en/model-studio/model-pricing) and [QwenCloud model-price reference](https://docs.qwencloud.com/developer-guides/getting-started/model-prices).

Scope update: hosted Qwen has moved from v1 to future work. The model comparisons and prices below are historical research, not current v1 choices; see [product behavior](../product-behavior.md#transcription).

## Models researched for future hosted Qwen

The provider's [speech-to-text overview](https://docs.qwencloud.com/developer-guides/speech/speech-to-text-models) lists English and Korean for every model below. These are language-level claims, not measured accuracy for en-US or ko-KR diary speech. No model call or comparative recognition test was performed for this project.

| Model | Input, limit, and capabilities | Fit for five-minute diary files |
|---|---|---|
| `qwen-audio-3.0-asr-flash` | HTTP, URL/Base64, .m4a listed, any sample rate, ≤5 min/2 GB. Language hints, hot words, and context; no speaker diarization. Duration-billed. | Direct input for the proposed .m4a archive; predictable cost. Baseline candidate. |
| `qwen-audio-3.1-asr-flash` | Same short-file input/limit. Language hints, hot words, context, speaker diarization, and optional native text polishing (off by default). Token-billed. | Direct .m4a quality/feature candidate. Keep polishing off until diary-text behavior is decided. |
| `qwen3-asr-flash` | HTTP, URL/Base64, ≤5 min/10 MB; the published format table **omits .m4a** but lists AAC and WAV. Language hint and emotion output; no diarization. The API permits limited recognition context, although the model overview does not list an accuracy-boost feature. Duration-billed. | Not a documented direct input for the current .m4a archive. Validate an actual file or conversion path before exposing it. |
| `qwen3-asr-flash-filetrans` | Asynchronous URL-based file job, .m4a listed, ≤12 h/2 GB; emotion output and timestamps, no diarization. Duration-billed. | Accepts .m4a, but public-file URL, polling, result retrieval, and deletion add work for five-minute clips. |
| `qwen-audio-3.0-asr-flash-filetrans` | Asynchronous URL-based .m4a job, ≤12 h/2 GB; hot words/context and diarization. Duration-billed. | Long-file option; unnecessary for the v1 duration cap unless features justify it. |
| `qwen-audio-3.1-asr-flash-filetrans` | Asynchronous URL-based .m4a job, ≤12 h/2 GB; hot words/context and diarization. Token-billed. | Long-file feature candidate, with the same URL and result lifecycle. |

The [Qwen-Audio-ASR HTTP API](https://www.alibabacloud.com/help/en/model-studio/qwen-audio-asr-http-api) documents language_hints values en and ko, context, and hot words. With 3.1 speaker diarization enabled, the API says language_hints are ignored. The [Qwen3-ASR API](https://www.alibabacloud.com/help/en/model-studio/qwen-asr-api-reference) uses a single language setting with en or ko; omit it when speech is mixed or uncertain, as the provider advises. Store the user's en-US/ko-KR selection separately from the provider's en/ko API value. Context is recognition guidance, not an instruction to rewrite the diary.

Real-time models use WebSocket audio streaming, while the app records a complete file and processes it only while open. For comparison, `qwen3-asr-flash-realtime` supports English/Korean and mono PCM/Opus at 8 or 16 kHz; Qwen-Audio 3.0/3.1 streaming variants support mono binary audio. The [real-time specifications](https://docs.qwencloud.com/developer-guides/speech/speech-to-text-models) do not describe direct submission of an archived .m4a file. They add a protocol and possible transcoding without satisfying the current recording workflow.

### Published recognition quality

The provider's [Qwen-Audio-3.1-ASR technical report](https://arxiv.org/html/2610.28711) compares the 3.0 and 3.1 model families on public datasets, not this app's hosted endpoints or diary recordings. Its Korean character error rates improve from 13.50% to 7.98% on GigaSpeechBench, 3.09% to 0.73% on Common Voice 15, and 4.94% to 2.38% on FLEURS. English results are mixed: 3.1 has 4.72% versus 3.0's 4.17% word error rate on FLEURS-en, and 2.19% versus 2.24% on LibriSpeech-other. The report cautions that some published baseline results use different preprocessing and scoring conventions. These results make 3.1 a strong Korean quality candidate, but do not establish its accuracy or value for the app's recordings; measure both hosted models on matched diary-like clips.

## Regional pay-as-you-go prices

The [Model Studio pricing table](https://www.alibabacloud.com/help/en/model-studio/model-pricing), last updated 2026-10-29, publishes these USD list prices. The five-minute column assumes exactly 300 billable seconds, one successful request, no discounts, and no ancillary storage/network charges. Token-priced 3.1 costs cannot be converted to a per-recording figure without measured input/output token counts.

| Model | Singapore | Beijing | Estimated 300-second cost |
|---|---:|---:|---:|
| `qwen-audio-3.0-asr-flash` | $0.000035/sec | $0.000030/sec | SG $0.0105; BJ $0.0090 |
| `qwen3-asr-flash` | $0.000035/sec | $0.000032/sec | SG $0.0105; BJ $0.0096 |
| `qwen-audio-3.0-asr-flash-filetrans` | $0.000035/sec | $0.000032/sec | SG $0.0105; BJ $0.0096 |
| `qwen3-asr-flash-filetrans` | $0.000035/sec | $0.000032/sec | SG $0.0105; BJ $0.0096 |
| `qwen-audio-3.1-asr-flash` and `-filetrans` | $0.15/M input tokens + $0.47/M output tokens | $0.113/M input tokens + $0.382/M output tokens | Unknown until token usage is measured |
| `qwen3-asr-flash-realtime` | $0.000090/sec | $0.000047/sec | SG $0.0270; BJ $0.0141 |
| `qwen-audio-3.1-asr-flash-streaming` | $0.93/M input tokens + $0.70/M output tokens | $0.848/M input tokens + $0.636/M output tokens | Unknown until token usage is measured |

For 3.1 file transcription, compute charge from the API's reported input and output token counts and the chosen region's rates. The [Qwen-Audio-ASR API](https://www.alibabacloud.com/help/en/model-studio/qwen-audio-asr-http-api) exposes those counts. QwenCloud's generic pricing guide says ASR is duration-billed, but its [model-price reference](https://docs.qwencloud.com/developer-guides/getting-started/model-prices) and the regional Model Studio table explicitly price the 3.1 ASR variants by token; use the model-specific rule. Do not assume an account has a free quota or that a Token Plan key uses these pay-as-you-go rates.

## Provisional recommendation

For **affordability with direct .m4a input**, use `qwen-audio-3.0-asr-flash` as the historical research baseline. At list price, a five-minute request is approximately $0.0105 in Singapore or $0.0090 in Beijing. It avoids the short Qwen3 model's undocumented .m4a path and the long-file models' public-URL task lifecycle. For **potential quality and richer controls**, compare `qwen-audio-3.1-asr-flash` on the same recordings, with polishing off when measuring transcription accuracy. The published Korean results favor 3.1, while English results are mixed; no project-specific en-US/ko-KR head-to-head result or per-recording token bill is available here. A recommendation to promote it must wait for an actual quality-and-cost test. Hosted Qwen is outside v1, and the current product keeps only the managed diary text, without a transcript sidecar. See the [audio-format research](p1-m1-audio-format.md) for the provisional iPhone recording baseline.

Use consented or synthetic diary-like recordings with manually checked references, balanced between en-US and ko-KR. Include names, dates, pauses, quiet speech, noise, mixed-language speech, and several durations. Report English word error rate and Korean character error rate with a stated normalization policy, plus human review of omissions, names, numbers, and polishing changes. Submit matched audio to both regions and record model version, hint/context, input/output tokens or billed seconds, latency, failures, and actual charge. Set acceptance thresholds before choosing a production model.

## Integration, privacy, and unresolved questions

The owner chose user-supplied Qwen API keys and a user-visible Beijing/Singapore region choice. The provider documents [region-specific keys and workspace endpoints](https://www.alibabacloud.com/help/en/model-studio/qwen-audio-asr-http-api). A key must be protected on device and excluded from logs; P1-M2 still needs to settle secure storage, revocation, and how the app avoids exposing a reusable key. The selected model, region, hint, context, and effective settings when processing starts must be recorded as provenance.

Short-file APIs accept a URL or Base64 audio Data URI. A local iPhone path is not reachable by the remote service; some SDK examples treat local paths as a convenience and encode the file. Long-file APIs require a provider-accessible URL, asynchronous task polling, and prompt retrieval of a result URL that the [provider says expires after 24 hours by default](https://www.alibabacloud.com/help/en/model-studio/non-realtime-speech-recognition-user-guide). Base64 inflates request size. Do not expose an iCloud diary folder publicly to satisfy a provider URL; design a temporary transfer path if required.

Diary recordings and transcripts are sensitive. The [International Site retention policy](https://www.alibabacloud.com/help/en/model-studio/data-retention-policy) gives default retention and separate stateful-file/async-task conditions, but it does not settle the applicable Beijing account terms or prove data residency. Confirm current contractual processing, logging, deletion, and regional rules before implementation. Open-weight Qwen3-ASR [research](https://arxiv.org/abs/2601.21337) reports Apache-2.0 weights, but this does not govern the hosted service or make on-device inference feasible on the target iPhone.

P1-M2 still needs to verify direct .m4a submission for 3.0/3.1, exact supported context controls, actual en-US/ko-KR quality, 3.1 token usage, account-region availability, and privacy terms. This research approves no model or dependency.

**Pricing note:** All figures are estimates from published pay-as-you-go list rates, not a bill quote. Actual charges depend on measured usage, account terms, discounts, and billing changes. Do not assume a free quota; verify the current [model pricing](https://www.alibabacloud.com/help/en/model-studio/model-pricing), [QwenCloud benefits](https://home.qwencloud.com/benefits), and [pay-as-you-go bill](https://home.qwencloud.com/billing/pay-as-you-go).
