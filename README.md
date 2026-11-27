<div align="center">
  <img src="https://github.com/YangJiiii/EnsWilde/blob/be10a7d93b70df3b40057f869e6cc82de92bc2f0/MyApp_Dark_1024.png?raw=true" width="120" alt="EnsWilde Logo" />
</div>

# EnsWilde (Mobile)
  <p align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS%20%7C%20iPadOS-27-000000?style=flat-square&logo=apple&logoColor=white" alt="Platform">
  <img alt="Swift" src="https://img.shields.io/badge/swift-%23F54A2A.svg?style=for-the-badge&logo=swift&logoColor=white">
</p>

**EnsWilde** is a an on-device customization tool for iPhone and iPad running iOS/iPadOS 26.0 – 27.3 Beta 1, powered by the `worse_query` and `AirLift` exploits. Once configured, it functions completely standalone without needing a computer (a PC is only required during initial setup on iOS 26).

> [!WARNING]
> **DISCLAIMER:**
> I am **not responsible** or any bootloops, bricked devices, or data loss. Use this utility at your own risk.  
> **Always back up your device before proceeding!**

---
## Exploits & Compatibility
* **worse_query: Supports iOS 27.0-27.3 Beta 1.**
* **AirLift: Supports iOS 26.0-27.2 Beta 2 (Build 24B5089g).**

---

## Features
* **Apple Wallet Customization:** Change background images for Wallet passes and cards
* **MobileGestalt Editor (for advanced users):** Tweak hidden system properties and configuration keys.
* **Passcode Keypad Theming:** Customize your lock screen and dialer numpad with custom `.passthm` themes.
* **Disable Call Recording Announcement:** Mute the "This call is being recorded" audio prompt.
*More features in active development!*

---

## Preview

<p align="center">
  <img src="assets/IMG_0209.png" width="245" alt="EnsWilde 3.1.3 Beta 2 Home">
  &nbsp;
  <img src="assets/IMG_0212.png" width="245" alt="EnsWilde 3.1.3 Beta 2 2.0 Setting">
  &nbsp;
  <img src="assets/IMG_0213.png" width="245" alt="EnsWilde 3.1.3 Beta 2 About">
</p>

---

## Setting Airlift
1. Download **LocalDevVPN** from the App Store.
2. Open the app and toggle the VPN.
3. Launch **EnsWilde** and navigate to **Settings**.
4. Import your Pairing File:
   - **iOS 26:** Generate and retrieve the pairing file via PC using `iloader`.
   - **iOS 27:** Dump the pairing file directly on-device using `StikPair` *(direct in-app pairing for iOS 27 coming soon)*.

## ⚠️ Important Prerequisites
1. **App Groups Entitlement:** `worse_query` requires App Groups to function. You must sign the app with a certificate that supports the App Group entitlement; otherwise, `MobileGestalt` modifications will not work.
2. **Need a signing certificate?** You can grab one at [Cert YangJiii](https://cc.dangdi.dev).
---

## Credits & Acknowledgments

Special thanks to everyone who made this project possible:

* **YangJiii**: [original developer of EnsWilde](https://github.com/yangjiiii/EnsWilde), and for guiding development.
* **@forcequitOS**: [for `worse_query`](https://github.com/forcequitOS/worse_query/)
* **0xjohnnydev**: [for `AirLift`](https://github.com/0xjohnnydev/airlift)
* **mak5er**: [for the on-device AirLift implementation](https://github.com/Mak5er/AirCard-iOS)
* **@StikDebug team**: [for `StikPair`](https://github.com/StikDebug)
* **DeepSeek**: AI assistance during development
