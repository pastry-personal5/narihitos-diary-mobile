# P1-M18: Open-Meteo research record

Status: Recorded 2026-11-11

Evidence for the owner's choice of Open-Meteo as the M18b weather source. The [approach](milestone-18-context-reminders-architecture.md#open-meteo-terms-verified-2026-11-11) holds the design rules derived from it. Re-check the live pages before implementation and before any public release; Open-Meteo may change its terms at any time without notice.

## Sources

Read on 2026-11-11: [terms](https://open-meteo.com/en/terms), [pricing](https://open-meteo.com/en/pricing), [docs](https://open-meteo.com/en/docs) and [licence](https://open-meteo.com/en/licence). Not read: the status page, the model-update schedule, and the Creative Commons non-commercial definition that the terms cite. WeatherKit facts (paid Apple Developer Program membership needed; 500,000 free calls per month per membership) come from search results, not from Apple's pages.

## What the pages state

| Topic | Finding |
|---|---|
| Permitted use | Free API for non-commercial purposes only. Non-commercial examples: private or non-profit apps without subscriptions or advertising, personal home automation, voluntary donations. Commercial examples: apps with subscriptions or ads, commercial products or promotion. |
| Limits | Under 10,000 calls/day, 5,000/hour and 600/minute; the pricing table adds 300,000/month. Applied per IP address and application. One request is usually one call; more than 10 variables or more than two weeks for a location count as several. The service may block misuse without notice. |
| Key | None for the free endpoint; `apikey` is for paid customers on a separate endpoint. |
| Attribution | CC BY 4.0: appropriate credit, a link to the licence, and an indication of changes. A link must appear next to displayed data, for example "Weather data by Open-Meteo.com" linking to `https://open-meteo.com/`. Required even for commercial use. |
| Privacy | IP addresses may be collected for maintenance and misuse prevention. Web-server logs may contain coordinates, are not shared with third parties, and are deleted after 90 days. The website sets no cookies. |
| Reliability | No uptime guarantee and no warranty on the free tier; paid plans target 99.9%. |
| `current` | `current=temperature_2m,weather_code` is supported. The pages call it "based on 15-minutely weather model data"; no refresh cadence is stated. |
| `time` | Default ISO 8601 strings are local times without an offset, with `utc_offset_seconds` separate. `timeformat=unixtime` returns UTC seconds. The default timezone is GMT. |
| Weather codes | The API returns numeric WMO codes only; the docs supply the mapping. Codes 96 and 99 appear only for models with a hail forecast. |

## Inferences (not stated by the pages)

- A free, ad-free, subscription-free personal app fits the non-commercial examples. The pages do not mention App Store distribution, and "private" is ambiguous for a public release.
- Shared carrier or NAT addresses could reach the per-IP limits sooner than the app's own call count suggests.
- `current` is model-derived, not a station observation, so the stored `weather_observed_at` is a model validity time.

## Decisions this supports

- Request exactly two variables with `timeformat=unixtime`, send coordinates rounded to two decimals, and treat HTTP 429 or any failure as an omission with no retry loop.
- Weather sits behind its own default-Off Settings toggle whose disclosure names the IP address and the 90-day logs.
- Display the Open-Meteo attribution link beside any displayed weather; show no weather without it.

## Open items

- Obtain written confirmation from Open-Meteo, using the contact address on its site, before any public or App Store release.
- Revisit the choice if the app gains ads, subscriptions or other monetization, or if the terms change.
- Verify the status page and model refresh behavior during M18-D03 on the target phone.
