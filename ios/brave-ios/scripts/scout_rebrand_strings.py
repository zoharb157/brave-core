#!/usr/bin/env python3
# Copyright 2026 Zaatar Tech. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Remove every 'Brave' from brave-ios's localized strings. Re-run after rebasing
onto a new Brave release; it is idempotent.

  scripts/scout_rebrand_strings.py [--dry]

Covers the English source values (NSLocalizedString `value:` in Swift) and every
.strings file in every locale. BraveCore's compiled C++ strings are handled at
build time by scout_rebrand_locale_paks.py.

The name is swapped in place ("Brave" -> "Scout") so every translation stays
grammatical; languages that inflect the name get the matching Scout ending.
Brave-hosted URLs point at Scout's own pages, or at the neutral standard.
"""
import os, re, sys, collections

DRY = '--dry' in sys.argv
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SITE = 'https://zaatar-scout.fly.dev'
GPC = 'https://globalprivacycontrol.org/'

URL = re.compile(r'https?://[^\s)\]"\\]*brave[^\s)\]"\\]*', re.I)
FI = {'n': 'in', 'a': 'ia', 'en': 'iin'}  # Braven -> Scoutin, Bravea -> Scoutia, Braveen -> Scoutiin
HU = {'et': 'ot', 't': 'ot', 'ot': 'ot', 'ben': 'ban', 'ban': 'ban', 'be': 'ba', 'ba': 'ba',
      'vel': 'tal', 'val': 'tal', 'nek': 'nak', 'nak': 'nak', 'ből': 'ból', 'ból': 'ból',
      'tól': 'tól', 'től': 'tól', 'hez': 'hoz', 'hoz': 'hoz', 're': 'ra', 'ra': 'ra',
      'en': 'on', 'on': 'on', 'ről': 'ról', 'ról': 'ról', 'nél': 'nál', 'nál': 'nál',
      'ért': 'ért', 'ig': 'ig', 'ként': 'ként', 'é': 'é', 'os': 'os', 'es': 'os'}
TR = {'in': 'un', 'ın': 'un', 'i': 'u', 'ı': 'u', 'yi': 'u', 'e': 'a', 'ye': 'a', 'a': 'a',
      'de': 'ta', 'da': 'ta', 'den': 'tan', 'dan': 'tan', 'le': 'la', 'la': 'la',
      'dir': 'tur', 'dır': 'tur', 'ta': 'ta', 'te': 'ta', 'ten': 'tan', 'tan': 'tan'}
unknown = collections.Counter()


def url_for(url, key):
    if key == 'EnableGPCDescription':
        return GPC
    u = url.lower()
    if 'terms' in u:
        return f'{SITE}/terms'
    if 'privacy' in u:
        return f'{SITE}/privacy'
    return f'{SITE}/support'


def rewrite(v, loc, key):
    if 'rave' not in v and 'RAVE' not in v:
        return v
    # Brave's trademark notice: drop it rather than claim Brave's marks for Scout.
    if key == 'wallet.setupCryptoDisclaimer':
        v = re.sub(r'^©\s*\d{4}\s+Brave Software,? Inc\.?\s*', '', v)
        v = re.sub(r'^[^.。]*Brave[^.。]*[.。]\s*', '', v)
    v = URL.sub(lambda m: url_for(m.group(0), key), v)
    # A sentence pointing at brave:// internals (hidden AI Chat) is dropped.
    v = re.sub(r'\s*[^.。!?]*brave://[^.。!?]*[.。!?]?', '', v)
    v = re.sub(r'(?i)\bbrave\.com\b', 'the web' if loc == 'en' else 'web', v)
    if loc == 'fi':
        v = re.sub(r'Brave(n|a|ssa|sta|en|lle|lla|lta|ksi|na|ssä|stä|llä|ltä|ä)\b',
                   lambda m: 'Scout' + FI.get(m.group(1), 'i' + m.group(1)), v)
    elif loc == 'hu':
        def hu(m):
            suf = m.group(1)
            if suf in HU:
                return 'Scout' + HU[suf]
            if len(suf) <= 4:
                unknown[('hu', suf)] += 1
            return 'Scout-' + suf  # a compound: Brave-fiók -> Scout-fiók
        v = re.sub(r'Brave-(\w+)', hu, v)
    elif loc == 'tr':
        def tr(m):
            suf = m.group(1)
            if suf == 's':  # a stray English possessive: "Brave's Sync"
                return 'Scout'
            if suf not in TR:
                unknown[('tr', suf)] += 1
            return "Scout'" + TR.get(suf, suf)
        v = re.sub(r"Brave['’](\w+)", tr, v)
    elif loc == 'sl':
        v = v.replace('Braveju', 'Scoutu')
    elif loc in ('bs', 'hr'):
        v = v.replace('omogućujeBraveu', 'omogućuje Scoutu')
    v = v.replace('BRAVE', 'SCOUT').replace('Brave', 'Scout')
    return v


# --- .strings, every locale ---------------------------------------------------
ENTRY = re.compile(r'^("(?P<k>(?:[^"\\]|\\.)+)"\s*=\s*")(?P<v>(?:[^"\\]|\\.)*)(";)', re.M)
changed_files = changed_values = 0
for dp, dn, fn in os.walk(ROOT):
    rel = os.path.relpath(dp, ROOT)
    if not dp.endswith('.lproj') or 'Tests' in rel or '.build' in rel:
        continue
    loc = os.path.basename(dp)[:-6]
    loc = 'en' if loc == 'Base' else loc
    for f in fn:
        if not f.endswith('.strings'):
            continue
        p = os.path.join(dp, f)
        s = open(p, encoding='utf-8').read()
        def fix(m):
            global changed_values
            nv = rewrite(m['v'], loc, m['k'])
            if nv != m['v']:
                changed_values += 1
            return m.group(1) + nv + m.group(4)
        ns = ENTRY.sub(fix, s)
        if ns != s:
            changed_files += 1
            if not DRY:
                open(p, 'w', encoding='utf-8').write(ns)
print(f'.strings: {changed_values} values in {changed_files} files')

# --- English source values in Swift ------------------------------------------
CALL = re.compile(r'NSLocalizedString\(\s*"(?P<k>[^"]+)"(?P<body>.*?)comment:', re.S)
LIT = re.compile(r'"(?:[^"\\]|\\.)*"|"""(?:.|\n)*?"""')
swift_values = 0
for dp, dn, fn in [w for top in ('Sources', 'App') for w in os.walk(os.path.join(ROOT, top))]:
    if 'Tests' in dp:
        continue
    for f in fn:
        if not f.endswith('.swift'):
            continue
        p = os.path.join(dp, f)
        s = open(p, encoding='utf-8').read()
        def fix_call(m):
            global swift_values
            body = m['body']
            vi = body.find('value:')
            if vi < 0:
                return m.group(0)
            head, tail = body[:vi], body[vi:]
            def fix_lit(l):
                return l.group(0)[:3] + rewrite(l.group(0)[3:-3], 'en', m['k']) + l.group(0)[-3:] \
                    if l.group(0).startswith('"""') else '"' + rewrite(l.group(0)[1:-1], 'en', m['k']) + '"'
            # only the string literals of the value argument (before `comment:`)
            new_tail = LIT.sub(fix_lit, tail)
            if new_tail != tail:
                swift_values += 1
            return m.group(0)[:m.start('body') - m.start()] + head + new_tail + 'comment:'
        ns = CALL.sub(fix_call, s)
        if ns != s and not DRY:
            open(p, 'w', encoding='utf-8').write(ns)
print(f'Swift: {swift_values} English values')
if unknown:
    print('UNMAPPED SUFFIXES', unknown.most_common())
