// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Reports the link under the user's finger the moment they touch it.
//
// Scout has to have a verdict before it can let a navigation through, and
// fetching one takes a beat. A tap gives a head start: `pointerdown` fires
// well before the navigation commits, which is enough for a verdict that is
// already on the service to arrive before the page would have needed it.
//
// It only reports links the user actually touched — never every link on the
// page — so the work tracks real intent instead of guessing.

window.__firefox__.execute(function($) {
  "use strict";

  // The same link reported twice in a row is the ordinary case (touch then
  // click); the browser side ignores repeats, and so does this.
  let last = null;
  let lastAt = 0;

  function report(href) {
    const now = Date.now();
    if (href === last && now - lastAt < 2000) return;
    last = href;
    lastAt = now;
    $.postNativeMessage('$<message_handler>', {
      "securityToken": SECURITY_TOKEN,
      "url": href,
    });
  }

  function linkFrom(target) {
    // `closest` walks up from whatever child element was actually touched —
    // the span inside the anchor, the image inside the card.
    const anchor = target && target.closest ? target.closest('a[href]') : null;
    if (!anchor) return null;
    const href = anchor.href;
    if (typeof href !== 'string') return null;
    if (!href.startsWith('http:') && !href.startsWith('https:')) return null;
    // Same page: nothing to check.
    if (href.split('#')[0] === window.location.href.split('#')[0]) return null;
    return href;
  }

  function onDown(event) {
    const href = linkFrom(event.target);
    if (href) report(href);
  }

  // Passive: this must never delay or interfere with the tap itself.
  const options = { capture: true, passive: true };
  window.addEventListener('pointerdown', onDown, options);
  // Safari fires touchstart slightly earlier on some pages; both are deduped.
  window.addEventListener('touchstart', onDown, options);
});
