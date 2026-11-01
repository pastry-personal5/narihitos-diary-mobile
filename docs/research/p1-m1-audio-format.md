# P1-M1: iPhone recording format and Qwen input research

Status: Active

This research compares iPhone recording output with the Qwen file-transcription inputs relevant to five-minute English and Korean diary clips. It gives a provisional recording baseline for P1-M2, not an approved codec or provider decision. Sources and example-asset metadata were checked on 2026-11-01.

## iPhone output choices

Apple's [AVAudioRecorder settings reference](https://developer.apple.com/documentation/avfaudio/avaudiorecorder/init%28url%3Asettings%3A%29-5whyq) lists linear PCM, AAC-LC, Apple Lossless, IMA4, iLBC, and µ-law as recorder formats. It accepts sample-rate settings from 8 to 192 kHz and channel-count settings from 1 to 64; these are API ranges, not a guarantee that every codec/rate/channel combination works on every iPhone route. [Format settings](https://developer.apple.com/documentation/avfoundation/format-settings) identify the sample-rate and channel keys, and [encoder settings](https://developer.apple.com/documentation/avfaudio/avencoderbitratekey) include bitrate control. Apple's [audio-session guidance](https://developer.apple.com/documentation/avfaudio/avaudiosession/preferredsamplerate) distinguishes a preferred hardware sample rate from the actual rate after session activation.

The owner's 24 example audio files were inspected with afinfo without decoding speech. All are mono AAC in .m4a at 44,100 Hz; measured encoded bitrates range from 55.4 to 64.3 kb/s. The clips are 3.6 to 33.7 seconds long. This is evidence of an existing file convention, not proof that those settings maximize recognition accuracy on iPhone 17 Pro Max.

| Candidate output | Approximate five-minute audio payload | Practical effect |
|---|---:|---|
| Mono AAC-LC in .m4a at 64 kb/s | 2.4 MB | Small archive and upload; lossy compression. Matches the example convention and is listed as a direct input for Qwen-Audio 3.0/3.1 Flash. |
| Mono 16-bit PCM at 16 kHz | 9.6 MB | No codec loss, but roughly four times the upload/storage of AAC. Near Qwen3-ASR-Flash's 10 MB short-file limit before Base64 expansion. |
| Mono 16-bit PCM at 44.1 kHz | 26.5 MB | No codec loss but much larger; exceeds that Qwen3 short-file limit. |

These are payload estimates from duration × bitrate or sample rate × bit depth × channels, excluding container overhead. Base64 grows binary audio by roughly one third, so a five-minute 16 kHz PCM file is not a safe inline choice for a 10 MB request limit. Codec bitrate chiefly affects storage and transfer size; Qwen's duration-billed models charge by audio seconds, while Qwen-Audio 3.1 charges by input and output tokens. See [regional prices](p1-m1-qwen-transcription.md#regional-pay-as-you-go-prices).

## Qwen input compatibility

The provider's [speech-to-text audio specifications](https://docs.qwencloud.com/developer-guides/speech/speech-to-text-models) list the following inputs. A file extension alone is insufficient: the recorded container and codec must match, and the chosen API must be tested with an actual iPhone file.

| Model/API | .m4a listed? | Sample rate and input path | Limit |
|---|---|---|---|
| Qwen-Audio 3.0/3.1 ASR Flash | Yes | Any sample rate; one URL or Base64 file per request | Five minutes, 2 GB |
| Qwen3-ASR-Flash | **No** in the current format table | Non-PCM formats at any rate are resampled server-side to 16 kHz; URL or Base64 for HTTP, with local path supported by some SDK calls | Five minutes, 10 MB |
| Qwen3-ASR-Flash-Filetrans | Yes | Any non-PCM sample rate; public file URL and asynchronous result retrieval | Twelve hours, 2 GB |
| Qwen-Audio 3.0/3.1 ASR Flash-Filetrans | Yes | Any sample rate; public file URL and asynchronous result retrieval | Twelve hours, 2 GB |

The short Qwen3-ASR-Flash list includes raw AAC but omits the .m4a container, while its filetrans variant explicitly lists .m4a. Do not assume a .m4a file works with the short API. Avoid transcoding AAC to another lossy codec merely to use that API; it cannot restore detail already lost in AAC and adds complexity. A lossless/PCM conversion may satisfy an API format check but increases upload size without restoring the original signal. The [Qwen3 API reference](https://www.alibabacloud.com/help/en/model-studio/qwen-asr-api-reference) also warns that Base64 expansion counts toward the input-size limit.

Real-time Qwen ASR uses a binary audio stream, not a completed .m4a file. The [real-time format table](https://docs.qwencloud.com/developer-guides/speech/speech-to-text-models) requires mono input and lists PCM/Opus at 8 or 16 kHz for Qwen3-ASR-Flash-Realtime. The v1 queue transcribes after recording while the app is open, so real-time protocols add work without meeting a current v1 requirement.

## Provisional recommendation and validation

Start the P1-M2 prototype with **mono AAC-LC in .m4a, 44.1 kHz, approximately 64 kb/s**. It matches every example asset, is directly listed for the short Qwen-Audio 3.0/3.1 APIs, and keeps a five-minute file around 2.4 MB before container overhead. This is a starting setting for storage and integration, not a measured ASR optimum. Use a slightly shorter stop threshold if needed to ensure the finalized file stays within the provider's five-minute limit.

On the target iPhone, record the same consented English and Korean speech once in an uncompressed capture and derive matched AAC variants at 64 and 96 kb/s, plus a 16 kHz PCM comparison. Record the actual codec, encoded sample rate, hardware route/sample rate, channel count, duration, and byte size. Submit identical speech to each candidate model and compare English word error rate, Korean character error rate, names, numbers, omissions, and replay quality. If 64 kb/s harms recognition, raise bitrate before changing the asset container. No such quality experiment has been run yet.
