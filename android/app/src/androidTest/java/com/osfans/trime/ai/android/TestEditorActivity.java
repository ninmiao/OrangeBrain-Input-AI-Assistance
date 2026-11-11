package com.osfans.trime.ai.android;

import android.app.Activity;
import android.os.Bundle;
import android.text.InputType;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.LinearLayout;

/** Standalone test-APK activity: deliberately uses only Android framework classes. */
public class TestEditorActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (getActionBar() != null) getActionBar().hide();
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE | WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(20, 80, 20, 20);
        android.widget.TextView selection = new android.widget.TextView(this);
        selection.setContentDescription("test-selection");
        EditText input = new EditText(this) {
            @Override protected void onSelectionChanged(int start, int end) {
                super.onSelectionChanged(start, end);
                selection.setText("selection:" + start + ":" + end);
            }
        };
        input.setHint("AI test editor");
        input.setContentDescription("test-editor");
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        EditText password = new EditText(this);
        password.setHint("Password (AI disabled)");
        password.setContentDescription("test-password");
        password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        layout.addView(input);
        layout.addView(password);
        layout.addView(selection);
        setContentView(layout);
        input.requestFocus();
        input.postDelayed(() -> ((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).showSoftInput(input, InputMethodManager.SHOW_IMPLICIT), 300);
    }
}
