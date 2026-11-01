# P1-M1: Qwen transcription research

Status: Active

This research compares Qwen-based transcription for English (en-US) and Korean (ko-KR) diary recordings. It is an input to P1-M2, not a provider or architecture decision. Sources were checked on 2026-11-01; service offerings and terms can change.

## Findings

| Option | Suitability and constraints |
|---|---|
| `qwen3-asr-flash` | A useful baseline for short recorded clips: HTTP, at most 5 minutes and 10 MB per file. English and Korean are supported. |
| `qwen3-asr-flash-filetrans` | Asynchronous file jobs for longer recordings, up to 12 hours and 2 GB per file. Submit, poll, and retrieve results; assess storage and result expiration. |
| `qwen-audio-3.1-asr-flash` and `qwen-audio-3.1-asr-flash-filetrans` | Newer short-file and asynchronous long-file alternatives supporting English and Korean. The former allows up to 5 minutes and 2 GB, the latter 12 hours and 2 GB. Compare quality, cost, and privacy with Qwen3 rather than assuming a winner. |
| Qwen3-ASR open weights | The [Qwen research report](https://arxiv.org/abs/2601.21337) describes 0.6B and 1.7B models under Apache-2.0. Self-hosting or on-device inference warrants a separate feasibility study of iPhone memory, speed, battery, model distribution and runtime licensing. These open weights are distinct from the hosted model IDs above. |

Alibaba lists these hosted options in both [Beijing and Singapore](https://www.alibabacloud.com/help/en/model-studio/non-realtime-speech-recognition-user-guide); its [model overview](https://www.alibabacloud.com/help/en/model-studio/asr-model/) lists English and Korean support. These are language-level claims, not guarantees of en-US accent or ko-KR accuracy. No recording or transcription experiment was performed.

For `qwen3-asr-flash`, the [API reference](https://www.alibabacloud.com/help/en/model-studio/qwen-asr-api-reference) specifies `en` and `ko`, rather than locale codes. If a recording is known to be in one language, a language hint may help; omit it for mixed or uncertain speech, as instructed by the provider. Test code-switching even though the supported product languages are restricted to English and Korean.

## Regions and integration

The owner's preference is Beijing while in mainland China; Singapore is the other region under consideration. The provider documents region-specific API keys and workspace endpoints: `{WorkspaceId}.cn-beijing.maas.aliyuncs.com` and `{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com` respectively. See the [API reference](https://www.alibabacloud.com/help/en/model-studio/qwen-asr-api-reference). Region selection, switching, account eligibility, network reachability and latency require an actual account and device tests. The endpoint alone does not establish data residency or cross-border transfer guarantees; confirm contractual processing, storage, logging and support locations for each region.

For short audio, the API documents URL or Base64 inputs; SDK-local paths are SDK conveniences, not paths the remote service can access. For long audio, asynchronous file transcription requires a provider-accessible audio location and task polling; verify supported URL schemes, expiration, upload/result handling and file deletion for the exact chosen API. Avoid embedding a long-lived provider API key in an iOS app; assess a credential-mediating backend and secure upload in P1-M2. These are integration considerations, not approved architecture.

The app's actual recording container, codec, sample rate, channel count, maximum length and offline behavior are not yet specified. Verify each against the chosen model's current API documentation and test real iPhone-generated files; a `.m4a` extension alone does not prove compatible encoding. If conversion or splitting is needed, evaluate loss of quality, file size, upload cost, boundaries and retry behavior. The [provider guide](https://www.alibabacloud.com/help/en/model-studio/non-realtime-speech-recognition-user-guide) documents limits and timestamp options; do not assume every variant offers identical controls.

## Privacy, cost and licensing

Diary speech and transcripts are sensitive. Review explicit user consent, encryption in transit and at rest, access controls, logging redaction, retention and deletion for the audio, transcript, temporary URLs, task results and any intermediary backend. According to the [International Site retention policy](https://www.alibabacloud.com/help/en/model-studio/data-retention-policy), ordinary inference prompts and responses are retained for no longer than 30 days by default, subject to stated exceptions; stateful files have separate rules. Enterprise zero data retention is conditional on eligibility, workspace and supported model; asynchronous task management is excluded. The policy's supported list includes the 3.1 audio ASR family, but that does not make asynchronous file jobs zero-retention. Verify the applicable account, site, region, and service terms before relying on these statements; no legal or data-residency conclusion is implied.

The [pricing page](https://www.alibabacloud.com/help/en/model-studio/model-pricing) distinguishes duration-billed Qwen3-ASR from token-billed newer variants and lists regional rates. Estimate using actual duration, retries, storage, networking and any backend costs; Token Plan credits are not equivalent to pay-as-you-go rates. Account entitlements and current exact charges were not verified: the installed QwenCloud CLI requires authentication. Check the relevant Model Studio console and contract for regional pricing, available quotas and billing terms.

Open-weight Apache-2.0 terms do not automatically govern hosted service use; review the service agreement and any runtime, model-weight and third-party license notices separately before adopting dependencies. No dependency is approved by this research.

## Evaluation and P1-M2 questions

Use consented or synthetic diary-like test recordings with manually checked references, balanced between en-US and ko-KR and including mixed speech, names, dates, pauses, quiet speech, noise, varying duration and common iPhone conditions. Report English word error rate and Korean character error rate with a documented normalization policy, alongside human review of names, numbers, omissions, hallucinations and code-switching. Compare identical audio and references across candidates and regions; record model version, hint, configuration, duration, latency, failure rate and cost. Agree acceptance thresholds before selecting a provider. Do not upload real private diaries without appropriate consent.

P1-M2 should resolve: expected recording duration and format; online/offline requirements; whether mixed-language entries are expected; user-visible region selection and consent; account and regional data rules; credential management; asynchronous storage and deletion; cost limits; quality and latency targets; and whether on-device inference is practical. Confirm provider feature availability and current terms before any implementation decision.
