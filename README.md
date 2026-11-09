<p align="center">
  <img src="GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="GestaltX" width="112" height="112">
</p>

<h1 align="center">GestaltX</h1>

[![Version](https://img.shields.io/badge/version-1.0.2-blue)](https://github.com/huamidev/GestaltX)
[![Platform](https://img.shields.io/badge/iOS-27.x-black?logo=apple)](#compatibility)
[![SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)](https://github.com/huamidev/GestaltX)
[![License](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

[English](README.md) · [简体中文](README_ZH-CN.md)

A MobileGestalt editor for iPhone and iPad. Developed by [huamidev](https://github.com/huamidev).

## Features

| Category | Presets and tools |
| --- | --- |
| Display | Dynamic Island capability and layout, Always-On Display, AOD Vibrancy, Liquid Glass low-power rendering |
| Device | Model name, boot/shutdown chime, charge limit, tap to wake, Camera Control settings, Action Button settings, build-specific FaceTime Audio preset |
| iPad | Apple Pencil settings, Stage Manager capability, iPad app compatibility |
| Intelligence | Independent region-code options, Apple Intelligence capability flag, and sales-region options for activation attempts on China-mainland devices |
| Advanced | Apple internal feature flags, internal storage view, Security Research Device flag |
| Field editor | Read, search, add, edit, and remove `CacheExtra` fields; local plist import/export; String, Integer, Real, Boolean, Data, Date, Array, and Dictionary values |
| Changes | Automatic reading and manual re-read, staged before/after review, verified writes, per-preset restore |
| Backups | Automatic initial backup before device editing, backup before every write, original-value records; open, export, restore, and delete |
| Logs & respring | Actual exploit-stage logs and manual NeoSpring respring |

Usually, changing the region code is enough to try enabling AI; there is no need to change Sales Region. Selecting United States for Region Code sets `RegionCode` to `LL` and keeps the sales-region suffix. You can also choose China (Mainland), Hong Kong, Taiwan, Japan or the United Kingdom. Sales Region and Region Code can be applied together: the sales suffix follows Sales Region, while the code follows Region Code.

*If you previously changed Sales Region, restore your device’s original sales region and apply it first.*

Disabling a preset or using its Revert button restores the recorded original values and types. Keys that were originally absent are removed. If an older change has no original record, use Remove Added Fields only when you know those fields were added.

Presets modify capability flags; actual effects depend on the device and OS. China-mainland devices can use the Apple Intelligence and region options to attempt activation; availability also depends on the model, OS version, and Apple services.

## Compatibility

Supports **iOS / iPadOS 27.x**. **iOS / iPadOS 26.x is not supported for on-device MobileGestalt access.** Powered by [worse_query](https://github.com/forcequitOS/worse_query). SystemGroup access requires iOS 27; available features depend on the device and OS. Local plist editing is also supported.

Signing requires a certificate and provisioning profile with at least one usable App Group. GestaltX detects the signed App Group at runtime.

## FaceTime Audio

Device → Presets includes a FaceTime Audio option for **iPhone 17 Pro (iPhone18,1), iOS 27.3 / 24C5037i**. It validates the model, build and cache layout before staging the two cache flags. Review the before/after values, apply, and restart the iPhone. The matching device owner confirmed FaceTime Audio works after applying the changes.

On-device original values are saved before applying. Use **Revert** to restore only these two flags, including after reopening the app. Previously modified devices use their earliest recorded values, not an assumed factory default.

Original idea: [KirbySD's V2EX post](https://www.v2ex.com/t/1246550).

## Language support

GestaltX follows your iOS language settings, with English as the default and fallback. Persian includes right-to-left layout support.

| Language | Locale |
| --- | --- |
| English | `en` |
| 简体中文 — Simplified Chinese | `zh-Hans` |
| 繁體中文（台灣）— Traditional Chinese (Taiwan) | `zh-Hant-TW` |
| 繁體中文（香港）— Traditional Chinese (Hong Kong) | `zh-Hant-HK` |
| Tiếng Việt — Vietnamese | `vi` |
| Русский — Russian | `ru` |
| فارسی — Persian | `fa` |

## Credits

- [forcequitOS / Taj C — worse_query](https://github.com/forcequitOS/worse_query)
- [neonmodder123](https://github.com/neonmodder123)
- [skadz108](https://github.com/skadz108)
- [rooootdev — NeoSpring](https://github.com/rooootdev/neospring)
- [Nouvborne — Ketamine](https://github.com/Nouvborne/Ketamine)
- [PoomSmart — MGKeys](https://github.com/PoomSmart/MGKeys)
- [leminlimez — Nugget](https://github.com/leminlimez/Nugget)
- [rooootdev — mond](https://github.com/rooootdev/mond)
- [frs0n — GestaltEdit](https://github.com/frs0n/GestaltEdit)

## Disclaimer

For security research and educational purposes only. Use only on devices you own or are authorized to manage.

Back up your data before making changes. Modifying MobileGestalt may cause system instability or require a device restore. You are responsible for the changes you apply and the resulting risks.

## License

[GNU GPL v3](LICENSE) · Copyright © 2026 huamidev.
