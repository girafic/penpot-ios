# App Store Connect

The listing text for **Viewer for Penpot**, one file per field and language. The layout is
the same as fastlane `deliver` uses (`deliver --metadata_path AppStore/metadata`), but
copying and pasting each file works just as well.

| File | Field | Limit |
| --- | --- | --- |
| `name.txt` | Name | 30 |
| `subtitle.txt` | Subtitle | 30 |
| `promotional_text.txt` | Promotional Text (can change without a review) | 170 |
| `description.txt` | Description | 4000 |
| `keywords.txt` | Keywords (comma-separated, no spaces needed) | 100 bytes |
| `support_url.txt`, `privacy_url.txt`, `marketing_url.txt` | URLs | — |

Languages: `en-US` (primary) and `de-DE`.

Rules for these texts:
- **Keywords** don't repeat words that are already in the name or subtitle; Apple indexes
  those anyway. They never name other apps or services (guideline 2.3.7).
- **No pricing words** ("free", "no in-app purchases") in the metadata, and **no link to
  Penpot's pricing, subscription or billing pages** (guideline 3.1.1).
- The description always ends with the **unofficial disclaimer** (guidelines 5.2.1 / 4.1).
- The app is a **viewer**: the texts never promise drawing or editing.

The support and privacy URLs are the GitHub Pages site in `docs/`. It has to be live
before you submit: Settings → Pages → Deploy from a branch → `main`, folder `/docs`.
The app links to the privacy policy too (Settings → About), as guideline 5.1.1 requires.

## Review information

- **Notes:** `review-notes.txt` (English, under the 4000-character limit).
- **Sign-in required:** yes. Use a demo account on `design.penpot.app` that has one team,
  one project and one file with a few boards, some comments and a prototype flow. Type
  its email and password into App Store Connect only. **Never put them in this repo.**
- **Contact:** your own name, phone number and email, again only in App Store Connect.

## Answers for App Store Connect

- **Category:** Graphics & Design (primary), Productivity (secondary).
- **Price:** free. **Availability:** all countries except China mainland, where an app
  needs an ICP filing.
- **EU Digital Services Act:**
  - Declare your trader status. Whether you are a trader is your own legal call.
  - A trader's name, address, phone number and email are shown on the EU store page.
- **App Privacy:**
  - **Data Not Collected.**
  - The developer receives no data.
  - The app talks only to the Penpot server the user chooses, and that server's
    operator is responsible for the data stored there (see `docs/privacy.md`).
  - This matches `Sources/PrivacyInfo.xcprivacy`, which declares no tracking and no
    collected data.
- **Age rating:**
  - Answer "None" for every content type.
  - **Unrestricted Web Access:** No. The web views only show the user's Penpot server,
    and there is no address bar.
  - **User-Generated Content:** Yes. Team members write comments that other members of
    the same private team can read.
  - **Messaging and Chat:** No.
  - **Advertising:** No.
- **Content rights:**
  - The app shows third-party content: the user's own designs, fetched through Penpot's
    public API.
  - Answer that you have the necessary rights.
  - Licenses:
    - Penpot's icons are Feather icons (MIT), and Penpot's code is MPL-2.0 (see
      `Scripts/penpot-icons-extra/NOTICE.md`);
    - Work Sans is under the SIL Open Font License (`Sources/Resources/Fonts/OFL.txt`).
- **Export compliance:** answered by `ITSAppUsesNonExemptEncryption: false` in the build.
- **Copyright:** `2026` and your name.
- **Version:** 1.0.0 (build 1), iPhone only.

## Screenshots

Required: **6.9" iPhone, 1320 × 2868** (portrait), 3–10 per language. Take them on the
iPhone 17 Pro Max Simulator with the demo account, so no real names or emails show.
Suggested set:
1. A page with its boards on the canvas.
2. A board in detail, zoomed in, with comment pins.
3. A comment thread with an @mention.
4. A prototype playing.
5. The team's files.
6. The same in dark mode.
