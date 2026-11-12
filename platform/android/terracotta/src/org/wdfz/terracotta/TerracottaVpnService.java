package org.wdfz.terracotta;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import net.burningtnt.terracotta.TerracottaAndroidAPI;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/** TUN descriptors belong to this service and outlive native EasyTier instances. */
public final class TerracottaVpnService extends VpnService {
    private static volatile TerracottaVpnService instance;
    private final List<ParcelFileDescriptor> tunnels = new ArrayList<>();
    private boolean closing;
    private final CountDownLatch stopped = new CountDownLatch(1);

    @Override public void onCreate() {
        super.onCreate();
        instance = this;
        String channel = "wdfz_remote";
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager.class).createNotificationChannel(
                    new NotificationChannel(channel, "远程合作连接", NotificationManager.IMPORTANCE_LOW));
        }
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, channel) : new Notification.Builder(this);
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch != null) builder.setContentIntent(PendingIntent.getActivity(this, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        startForeground(4182, builder.setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setContentTitle("武大附中 · 远程合作")
                .setContentText("Terracotta 正在连接好友；返回游戏离开房间即可断开。")
                .setOngoing(true).build());
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) { return START_NOT_STICKY; }

    // Called by the native API's dedicated callback thread, not the command worker.
    public static void fulfill() {
        TerracottaAndroidAPI.VpnServiceRequest request = TerracottaAndroidAPI.getPendingVpnServiceRequest();
        TerracottaVpnService service = instance;
        if (service == null) { request.reject(); return; }
        synchronized (service) {
            if (service.closing) { request.reject(); return; }
            try {
                Builder builder = service.new Builder().setSession("WDFZ · Terracotta").setMtu(1380);
                builder.addAllowedApplication(service.getPackageName());
                // Only upstream's virtual-network routes are installed. Never add a default route.
                service.tunnels.add(request.startVpnService(builder));
            } catch (Exception e) { request.reject(); }
        }
    }

    public static void close(Context context) {
        TerracottaVpnService service = instance;
        if (service != null) service.closeDescriptors();
        context.stopService(new Intent(context, TerracottaVpnService.class));
        if (service != null) {
            try { service.stopped.await(3, TimeUnit.SECONDS); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        }
    }

    private synchronized void closeDescriptors() {
        closing = true;
        for (ParcelFileDescriptor tunnel : tunnels) {
            try { tunnel.close(); } catch (IOException ignored) { }
        }
        tunnels.clear();
    }

    @Override public void onRevoke() {
        // Revocation can race a state request. Stop native work before closing borrowed FDs.
        new Thread(() -> { try { TerracottaAndroidAPI.setWaiting(); } finally { close(this); } }, "wdfz-vpn-stop").start();
    }

    @Override public void onDestroy() {
        if (instance == this) instance = null;
        // Android may stop the service independently of Godot (task removal / another VPN).
        if (!closing) new Thread(() -> {
            try { TerracottaAndroidAPI.setWaiting(); } catch (IllegalStateException ignored) { }
            finally { closeDescriptors(); }
        }, "wdfz-vpn-destroy").start();
        stopped.countDown();
        super.onDestroy();
    }
}
