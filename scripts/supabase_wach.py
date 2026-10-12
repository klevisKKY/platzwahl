#!/usr/bin/env python3
"""
Supabase wach halten
====================

Kostenlose Supabase-Projekte werden pausiert, wenn eine Woche lang kaum
jemand die Datenbank nutzt. Dieses Skript fragt einmal am Tag die freien
Termine ab. Das zählt als Nutzung und räumt nebenbei alte Termine auf.

Project URL und Publishable key liest es aus index.html. Solange dort nichts
eingetragen ist (Demo), tut es nichts.

Läuft automatisch über .github/workflows/supabase-wach.yml.
Braucht nur die Python-Standardbibliothek.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEITE = os.path.join(WURZEL, 'index.html')


def einstellungen():
    html = open(SEITE, encoding='utf-8').read()
    url = re.search(r"supabaseUrl:\s*'([^']*)'", html)
    key = re.search(r"supabaseKey:\s*'([^']*)'", html)
    return (url.group(1).strip() if url else ''), (key.group(1).strip() if key else '')


def main():
    url, key = einstellungen()
    if not url or not key:
        print('Rückwerbung läuft als Demo (keine Supabase-Daten in index.html). Nichts zu tun.')
        return 0
    if not url.startswith('https://'):
        print('supabaseUrl in index.html muss mit https:// beginnen.')
        return 1
    kopf = {'apikey': key, 'Content-Type': 'application/json', 'Accept': 'application/json',
            'User-Agent': 'platzwahl-wach'}
    if key.startswith('eyJ'):  # alter "anon"-Schlüssel braucht ihn zusätzlich hier
        kopf['Authorization'] = 'Bearer ' + key
    anfrage = urllib.request.Request(url.rstrip('/') + '/rest/v1/rpc/termine_oeffentlich',
                                     data=b'{}', method='POST', headers=kopf)
    try:
        with urllib.request.urlopen(anfrage, timeout=60) as antwort:
            termine = json.loads(antwort.read().decode('utf-8') or '[]')
    except urllib.error.HTTPError as fehler:
        print(f'Supabase antwortet mit HTTP {fehler.code}: {fehler.read().decode("utf-8", "replace")[:300]}')
        if fehler.code in (401, 403):
            print('Der Schlüssel passt nicht. supabaseKey in index.html mit "Connect" im Dashboard vergleichen.')
        elif fehler.code == 404:
            print('Funktion nicht gefunden. Wurde supabase-setup.sql im SQL Editor ausgeführt?')
        else:
            print('Ist das Projekt pausiert? Dann im Supabase-Dashboard auf "Resume project" klicken.')
        return 1
    except (urllib.error.URLError, TimeoutError, OSError) as fehler:
        print(f'Supabase ist nicht erreichbar: {fehler}')
        return 1
    frei = sum(1 for t in termine if not t.get('gebucht'))
    print(f'Supabase ist wach. Termine in den nächsten 30 Tagen: {len(termine)}, davon frei: {frei}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
