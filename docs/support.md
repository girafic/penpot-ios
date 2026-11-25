---
title: Support
permalink: /support/
---

# Support

**Viewer for Penpot** lets you browse, review and comment on Penpot design files on your
iPhone. [Deutsch]({{ '/de/support/' | relative_url }})

**[Get it on the App Store](https://apps.apple.com/app/id6838299207)**

## Requirements

- An iPhone with iOS 17 or later.
- A Penpot account, either on `design.penpot.app` or on a self-hosted Penpot server.
  Penpot is free and open source; you can create an account at
  [penpot.app](https://penpot.app).

## Questions and answers

**Can I edit designs in the app?**
No. The app is for viewing, reviewing and commenting. To draw or edit, use Penpot on a
computer. Everything around the design can be changed in the app, though: files, projects,
team members, fonts, versions and share links.

**How do I use my own Penpot server?**
On the login screen, enter your server's address in the "Penpot server" field, for example
`https://penpot.example.com`. Servers without HTTPS work too.

**I can't sign up or reset my password in the app.**
On `design.penpot.app`, Penpot protects these pages with a browser check. The app then
opens Penpot's website, where you can finish signing up or resetting your password. After
that, log in in the app.

**A board looks different than in Penpot.**
The app draws boards on your iPhone from the file's data, following Penpot's own renderer.
A few effects aren't supported yet, such as arrowheads on lines. Please report the
difference with a screenshot (see Contact below). Settings → About → **Clear image cache**
draws every board again.

**Exporting a board as an image fails.**
Exporting PNG, JPEG, WebP, SVG or PDF uses the export service of your Penpot server.
Self-hosted servers don't always run it. Viewing boards doesn't need it.

**Why does the comments inbox show only unread threads?**
Penpot only lists unread threads across a whole team. Open a file to see all of its
comments, including the read and resolved ones.

**Some features are missing on my self-hosted server.**
Some features need a recent Penpot version:
- import: 1.15;
- templates: 1.19;
- version history: 2.4;
- @mentions: 2.7;
- "Recently Deleted": 2.12;
- font upload: 2.17.

**How do I delete my account?**
Settings → Profile → **Delete Account**. This deletes your Penpot account on the server
you are signed in to. See also the [Privacy Policy]({{ '/privacy/' | relative_url }}).

**Which languages does the app support?**
The same 34 languages as Penpot. You can change the language on the login screen or in
Settings → Appearance.

## Contact

Report problems and ideas at
[github.com/girafic/penpot-ios/issues](https://github.com/girafic/penpot-ios/issues).
Please include your iPhone model, your iOS version, the app version (Settings → About)
and whether you use `design.penpot.app` or your own server.

For questions about your Penpot account or `design.penpot.app` itself, contact
Penpot at [help.penpot.app](https://help.penpot.app).

Viewer for Penpot is an independent app. It is not made by, affiliated with or endorsed
by Kaleidos, the company behind Penpot. "Penpot" is a trademark of Kaleidos.
