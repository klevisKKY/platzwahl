# Platzwahl

**Wo Azubis gebraucht werden.**

Platzwahl zeigt auf einer Karte, wo in Deutschland Ausbildungsplätze leer bleiben und wo viele Menschen noch einen Platz suchen. Alle Zahlen stammen aus offiziellen Quellen (BIBB und Bundesagentur für Arbeit).

Dazu kommt **Rückwerbung**: Betriebe bieten 10-Minuten-Gespräche an, und Schülerinnen und Schüler, Arbeitsuchende oder Menschen, die umsteigen wollen, buchen einen Termin. Ohne Bewerbungsmappe, einfach erst einmal reden.

**Zur Seite:** https://kleviskky.github.io/platzwahl/

Platzwahl ist ein unabhängiges, nichtkommerzielles Projekt. Es besteht keine Verbindung zur Bundesagentur für Arbeit, zum BIBB oder zu den Kammern.

\---

## Was die Seite kann

* **Karte der Bundesländer** mit vier Ansichten: Ausbildungsplätze je 100 Suchende (Ampel), leer gebliebene Plätze, noch Suchende und Arbeitslosenquote
* **148 Agenturbezirke**: Für jedes Land zeigt die Seite, wie es in den einzelnen Bezirken der Arbeitsagentur aussieht
* **Rangliste und Vergleich** aller Länder
* **Berufe**, in denen Betriebe besonders oft vergeblich suchen, und Berufe, in denen es eng ist
* **Wege für Erwachsene**: Umschulung, Teilqualifizierung, Berufserfahrung anerkennen lassen
* **Rückwerbung**: Betriebe tragen sich ein und legen Termine an, Suchende buchen mit Vornamen und Kontakt. Wer jünger als 16 ist, bucht mit einem Elternteil.

## Die Dateien

|Datei|Wozu|
|-|-|
|`index.html`|Die ganze Seite in einer Datei: Schrift, Karte, Zahlen und Programm. Lädt nichts von fremden Servern.|
|`datenschutz.html`|Datenschutzerklärung|
|`supabase/supabase-setup.sql`|Baut die Datenbank für Rückwerbung (einmal in Supabase ausführen)|
|`scripts/daten\\\_check.py`|Sucht nach neuen offiziellen Zahlen und meldet sich mit einem Issue|
|`scripts/supabase\\\_wach.py`|Fragt einmal am Tag die Datenbank ab, damit das kostenlose Projekt nicht pausiert|
|`.github/workflows/`|Zeitpläne, die die beiden Skripte automatisch starten|

## Wie Rückwerbung funktioniert

Ohne Einstellungen läuft Rückwerbung als **Demo**: Alles bleibt im eigenen Browser, nichts geht an einen Server. Sobald in `index.html` die Daten eines Supabase-Projekts stehen, läuft sie **online** mit echter Datenbank.

* **Regeln in der Datenbank** (Row Level Security): Besucher sehen nur geprüfte Betriebe und ob ein Termin frei ist. Namen und Kontakte bekommt nur der gebuchte Betrieb.
* **Buchen** läuft über eine Funktion in der Datenbank. Sie prüft, ob der Termin noch frei ist, ob bei unter 16 ein Elternteil zugestimmt hat und dass niemand mehr als drei offene Termine hält.
* **Ohne Konto**: Wer bucht, bekommt einen persönlichen Absage-Link.
* **Prüfung**: Neue Betriebe sind erst sichtbar, wenn du sie freischaltest. Ändert ein Betrieb seine Angaben, ist er bis zur nächsten Freigabe wieder unsichtbar.
* **Löschen**: Termine und Buchungen verschwinden 14 Tage nach dem Gespräch automatisch.

### Einrichten (etwa 20 Minuten)

1. Auf [supabase.com](https://supabase.com) ein Konto anlegen (Anmelden mit GitHub geht).
2. **New project**: Name `platzwahl`, Region **Central EU (Frankfurt)**, Datenbank-Passwort sicher aufheben. „Data API“ eingeschaltet lassen.
3. **SQL Editor**: den Inhalt von `supabase/supabase-setup.sql` einfügen und **Run** klicken. Die Warnung zu „destructive operations“ bestätigen. Am Ende steht „Success. No rows returned“.
4. **Authentication → Sign In / Providers**: „Confirm email“ ausschalten. Der eingebaute Mailversand schafft nur wenige Mails pro Stunde und nur an dein eigenes Team.
5. **Authentication → URL Configuration**: als Site URL die Adresse der Seite eintragen.
6. Oben auf **Connect**: *Project URL* und *Publishable key* (`sb\\\_publishable\\\_…`) kopieren.
7. In `index.html` nach `ONLINE\\\_EINSTELLUNGEN` suchen und beide Werte eintragen. Der Publishable key darf öffentlich sein. Den **Secret key** nie in die Seite schreiben.
8. Impressum und Datenschutz ausfüllen: In `index.html` und `datenschutz.html` nach `class="ph"` suchen und die Platzhalter ersetzen.
9. Test: Auf der Seite unter „Für Betriebe“ ein Konto und einen Testbetrieb anlegen, dann freischalten (siehe unten) und einen Termin buchen.

### Betriebe prüfen und freischalten

Bevor ein Betrieb sichtbar wird:

* den Nachweis ansehen (Handelsregister oder Kammer-Nummer)
* die Telefonnummer aus dem Impressum der Firmen-Webseite anrufen und nachfragen, ob die Person dort arbeitet und ausbilden darf

Freischalten im Supabase-Dashboard unter **Table Editor → betriebe**: in der Spalte `geprueft` auf `true` setzen. Oder im SQL Editor:

```sql
-- Wer wartet auf Prüfung?
select name, ort, land, nachweis, erstellt from public.betriebe where not geprueft;

-- Freischalten
update public.betriebe set geprueft = true where name = 'Name des Betriebs';
```

### Gut zu wissen

* **„Passwort vergessen“** braucht einen echten Mailversand. Vor dem großen Start unter Authentication → Emails eigenes SMTP einrichten, zum Beispiel mit Brevo.
* **Advisors**: Supabase warnt vor „security definer“-Funktionen. Bei den fünf öffentlichen Funktionen ist das Absicht, sie sind der einzige Weg zu den Daten.
* **Pausiert?** Kostenlose Projekte schlafen nach etwa einer Woche ohne Nutzung ein. Der Workflow „Supabase wach halten“ verhindert das. Falls doch: im Dashboard auf „Resume project“.

## Zahlen aktuell halten

Der Workflow **Datencheck** läuft jeden Montag. Er liest aus `index.html`, welcher Stand gerade auf der Seite ist, und schaut nach, ob es Neueres gibt. Wenn ja, öffnet er ein **Issue** mit Link und Schritt-für-Schritt-Liste.

* **Jeden Monat** (Ende des Monats): neuer Monatsbericht der Bundesagentur für Arbeit. In `index.html` den Block `MONATSZAHLEN` aktualisieren: Monat, 17 Arbeitslosenquoten, Arbeitslose, gemeldete Stellen, zwei Links. Etwa 5 Minuten.
* **Jedes Jahr** (Anfang Dezember): neue BIBB-Zahlen zum 30. September. Das ist das große Update für Karte, Rangliste und Texte.

Warum nicht vollautomatisch? Die Zahlen erscheinen als PDF. Ein Programm, das PDFs ausliest, kann still falsche Zahlen übernehmen, wenn sich das Layout ändert. Deshalb meldet der Datencheck nur, und ein Mensch prüft.

Von Hand starten: Tab **Actions** → Workflow auswählen → **Run workflow**. Zeitgesteuerte Workflows pausieren, wenn im Repository 60 Tage lang nichts passiert. Jede Aktualisierung der Zahlen zählt als Aktivität.

## Eigene Domain

1. Domain bei einem Anbieter kaufen, zum Beispiel INWX oder Netcup. `platzwahl.de` ist schon vergeben.
2. In GitHub: **Settings → Pages → Custom domain** eintragen und speichern.
3. Beim Anbieter im DNS:

   * vier **A-Einträge** für die Domain selbst: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
   * ein **CNAME** für `www` auf `kleviskky.github.io`
4. Nach einigen Minuten bis Stunden in GitHub **Enforce HTTPS** anhaken.
5. In Supabase unter Authentication → URL Configuration die neue Adresse als Site URL eintragen.

Keine Platzhalter-Einträge wie `\\\*.domain.de` anlegen, die machen die Domain angreifbar.

## Datenquellen

* BIBB-Erhebung über neu abgeschlossene Ausbildungsverträge zum 30. September 2025, Tabellen 70, 71 und 83 (Bundesländer) und Tabelle 37 (Agenturbezirke), Datenstand 5. Dezember 2025: https://www.bibb.de/de/211098.php
* BIBB, Datenreport zum Berufsbildungsbericht 2026, Kapitel A1.1
* BIBB, Christ u. a.: Ausbildungsmarkt 2025 (Dezember 2025)
* Bundesagentur für Arbeit: Ausbildungsmarktbilanz 2024/25, Monatsbericht zum Arbeits- und Ausbildungsmarkt, Fachkräfteengpassanalyse 2025
* Berufsbildungsbericht 2026 der Bundesregierung
* Ländergrenzen: © GeoBasis-DE / BKG (2020), Verwaltungsgebiete 1:250 000, Lizenz dl-de/by-2-0
* Schrift: Atkinson Hyperlegible, Braille Institute of America, SIL Open Font License 1.1

Alle Zahlen sind auf der Seite mit Link zur Quelle angegeben, damit jede Person sie nachprüfen kann.

## Datenschutz in Kürze

* keine Cookies, kein Tracking, keine Werbung, keine fremden Schriften oder Skripte
* Rückwerbung speichert nur, was für den Termin nötig ist, in Frankfurt am Main
* Buchungen werden 14 Tage nach dem Termin gelöscht, Absagen löscht sofort

Details stehen in `datenschutz.html`.

