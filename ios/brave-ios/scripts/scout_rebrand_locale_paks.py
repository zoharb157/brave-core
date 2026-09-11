#!/usr/bin/env python3
# Copyright 2026 Zaatar Tech. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
"""Rename "Brave" to "Scout" in BraveCore.framework's compiled UI strings.

The C++ layer's strings come from Brave's branded copies of Chromium's .grd
files. Editing those would change grit's message fingerprints and orphan
every translation, so Scout rewrites the compiled locale paks instead, after
BraveCore is built and before Xcode embeds the framework. The swap is
idempotent. Languages that inflect the name get Scout's matching ending, the
same rules as the app's own .strings.

  scout_rebrand_locale_paks.py <path/to/BraveCore.framework>
"""

import glob
import os
import re
import sys

_SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(_SRC, 'tools', 'grit'))
sys.path.insert(0, os.path.join(_SRC, 'brave', 'script'))  # grit's brave overrides
from grit.format import data_pack  # pylint: disable=wrong-import-position

_FI = {'n': 'in', 'a': 'ia', 'en': 'iin'}
_HU = {'et': 'ot', 't': 'ot', 'ot': 'ot', 'ben': 'ban', 'ban': 'ban', 'be': 'ba',
       'ba': 'ba', 'vel': 'tal', 'val': 'tal', 'nek': 'nak', 'nak': 'nak',
       'ből': 'ból', 'ból': 'ból', 'tól': 'tól', 'től': 'tól', 'hez': 'hoz',
       'hoz': 'hoz', 're': 'ra', 'ra': 'ra', 'en': 'on', 'on': 'on', 'ről': 'ról',
       'ról': 'ról', 'nél': 'nál', 'nál': 'nál', 'ért': 'ért', 'ig': 'ig',
       'ként': 'ként', 'é': 'é', 'os': 'os', 'es': 'os'}
_TR = {'in': 'un', 'ın': 'un', 'i': 'u', 'ı': 'u', 'yi': 'u', 'e': 'a', 'ye': 'a',
       'a': 'a', 'de': 'ta', 'da': 'ta', 'den': 'tan', 'dan': 'tan', 'le': 'la',
       'la': 'la', 'dir': 'tur', 'dır': 'tur', 'ta': 'ta', 'te': 'ta',
       'ten': 'tan', 'tan': 'tan'}
# Brave's trademark notice: dropped rather than claim Brave's marks for Scout.
_TRADEMARK = re.compile(r'©\s*\d{4}\s+Brave Software,? Inc\.?\s*[^.。]*Brave[^.。]*[.。]\s*')


def rewrite(text, lang):
  if 'Brave' not in text and 'BRAVE' not in text:
    return text
  text = _TRADEMARK.sub('', text)
  if lang == 'fi':
    text = re.sub(r'Brave(n|a|ssa|sta|en|lle|lla|lta|ksi|na|ssä|stä|llä|ltä|ä)\b',
                  lambda m: 'Scout' + _FI.get(m.group(1), 'i' + m.group(1)), text)
  elif lang == 'hu':
    text = re.sub(r'Brave-(\w+)',
                  lambda m: 'Scout' + _HU[m.group(1)] if m.group(1) in _HU
                  else 'Scout-' + m.group(1), text)
  elif lang == 'tr':
    text = re.sub(r"Brave['’](\w+)",
                  lambda m: 'Scout' if m.group(1) == 's'
                  else "Scout'" + _TR.get(m.group(1), m.group(1)), text)
  elif lang == 'sl':
    text = text.replace('Braveju', 'Scoutu')
  return text.replace('BRAVE', 'SCOUT').replace('Brave', 'Scout')


def rebrand(framework_dir):
  changed_paks = 0
  for pak in sorted(glob.glob(os.path.join(framework_dir, '*.lproj', 'locale.pak'))):
    lang = os.path.basename(os.path.dirname(pak))[:-len('.lproj')]
    contents = data_pack.ReadDataPack(pak)
    if contents.encoding == data_pack.UTF8:
      codec = 'utf-8'
    elif contents.encoding == data_pack.UTF16:
      codec = 'utf-16-le'
    else:
      continue
    changed = False
    resources = {}
    for rid, raw in contents.resources.items():
      try:
        text = raw.decode(codec)
      except UnicodeDecodeError:
        resources[rid] = raw
        continue
      new = rewrite(text, lang)
      changed |= new != text
      resources[rid] = new.encode(codec)
    if changed:
      data_pack.WriteDataPack(resources, pak, contents.encoding)
      changed_paks += 1
  return changed_paks


if __name__ == '__main__':
  if len(sys.argv) != 2:
    sys.exit(__doc__)
  print(f'Scout: rebranded {rebrand(sys.argv[1])} locale paks')
