# Device and release acceptance — not yet executed

Use two physical phones, two confirmed test accounts and paired Bluetooth headsets. Run an
Android↔Android, iOS↔iOS and Android↔iOS matrix. Record OS, device, headset, provider model,
language pair, network, timestamp, latency and pass/fail. Do not retain speech without consent.

| Scenario | Required evidence |
| --- | --- |
| Two users create/join | Host creates, partner joins via code and QR; both names/languages appear |
| Invalid/reused code | Both are rejected without revealing room metadata |
| Capacity/race | Two concurrent joins yield one admission; third user cannot read the room |
| Two-way translation | At least 20 reference phrases each direction; bilingual meaning assessment |
| Uzbek | Explicit experimental configuration; native speakers assess STT, translation and TTS separately |
| Provider outage | Safe visible error, no secrets in response/log; user can retry |
| Quota exhausted | New session and next turn blocked; concurrent turns cannot overspend |
| Network drop | Microphone stops on timeout; no replay; explicit fresh-ticket reconnect |
| Partner offline | No provider call or usage charge until partner is connected |
| Headset disconnect | Capture/playback pause; no private audio silently sent to speaker |
| Audio focus / phone call | Translation pauses and microphone stops |
| Background / lock screen | Audio stops, no hidden recording; explicit reconnect after resume |
| Simultaneous speaking | Both directions translate; playback waits while local microphone records |
| Speaker feedback | Measure echo; do not approve loudspeaker support if repeated translation occurs |
| Expiry / end / deletion | Both sockets stop and no late provider audio is delivered |
| Long conversation | 45–60 minutes; measure memory, battery, audio focus and five-minute reconnects |
| Accessibility | Screen reader labels, large fonts, contrast, tap targets, landscape and narrow screens |
| Secrets | Scan source/build/logs for actual server keys, not only key names |
| Privacy | Denying processing consent disables connection; leaving clears transcript; deletion removes data |

Before store submission: signed release builds, custom app IDs/icons, verified auth callbacks or
universal/app links, password policy, SMTP and Auth CAPTCHA/rate limits, privacy policy and consent,
OpenAI AI-voice disclosure, Google Play Data Safety and App Store privacy labels, microphone/camera
purpose strings, in-app account deletion, real billing integration before enabling checkout,
crash telemetry with strict redaction, incident response, RLS tests and penetration review.
