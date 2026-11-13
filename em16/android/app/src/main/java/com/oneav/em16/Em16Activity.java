package com.oneav.em16;

import android.app.NativeActivity;
import android.os.Bundle;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;

/* em16's activity: NativeActivity, its native side libem16.so
   (EmAndroid.c), full screen and kept on; a mouse captured while the
   window has the focus, so that its moves come as deltas (an ADB
   mouse's) and Android's pointer is not shown over the guest's. */
public class Em16Activity extends NativeActivity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    @Override
    public void onWindowFocusChanged(boolean focus) {
        super.onWindowFocusChanged(focus);
        View v = getWindow().getDecorView();
        if (focus) {
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                WindowInsetsController c = v.getWindowInsetsController();
                if (c != null) {
                    c.hide(WindowInsets.Type.systemBars());
                    c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                }
            } else {
                v.setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
            }
            v.requestPointerCapture();
        }
    }
}
