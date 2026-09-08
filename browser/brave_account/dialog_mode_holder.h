/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_BROWSER_BRAVE_ACCOUNT_DIALOG_MODE_HOLDER_H_
#define BRAVE_BROWSER_BRAVE_ACCOUNT_DIALOG_MODE_HOLDER_H_

#include "brave/components/brave_account/mojom/brave_account.mojom.h"
#include "content/public/browser/web_contents_user_data.h"

namespace content {
class WebContents;
}  // namespace content

namespace brave_account {

// Carries the `mojom::DialogMode` a Brave Account page was opened in, from the
// host surface that opened it to the WebUI controller that serves it.
//
// Set before navigating; read when the page asks via
// `mojom::DialogController::GetDialogMode()`. Reading on demand rather than at
// controller construction keeps this free of ordering constraints between the
// host hook that populates it and the navigation it applies to.
//
// Deliberately not persisted: a restored tab comes back in `kDefault`, so a
// session restore cannot drop the user back into a half-finished destructive
// flow.
class DialogModeHolder : public content::WebContentsUserData<DialogModeHolder> {
 public:
  DialogModeHolder(const DialogModeHolder&) = delete;
  DialogModeHolder& operator=(const DialogModeHolder&) = delete;

  ~DialogModeHolder() override;

  // Replaces any mode already set on `web_contents`.
  static void Set(content::WebContents& web_contents, mojom::DialogMode mode);

  // Returns `kDefault` if no mode was set.
  static mojom::DialogMode Get(content::WebContents& web_contents);

 private:
  friend class content::WebContentsUserData<DialogModeHolder>;

  DialogModeHolder(content::WebContents* web_contents, mojom::DialogMode mode);

  const mojom::DialogMode mode_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace brave_account

#endif  // BRAVE_BROWSER_BRAVE_ACCOUNT_DIALOG_MODE_HOLDER_H_
