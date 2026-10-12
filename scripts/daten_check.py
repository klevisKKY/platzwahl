#!/usr/bin/env python3
"""
Datencheck für Platzwahl
========================

Schaut nach, ob die Bundesagentur für Arbeit (BA) oder das Bundesinstitut für
Berufsbildung (BIBB) neuere Zahlen veröffentlicht haben als die, die gerade in
index.html stehen. Wenn ja, öffnet das Skript ein Issue mit Link und Anleitung.

Woher weiß das Skript, was auf der Seite steht?
  * Monatszahlen: aus MONATSZAHLEN.monat in index.html, z. B. 'September 2026'
  * BIBB-Zahlen:  aus dem Quellen-Link naa309_<JAHR>_tab070 in index.html

Läuft automatisch über .github/workflows/daten-check.yml (jeden Montag).
Zum Ausprobieren auf dem eigenen Rechner (öffnet keine Issues):
    python3 scripts/daten_check.py --nur-anzeigen

Braucht nur die Python-Standardbibliothek.
"""
import argparse
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEITE = os.path.join(WURZEL, 'index.html')

BA_BERICHT = ('https://statistik.arbeitsagentur.de/Statistikdaten/Detail/{jm}/arbeitsmarktberichte/'
              'monatsbericht-monatsbericht/monatsbericht-d-0-{jm}-pdf.pdf')
BA_PRESSE = 'https://www.arbeitsagentur.de/presse'
BIBB_TABELLE = 'https://www.bibb.de/dokumente/pdf/naa309/naa309_{jahr}_{tabelle}.pdf'
BIBB_TABELLEN = [
    ('tab070_1land_mzkt', 'Länder: Plätze und Suchende (Tabelle 70)'),
    ('tab083_1land', 'Länder: Eckwerte, leere Plätze, Suchende (Tabelle 83)'),
    ('tab037_2regional', 'Agenturbezirke: Plätze je 100 Suchende (Tabelle 37)'),
    ('tab083_2regional', 'Agenturbezirke: Eckwerte (Tabelle 83)'),
]
MONATE = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August',
          'September', 'Oktober', 'November', 'Dezember']
# Steht unsichtbar in jedem Issue. So meldet das Skript nichts doppelt,
# auch wenn du ein Issue schon geschlossen hast.
KENNUNG = 'platzwahl-datencheck'


def lies_seite():
    """Liest Berichtsmonat und BIBB-Jahr aus index.html."""
    try:
        html = open(SEITE, encoding='utf-8').read()
    except FileNotFoundError:
        sys.exit('index.html nicht gefunden. Das Skript muss im Repository liegen (Ordner scripts/).')
    m = re.search(r"monat:\s*'([^'\s]+)\s+(\d{4})'", html)
    if not m or m.group(1) not in MONATE:
        sys.exit("In index.html fehlt MONATSZAHLEN.monat, zum Beispiel  monat: 'September 2026',")
    monat = (int(m.group(2)), MONATE.index(m.group(1)) + 1)
    b = re.search(r'naa309_(\d{4})_tab070', html)
    return monat, (int(b.group(1)) if b else None)


def ist_pdf(url):
    """True: dort liegt ein PDF. False: gibt es (noch) nicht. None: Server nicht erreichbar."""
    anfrage = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0 (compatible; platzwahl-datencheck; +https://github.com)',
        'Range': 'bytes=0-1023',
    })
    try:
        with urllib.request.urlopen(anfrage, timeout=45) as antwort:
            return antwort.read(5) == b'%PDF-'
    except urllib.error.HTTPError as fehler:
        if fehler.code in (404, 410):
            return False
        print(f'  Hinweis: {url} antwortet mit HTTP {fehler.code}')
        return None
    except (urllib.error.URLError, TimeoutError, OSError) as fehler:
        print(f'  Hinweis: {url} ist nicht erreichbar ({fehler})')
        return None


def naechster(jahr, monat):
    return (jahr + 1, 1) if monat == 12 else (jahr, monat + 1)


def name(jahr_monat):
    return f'{MONATE[jahr_monat[1] - 1]} {jahr_monat[0]}'


def jm(jahr_monat):
    return f'{jahr_monat[0]}{jahr_monat[1]:02d}'


def github(methode, pfad, daten=None):
    token = os.environ.get('GITHUB_TOKEN')
    repo = os.environ.get('GITHUB_REPOSITORY')
    if not token or not repo:
        sys.exit('GITHUB_TOKEN oder GITHUB_REPOSITORY fehlt. Lokal bitte mit --nur-anzeigen starten.')
    anfrage = urllib.request.Request(
        f'https://api.github.com/repos/{repo}{pfad}',
        data=None if daten is None else json.dumps(daten).encode('utf-8'),
        method=methode,
        headers={
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'platzwahl-datencheck',
            'Content-Type': 'application/json',
        })
    with urllib.request.urlopen(anfrage, timeout=30) as antwort:
        text = antwort.read().decode('utf-8')
        return json.loads(text) if text else None


def schon_gemeldet(schluessel):
    marke = f'<!-- {KENNUNG}:{schluessel} -->'
    seite = 1
    while True:
        liste = github('GET', f'/issues?state=all&per_page=100&page={seite}') or []
        if any(marke in (i.get('body') or '') for i in liste):
            return True
        if len(liste) < 100:
            return False
        seite += 1


def melden(schluessel, titel, text, nur_anzeigen):
    print(f'\n>>> {titel}')
    if nur_anzeigen:
        print(text)
        return
    if schon_gemeldet(schluessel):
        print('    Gibt es schon als Issue, nichts zu tun.')
        return
    issue = github('POST', '/issues', {'title': titel, 'body': text + f'\n\n<!-- {KENNUNG}:{schluessel} -->'})
    print(f"    Issue angelegt: {issue.get('html_url')}")


def text_monatsbericht(neu, alt, url):
    zeilen = [
        f'Die Bundesagentur für Arbeit hat den **Monatsbericht {name(neu)}** veröffentlicht. '
        f'Auf der Seite steht noch **{name(alt)}**.',
        '',
        f'**Bericht (PDF):** {url}',
        f'**Presseinfos:** {BA_PRESSE}',
        '',
        '### So aktualisierst du die Zahlen (etwa 5 Minuten)',
        '- [ ] Im PDF mit der Suche die Abbildung „Arbeitslosenquoten nach Ländern“ finden',
        '- [ ] In `index.html` auf den Stift (Bearbeiten) tippen und mit Strg+F `MONATSZAHLEN` suchen',
        f"- [ ] `monat` auf `'{name(neu)}'` ändern und `monatsbericht` auf den Link oben setzen",
        '- [ ] Die Quoten der 16 Länder und `DE` eintragen. Komma wird Punkt: 6,4 wird `6.4`',
        '- [ ] `arbeitslose` und `stellen` für Deutschland eintragen, ohne Punkte (`2994000`). '
        'Beides steht vorne im Bericht und in der Presseinfo, deren Link kommt in `pressemitteilung`',
        '- [ ] Auf „Commit changes“ tippen und dieses Issue schließen',
    ]
    if neu[1] == 10:
        zeilen += [
            '',
            '> Der Oktober-Bericht enthält auch die Bilanz des Ausbildungsjahres zum 30. September. '
            'Die Karte nutzt aber die BIBB-Zahlen, die im Dezember erscheinen. Dafür kommt ein eigenes Issue.',
        ]
    return '\n'.join(zeilen)


def text_bibb(jahr, links):
    zeilen = [
        f'Das BIBB hat die Ergebnisse der Erhebung zum **30. September {jahr}** veröffentlicht. '
        f'Karte, Rangliste und Texte zeigen noch {jahr - 1}.',
        '',
    ]
    zeilen += [f'- {beschreibung}: {url}' for url, beschreibung in links]
    zeilen += [
        '',
        '### Was zu tun ist',
        'Das ist das große Jahres-Update. Es betrifft viele Zahlen auf einmal, darum lohnt sich Sorgfalt.',
        '- [ ] Neue Zahlen übernehmen und gegen die Tabellen prüfen '
        '(Tipp: den Link zu diesem Issue an Claude schicken und die Seite neu bauen lassen)',
        f'- [ ] Quellen und Stand in `index.html` auf {jahr} ändern',
        '- [ ] Seite testen und dieses Issue schließen',
    ]
    return '\n'.join(zeilen)


def main():
    parser = argparse.ArgumentParser(description='Sucht neue offizielle Zahlen für Platzwahl.')
    parser.add_argument('--nur-anzeigen', action='store_true', help='nichts anlegen, nur ausgeben')
    args = parser.parse_args()

    stand, bibb_jahr = lies_seite()
    heute = datetime.date.today()
    print(f'Auf der Seite: Monatszahlen {name(stand)}, BIBB-Erhebung {bibb_jahr or "unbekannt"}')
    unklar = False

    # 1. Monatsbericht der BA. Zur Kontrolle muss der aktuelle Bericht erreichbar sein.
    print(f'\nBA-Monatsbericht {name(stand)} (Kontrolle):')
    kontrolle = ist_pdf(BA_BERICHT.format(jm=jm(stand)))
    print('  gefunden' if kontrolle else '  nicht gefunden')
    if kontrolle is None:
        unklar = True
    elif kontrolle is False:
        melden(f'ba-muster-{jm(stand)}',
               'Datencheck: Monatsbericht der BA nicht mehr unter der bekannten Adresse',
               f'Der Bericht {name(stand)} ist nicht mehr unter dieser Adresse zu finden:\n'
               f'{BA_BERICHT.format(jm=jm(stand))}\n\nVermutlich hat die BA ihre Links geändert. '
               'Dann muss `BA_BERICHT` in `scripts/daten_check.py` angepasst werden.', args.nur_anzeigen)
    else:
        neuester, kandidat = None, naechster(*stand)
        while kandidat <= (heute.year, heute.month):
            print(f'BA-Monatsbericht {name(kandidat)}:')
            gefunden = ist_pdf(BA_BERICHT.format(jm=jm(kandidat)))
            print('  gefunden' if gefunden else '  noch nicht da')
            if not gefunden:
                unklar = unklar or gefunden is None
                break
            neuester, kandidat = kandidat, naechster(*kandidat)
        if neuester:
            url = BA_BERICHT.format(jm=jm(neuester))
            melden(f'ba-{jm(neuester)}', f'Neue Monatszahlen: {name(neuester)}',
                   text_monatsbericht(neuester, stand, url), args.nur_anzeigen)

    # 2. Jahreszahlen des BIBB (erscheinen meist Anfang Dezember)
    if bibb_jahr:
        neu = bibb_jahr + 1
        print(f'\nBIBB-Erhebung {neu}:')
        links = []
        for tabelle, beschreibung in BIBB_TABELLEN:
            url = BIBB_TABELLE.format(jahr=neu, tabelle=tabelle)
            gefunden = ist_pdf(url)
            print(f'  {tabelle}: ' + ('gefunden' if gefunden else 'noch nicht da'))
            unklar = unklar or gefunden is None
            if gefunden:
                links.append((url, beschreibung))
        if links:
            melden(f'bibb-{neu}', f'Neue BIBB-Zahlen zum 30. September {neu}', text_bibb(neu, links), args.nur_anzeigen)

    if unklar:
        print('\nEin Server war nicht erreichbar. Nächste Woche wird erneut geprüft.')
        # Fehlercode, damit GitHub dich per Mail informiert, falls das dauerhaft so bleibt
        if kontrolle is None:
            sys.exit(1)
    print('\nFertig.')


if __name__ == '__main__':
    main()
