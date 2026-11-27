---
title: Privacy Policy
permalink: /privacy/
---

# Privacy Policy

**Viewer for Penpot.** Last updated: 27 November 2026.
[Deutsche Fassung]({{ '/de/datenschutz/' | relative_url }})

## Summary

The developer of Viewer for Penpot does not collect, store or share any of your personal
data. The app contains no analytics, no advertising, no tracking and no crash reporting.
It connects only to the Penpot servers you sign in to, and, for designs set in Google
Fonts, to Google's font servers (see [Fonts in designs](#fonts-in-designs)).

## Who makes this app

Viewer for Penpot is an independent app by an individual developer, who is named as the
seller on the App Store. It is not made by or affiliated with Kaleidos, the company that
develops Penpot and runs `design.penpot.app`. The source code is public at
[github.com/girafic/penpot-ios](https://github.com/girafic/penpot-ios), so you can check
everything this policy says.

## The Penpot server you sign in to

The app is a client for Penpot. When you sign in, it connects directly to the server you
choose on the login screen: either `design.penpot.app`, which Kaleidos runs, or a
self-hosted Penpot server.

That server receives and stores everything you do in the app, such as:
- your sign-in;
- your profile;
- your teams, projects and files;
- your comments, invitations and share links;
- fonts, pictures and files you upload.

Like any server you connect to, it also sees technical data such as your IP address. All
of this is governed by the privacy policy of whoever runs the server. For
`design.penpot.app`, that is [Penpot's privacy policy](https://penpot.app/privacy-policy).
The developer of this app has no access to any of it.

Two screens show Penpot's own web app inside the app: "Open live canvas" and, from the
prototype player's menu, "Open in Penpot's view mode". These pages come from the same server and work as they would in a browser. They
may store cookies and website data on your device and load resources that the server's
operator has chosen.

## Fonts in designs

The app draws designs on your device the way Penpot does, in the fonts they use. Fonts
from Google Fonts, which Penpot offers in its editor, are loaded the way Penpot's own web
app loads them: the list of font files comes from your Penpot server, the files themselves
from Google's font servers (`fonts.gstatic.com`). Like any server, those see your IP
address; the app sends them nothing else. Google's privacy policy applies to them. Fonts
your team uploaded come from your Penpot server.

## Data stored on your device

- **Sessions:** Penpot's session token for each account you sign in to, kept in the iOS
  Keychain.
- **Accounts:** the server address and email address of each account you add, so you can
  switch between them without signing in again, and those of your last sign-in, so the
  login form is filled in for you next time.
- **Profiles:** the name and the ID of the profile picture of each account, so your
  accounts show before the server answers.
- **Settings:** your app preferences (appearance and language) and your last eight
  searches for each team.
- **Caches:** rendered boards, thumbnails, avatars, and the outline of files you opened
  (their pages, boards and names). The caches make files open faster and live in the
  app's cache folder.

None of this leaves your device, except what the app sends to your Penpot server to do
what you ask.

When you log out of an account (Settings → **Log Out**, or **Log Out** on one of your
other accounts there) or delete your account, the app forgets that account and deletes
all of this except the server address, the email address and your app preferences,
which fill in the login form next time:
- the account's session token;
- its cached profile;
- your recent searches;
- all caches;
- the cookies and website data of the screens that show Penpot's web app.

Your other accounts stay signed in. If the server ends your session, you are logged out too. The caches then stay, so they
are ready when you sign in again.

You can also delete data yourself:
- Settings → About → **Clear image cache** removes rendered boards, thumbnails and avatars
  at any time;
- iOS removes cache files when storage runs low;
- deleting the app removes all data it stored on your device.

## Photos and files

- **Saving to Photos:** the app only adds to your photo library when you export a board
  as an image and choose "Save Image" in the share sheet. It never reads your library.
- **Choosing a picture:** when you pick a new profile or team picture, iOS gives the app
  only the photo you picked. The app uploads it to your Penpot server.
- **Fonts and Penpot files:** fonts and `.penpot` files you choose to import are uploaded
  to your Penpot server.

## Deleting your account

Settings → Profile → **Delete Account** asks your Penpot server to delete your Penpot
account. What happens to your data then follows that server's rules.

## Changes

If this policy changes, the new version is published on this page, with a new date at
the top.

## Contact

For questions about this app, open an issue at
[github.com/girafic/penpot-ios/issues](https://github.com/girafic/penpot-ios/issues).

For questions about your Penpot account or the data stored on a Penpot server, contact
whoever runs that server. For `design.penpot.app`, that is Penpot's support at
[help.penpot.app](https://help.penpot.app).
