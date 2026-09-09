/* Copyright (c) 2026 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.brave_account;

import org.jni_zero.JNINamespace;
import org.jni_zero.NativeMethods;

import org.chromium.brave_account.mojom.DialogMode;
import org.chromium.build.annotations.NullMarked;
import org.chromium.content_public.browser.WebContents;

/**
 * Attaches the mode a brave://account page is served in to that page's WebContents. Set before the
 * page is loaded; read back by the page through {@code
 * brave_account::mojom::DialogController::GetDialogMode()}.
 */
@JNINamespace("chrome::android")
@NullMarked
public class BraveAccountDialogMode {
    private BraveAccountDialogMode() {}

    public static void set(WebContents webContents, @DialogMode.EnumType int mode) {
        BraveAccountDialogModeJni.get().set(webContents, mode);
    }

    @NativeMethods
    interface Natives {
        void set(WebContents webContents, int mode);
    }
}
