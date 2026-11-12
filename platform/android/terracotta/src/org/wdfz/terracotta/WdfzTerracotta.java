package org.wdfz.terracotta;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.net.VpnService;
import net.burningtnt.terracotta.TerracottaAndroidAPI;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONObject;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Native calls can block; never execute them on Godot's render or Android's UI thread. */
public final class WdfzTerracotta extends GodotPlugin {
    private static final int VPN_PERMISSION = 4182;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private volatile boolean destroyed;
    private boolean awaitingPermission;
    private static TerracottaAndroidAPI.Metadata metadata;

    public WdfzTerracotta(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "WdfzTerracotta"; }
    @Override public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(new SignalInfo("prepared", String.class),
                new SignalInfo("response", Integer.class, Integer.class, String.class), new SignalInfo("released")));
    }

    @UsedByGodot public void prepare() {
        runOnHostThread(() -> {
            Activity activity = getActivity();
            if (activity == null || destroyed) return;
            try {
                Intent intent = VpnService.prepare(activity);
                if (intent != null) {
                    awaitingPermission = true;
                    activity.startActivityForResult(intent, VPN_PERMISSION);
                } else initialize();
            } catch (Exception e) { prepared("此设备无法启用远程联机 VPN。"); }
        });
    }

    @Override public void onMainActivityResult(int request, int result, Intent data) {
        if (request != VPN_PERMISSION || !awaitingPermission) return;
        awaitingPermission = false;
        if (result == Activity.RESULT_OK) initialize();
        else prepared("未允许 VPN，远程联机已取消；局域网联机仍可使用。");
    }

    private void initialize() {
        try {
            Intent intent = new Intent(getContext(), TerracottaVpnService.class);
            if (android.os.Build.VERSION.SDK_INT >= 26) getContext().startForegroundService(intent);
            else getContext().startService(intent);
        } catch (Exception e) { prepared("无法启动远程联机服务，请回到游戏前台重试。"); return; }
        worker.execute(() -> {
            try {
                synchronized (WdfzTerracotta.class) {
                    if (metadata == null) metadata = TerracottaAndroidAPI.initialize(getContext(), TerracottaVpnService::fulfill);
                }
                prepared("");
            } catch (Throwable e) {
                TerracottaVpnService.close(getContext());
                prepared("远程联机组件初始化失败，请重启游戏。");
            }
        });
    }

    private void prepared(String error) { if (!destroyed) emitSignal("prepared", error); }

    @UsedByGodot public void request(int id, String path) {
        worker.execute(() -> {
            int status = 200;
            String body = "{}";
            try {
                if (metadata == null) throw new IllegalStateException();
                Uri uri = Uri.parse("http://127.0.0.1" + path);
                switch (uri.getPath()) {
                    case "/meta":
                        // The JNI API does not expose a randomly rebound scaffolding port.
                        // Godot verifies 13448 against our game port and fails closed on collision.
                        body = new JSONObject().put("version", metadata.getTerracottaVersion())
                                .put("yggdrasil_port", 13448).toString();
                        break;
                    case "/state": body = TerracottaAndroidAPI.getState(); break;
                    case "/state/ide": TerracottaAndroidAPI.setWaiting(); break;
                    case "/state/scanning":
                        TerracottaAndroidAPI.setScanning(uri.getQueryParameter("room"), uri.getQueryParameter("player"));
                        break;
                    case "/state/guesting":
                        if (!TerracottaAndroidAPI.setGuesting(uri.getQueryParameter("room"), uri.getQueryParameter("player"))) status = 400;
                        break;
                    default: status = 404;
                }
            } catch (Throwable e) { status = 500; }
            if (!destroyed) emitSignal("response", id, status, body);
        });
    }

    @UsedByGodot public void release() {
        worker.execute(() -> {
            try { if (metadata != null) TerracottaAndroidAPI.setWaiting(); }
            finally {
                TerracottaVpnService.close(getContext());
                if (!destroyed) emitSignal("released");
            }
        });
    }

    @Override public void onMainDestroy() {
        destroyed = true;
        release();
        worker.shutdown();
    }
}
