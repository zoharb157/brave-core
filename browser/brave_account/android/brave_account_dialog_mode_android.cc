/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "base/android/jni_android.h"
#include "brave/browser/brave_account/dialog_mode_holder.h"
#include "brave/components/brave_account/mojom/brave_account.mojom.h"
#include "chrome/android/chrome_jni_headers/BraveAccountDialogMode_jni.h"
#include "content/public/browser/web_contents.h"

namespace chrome::android {

static void JNI_BraveAccountDialogMode_Set(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& java_web_contents,
    int32_t dialog_mode) {
  auto* web_contents =
      content::WebContents::FromJavaWebContents(java_web_contents);
  if (!web_contents) {
    return;
  }

  brave_account::DialogModeHolder::Set(
      *web_contents,
      static_cast<brave_account::mojom::DialogMode>(dialog_mode));
}

}  // namespace chrome::android

DEFINE_JNI(BraveAccountDialogMode)
