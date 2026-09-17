// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Reports the link the user tapped, a moment before the tap navigates.
//
// Scout has to have a verdict before it can let a navigation through, and
// fetching one takes a beat. A tap gives a head start: the finger lifts before
// the click fires and the navigation starts, which is enough for a verdict
// that is already on the service to arrive before the page would have needed
// it.
//
// It reports on the lift, not the touch. A finger lands on a link every time
// someone scrolls a feed — on a page of videos or posts there is little else
// to land on — and reporting on the touch started a paid check for every link
// scrolled past, spending the phone's allowance on things nobody chose to
// open. A touch that moved is a scroll; only one that lifted where it landed
// is a tap. The head start this gives up is the length of a tap, next to a
// check that takes seconds.

window.__firefox__.execute(function($) {
  "use strict";

  // How far a finger may drift and still be tapping, in CSS pixels.
  const TAP_SLOP = 10;

  // The same link reported twice in a row is the ordinary case (pointer and
  // touch events for one tap); the browser side ignores repeats, and so does
  // this.
  let last = null;
  let lastAt = 0;

  // Where the current touch started, and on which link.
  let start = null;

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

  function point(event) {
    const t = event.changedTouches && event.changedTouches[0];
    return t ? { x: t.clientX, y: t.clientY } : { x: event.clientX, y: event.clientY };
  }

  function onDown(event) {
    const href = linkFrom(event.target);
    start = href ? { href: href, ...point(event) } : null;
  }

  function onMove(event) {
    if (!start) return;
    const p = point(event);
    if (Math.abs(p.x - start.x) > TAP_SLOP || Math.abs(p.y - start.y) > TAP_SLOP) {
      start = null;
    }
  }

  function onUp(event) {
    if (!start) return;
    const p = point(event);
    const moved = Math.abs(p.x - start.x) > TAP_SLOP || Math.abs(p.y - start.y) > TAP_SLOP;
    const href = start.href;
    start = null;
    if (!moved) report(href);
  }

  function onCancel() {
    // The browser took the touch for a scroll or a zoom.
    start = null;
  }

  // Passive: this must never delay or interfere with the tap itself.
  const options = { capture: true, passive: true };
  window.addEventListener('pointerdown', onDown, options);
  window.addEventListener('pointermove', onMove, options);
  window.addEventListener('pointerup', onUp, options);
  window.addEventListener('pointercancel', onCancel, options);
  // Some pages only get touch events through; both paths dedupe.
  window.addEventListener('touchstart', onDown, options);
  window.addEventListener('touchmove', onMove, options);
  window.addEventListener('touchend', onUp, options);
  window.addEventListener('touchcancel', onCancel, options);
});
