// Copyright 2026 Zaatar Tech. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

"use strict";

// Reports the page's own title, so the browser can see what actually rendered.
//
// Every other signal Scout has describes a site. This one describes the page
// in front of the person — the only thing that catches an injected page on a
// domain whose verdict is honestly clean.
//
// Polled rather than read once: plenty of pages ship a placeholder title in
// the markup and set the real one from script a moment later.

window.__firefox__.execute(function($) {
  (function() {
    const messageHandler = '$<message_handler>';
    const W = window;

    let last = null;
    let timesToCheck = 20;
    let intervalId = 0;

    const report = $((title) => {
      return $.postNativeMessage(messageHandler, {
        "securityToken": SECURITY_TOKEN,
        "title": title,
        "url": W.location.href
      });
    });

    const checkTitle = $(_ => {
      timesToCheck -= 1;
      if (timesToCheck <= 0) {
        W.clearInterval(intervalId);
      }

      const title = W.document.title;
      if (typeof title !== 'string') { return; }
      const trimmed = title.trim();
      if (!trimmed || trimmed === last) { return; }
      last = trimmed;
      report(trimmed.substring(0, 300));
    });

    intervalId = W.setInterval(checkTitle, 300);
    checkTitle();
  })();
});
