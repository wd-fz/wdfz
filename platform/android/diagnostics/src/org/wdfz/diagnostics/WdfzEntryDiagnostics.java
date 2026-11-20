package org.wdfz.diagnostics;

import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Process;
import android.util.Log;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.nio.charset.StandardCharsets;
import java.util.Date;

/** Local, opt-in reading of Android's own exit records. Requires no permissions. */
public final class WdfzEntryDiagnostics extends GodotPlugin {
    private final SharedPreferences notes;
    private final ActivityManager activity;
    private final String packageName;

    public WdfzEntryDiagnostics(Godot godot) {
        super(godot);
        Context context = getContext();
        notes = context.getSharedPreferences("campus_entry", Context.MODE_PRIVATE);
        activity = context.getSystemService(ActivityManager.class);
        packageName = context.getPackageName();
    }

    @Override public String getPluginName() { return "WdfzEntryDiagnostics"; }

    @UsedByGodot public void stage(String stage) {
        // Record only transitions during an entry, never a per-frame heartbeat.
        String summary = stage + " · PID " + Process.myPid();
        Log.i("WdfzEntry", summary);
        SharedPreferences.Editor edit = notes.edit().putString("stage", summary)
                .putLong("time", System.currentTimeMillis());
        if (stage.startsWith("load ")) edit.remove("asset");
        edit.apply();
        if (Build.VERSION.SDK_INT >= 30) {
            byte[] bytes = stage.getBytes(StandardCharsets.UTF_8);
            if (bytes.length <= 128) {
                try { activity.setProcessStateSummary(bytes); }
                catch (RuntimeException ignored) { /* Android may rate-limit this optional note. */ }
            }
        }
    }

    @UsedByGodot public void assetIssue(String detail) {
        notes.edit().putString("asset", detail).apply();
    }

    @UsedByGodot public String report() {
        StringBuilder text = new StringBuilder(packageName).append(" · Android ")
                .append(Build.VERSION.RELEASE).append(" · ").append(Build.MANUFACTURER)
                .append(' ').append(Build.MODEL);
        long time = notes.getLong("time", 0);
        if (time != 0) text.append("\n最近入校  ").append(new Date(time)).append("  ").append(notes.getString("stage", ""));
        if (notes.contains("asset")) text.append("\n资源  ").append(notes.getString("asset", ""));
        if (Build.VERSION.SDK_INT < 30) return text.append("\n此系统版本未提供进程退出记录。").toString();
        try {
            boolean found = false;
            for (ApplicationExitInfo exit : activity.getHistoricalProcessExitReasons(packageName, 0, 12)) {
                if (!packageName.equals(exit.getProcessName())) continue;
                found = true;
                text.append("\n").append(new Date(exit.getTimestamp())).append("  PID ").append(exit.getPid())
                        .append("  ").append(reason(exit.getReason())).append(" (").append(exit.getReason())
                        .append(") status=").append(exit.getStatus()).append(" PSS/RSS KiB=")
                        .append(exit.getPss()).append('/').append(exit.getRss());
                byte[] state = exit.getProcessStateSummary();
                if (state != null) text.append(" stage=").append(new String(state, StandardCharsets.UTF_8));
                String detail = exit.getDescription();
                if (detail != null) text.append("  ").append(detail);
            }
            if (!found) text.append("\n系统尚无本应用主进程的退出记录。");
        } catch (RuntimeException e) {
            text.append("\n系统退出记录暂不可读。");
        }
        return text.toString();
    }

    private static String reason(int code) {
        switch (code) {
            case ApplicationExitInfo.REASON_LOW_MEMORY: return "系统回收内存";
            case ApplicationExitInfo.REASON_CRASH_NATIVE: return "原生代码崩溃";
            case ApplicationExitInfo.REASON_CRASH: return "应用异常";
            case ApplicationExitInfo.REASON_ANR: return "无响应";
            case ApplicationExitInfo.REASON_SIGNALED: return "进程收到信号";
            case ApplicationExitInfo.REASON_USER_REQUESTED: return "用户或系统请求退出";
            case ApplicationExitInfo.REASON_EXIT_SELF: return "应用自行退出";
            default: return "系统退出记录";
        }
    }
}
