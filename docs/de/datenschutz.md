---
title: Datenschutzerklärung
permalink: /de/datenschutz/
---

# Datenschutzerklärung

**Viewer for Penpot.** Stand: 22. November 2026.
[English version]({{ '/privacy/' | relative_url }})

## Kurzfassung

Der Entwickler von Viewer for Penpot erhebt, speichert und teilt keine personenbezogenen
Daten von Ihnen. Die App enthält keine Analyse, keine Werbung, kein Tracking und keine
Absturzberichte. Sie verbindet sich nur mit dem Penpot-Server, bei dem Sie sich anmelden.

## Wer die App anbietet

Viewer for Penpot ist eine unabhängige App eines einzelnen Entwicklers. Er ist im App Store
als Anbieter genannt. Die App stammt nicht von Kaleidos, der Firma, die Penpot entwickelt
und `design.penpot.app` betreibt, und ist nicht mit ihr verbunden. Der Quellcode ist
öffentlich unter
[github.com/girafic/penpot-ios](https://github.com/girafic/penpot-ios). Dort können Sie
alles nachprüfen, was in dieser Erklärung steht.

## Der Penpot-Server, bei dem Sie sich anmelden

Die App ist ein Client für Penpot. Wenn Sie sich anmelden, verbindet sie sich direkt mit dem
Server, den Sie auf dem Anmeldebildschirm wählen. Das ist entweder `design.penpot.app`, den
Kaleidos betreibt, oder ein selbst gehosteter Penpot-Server.

Dieser Server empfängt und speichert alles, was Sie in der App tun, zum Beispiel:
- Ihre Anmeldung;
- Ihr Profil;
- Ihre Teams, Projekte und Dateien;
- Ihre Kommentare, Einladungen und Freigabe-Links;
- Schriftarten, Bilder und Dateien, die Sie hochladen.

Wie jeder Server, mit dem Sie sich verbinden, sieht er dabei auch technische Daten wie Ihre
IP-Adresse. Für all das gilt die Datenschutzerklärung des Serverbetreibers. Bei
`design.penpot.app` ist das
[die Datenschutzerklärung von Penpot](https://penpot.app/privacy-policy). Der Entwickler
dieser App hat auf keine dieser Daten Zugriff.

Zwei Ansichten zeigen Penpots eigene Web-App innerhalb der App: „Live-Canvas öffnen“ und
„Prototyp abspielen“. Diese Seiten kommen vom selben Server und verhalten sich wie in
einem Browser. Sie können Cookies und Website-Daten auf Ihrem Gerät speichern und Inhalte
laden, die der Serverbetreiber ausgewählt hat.

## Auf Ihrem Gerät gespeicherte Daten

- **Sitzung:** Penpots Sitzungstoken, im iOS-Schlüsselbund.
- **Anmeldedaten:** die Serveradresse und die E-Mail-Adresse Ihrer letzten Anmeldung,
  damit das Anmeldeformular beim nächsten Mal ausgefüllt ist.
- **Profil:** Ihr Name und die Kennung Ihres Profilbilds, damit Ihr Konto angezeigt wird,
  bevor der Server antwortet.
- **Einstellungen:** Ihre App-Einstellungen (Erscheinungsbild und Sprache) und Ihre
  letzten acht Suchen je Team.
- **Zwischenspeicher:** gerenderte Zeichenflächen, Vorschaubilder, Profilbilder und die
  Gliederung geöffneter Dateien (ihre Seiten, Zeichenflächen und Namen). Der
  Zwischenspeicher lässt Dateien schneller öffnen und liegt im Cache-Ordner der App.

Nichts davon verlässt Ihr Gerät, außer dem, was die App an Ihren Penpot-Server sendet, um
auszuführen, was Sie verlangen.

Wenn Sie sich abmelden (Einstellungen → **Abmelden**) oder Ihr Konto löschen, löscht die App
all das außer der Serveradresse, der E-Mail-Adresse und Ihren App-Einstellungen, die beim
nächsten Mal das Anmeldeformular ausfüllen:
- das Sitzungstoken;
- das zwischengespeicherte Profil;
- Ihre letzten Suchen;
- den gesamten Zwischenspeicher;
- die Cookies und Website-Daten der Ansichten, die Penpots Web-App zeigen.

Beendet der Server Ihre Sitzung, werden Sie ebenfalls abgemeldet. Der Zwischenspeicher
bleibt dann erhalten, damit er bei der nächsten Anmeldung bereitsteht.

Sie können Daten auch selbst löschen:
- Einstellungen → Über → **Bild-Cache leeren** entfernt jederzeit gerenderte
  Zeichenflächen, Vorschaubilder und Profilbilder;
- iOS entfernt Cache-Dateien, wenn der Speicher knapp wird;
- wenn Sie die App löschen, werden alle Daten entfernt, die sie auf Ihrem Gerät gespeichert
  hat.

## Fotos und Dateien

- **In Fotos sichern:** Die App schreibt nur dann in Ihre Fotomediathek, wenn Sie eine
  Zeichenfläche als Bild exportieren und im Teilen-Menü „Bild sichern“ wählen. Sie liest
  Ihre Mediathek nie.
- **Bild auswählen:** Wenn Sie ein neues Profil- oder Teambild auswählen, gibt iOS der App
  nur das gewählte Foto. Die App lädt es auf Ihren Penpot-Server hoch.
- **Schriftarten und Penpot-Dateien:** Schriftarten und `.penpot`-Dateien, die Sie importieren,
  werden auf Ihren Penpot-Server hochgeladen.

## Konto löschen

Einstellungen → Profil → **Konto löschen** bittet Ihren Penpot-Server, Ihr Penpot-Konto zu
löschen. Was danach mit Ihren Daten geschieht, regelt dieser Server.

## Änderungen

Wenn sich diese Erklärung ändert, steht die neue Fassung auf dieser Seite, mit neuem Datum
oben.

## Kontakt

Fragen zur App stellen Sie bitte als Issue unter
[github.com/girafic/penpot-ios/issues](https://github.com/girafic/penpot-ios/issues).

Fragen zu Ihrem Penpot-Konto oder zu Daten auf einem Penpot-Server richten Sie an den
Betreiber dieses Servers. Bei `design.penpot.app` ist das der Penpot-Support unter
[help.penpot.app](https://help.penpot.app).
