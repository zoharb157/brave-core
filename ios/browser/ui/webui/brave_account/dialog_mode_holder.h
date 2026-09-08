// Copyright (c) 2026 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_IOS_BROWSER_UI_WEBUI_BRAVE_ACCOUNT_DIALOG_MODE_HOLDER_H_
#define BRAVE_IOS_BROWSER_UI_WEBUI_BRAVE_ACCOUNT_DIALOG_MODE_HOLDER_H_

#include "brave/components/brave_account/mojom/brave_account.mojom.h"
#include "ios/web/public/web_state_user_data.h"

namespace brave_account {

// Some WebState user data that holds onto the mode the brave://account WebUI
// page is served in. Set by the host surface that opens the page, before the
// page is loaded; read back by `BraveAccountUIIOS::GetDialogMode()`.
//
// iOS counterpart of `//brave/browser/brave_account:dialog_mode_holder` - see
// that header for why the mode travels as host state rather than in the URL.
class DialogModeHolder : public web::WebStateUserData<DialogModeHolder> {
 public:
  void SetMode(mojom::DialogMode mode) { mode_ = mode; }
  mojom::DialogMode mode() const { return mode_; }

 private:
  explicit DialogModeHolder(web::WebState*);
  friend class web::WebStateUserData<DialogModeHolder>;
  mojom::DialogMode mode_ = mojom::DialogMode::kDefault;
};

}  // namespace brave_account

#endif  // BRAVE_IOS_BROWSER_UI_WEBUI_BRAVE_ACCOUNT_DIALOG_MODE_HOLDER_H_
