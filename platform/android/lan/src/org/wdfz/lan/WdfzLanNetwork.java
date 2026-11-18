package org.wdfz.lan;

import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.net.Inet4Address;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicBoolean;

/** Bind this game's new sockets to a physical LAN, never disable another app's VPN. */
public final class WdfzLanNetwork extends GodotPlugin implements LocalNetworkRoute.Backend {
    private final ConnectivityManager manager;
    private final LocalNetworkRoute route;
    private final Set<Network> blocked = new HashSet<>();
    private final ExecutorService routeMonitor = Executors.newSingleThreadExecutor(
            work -> new Thread(work, "WdfzLanRoute"));
    private final AtomicBoolean routeCheckPending = new AtomicBoolean();
    private volatile String lastStatus = "{\"ok\":true,\"error\":\"\"}";
    private boolean watching;
    private final ConnectivityManager.NetworkCallback callback = new ConnectivityManager.NetworkCallback() {
        @Override public void onBlockedStatusChanged(Network network, boolean value) {
            synchronized (WdfzLanNetwork.this) {
                if (value) blocked.add(network); else blocked.remove(network);
            }
        }
        @Override public void onLost(Network network) {
            synchronized (WdfzLanNetwork.this) { blocked.remove(network); }
        }
    };

    public WdfzLanNetwork(Godot godot) {
        super(godot);
        manager = getContext().getSystemService(ConnectivityManager.class);
        route = new LocalNetworkRoute(this);
    }
    @Override public String getPluginName() { return "WdfzLanNetwork"; }

    @UsedByGodot public synchronized String prepareLocal(String target) {
        try {
            if (!watching) {
                // No INTERNET/VALIDATED requirement: a friend's offline hotspot is a LAN.
                NetworkRequest.Builder builder = new NetworkRequest.Builder();
                if (android.os.Build.VERSION.SDK_INT >= 30) builder.clearCapabilities();
                else builder.removeCapability(NetworkCapabilities.NET_CAPABILITY_TRUSTED)
                        .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED);
                NetworkRequest request = builder.addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build();
                manager.registerNetworkCallback(request, callback);
                watching = true;
            }
            lastStatus = status(route.prepare(target));
        } catch (SecurityException e) { lastStatus = status("系统不允许查询或选择本地网络，请检查 VPN 与网络权限。"); }
        catch (RuntimeException e) { lastStatus = status("无法选择本地网络，请检查 Wi-Fi 后重试。"); }
        return lastStatus;
    }

    /** The game thread reads the last complete result without waiting on Android network services. */
    @UsedByGodot public String routeStatus() {
        if (routeCheckPending.compareAndSet(false, true)) {
            try { routeMonitor.execute(this::refreshRoute); }
            catch (RejectedExecutionException ignored) { routeCheckPending.set(false); }
        }
        return lastStatus;
    }

    private synchronized void refreshRoute() {
        try { if (route.active()) lastStatus = status(route.check()); }
        catch (RuntimeException e) { lastStatus = status("无法确认本地网络状态，请重新加入房间。"); }
        finally { routeCheckPending.set(false); }
    }

    @UsedByGodot public synchronized String releaseLocal() {
        String error;
        try { error = route.release(); }
        catch (RuntimeException e) { error = "无法恢复系统网络，请重启游戏。"; }
        if (error.isEmpty() && watching) {
            try { manager.unregisterNetworkCallback(callback); } catch (IllegalArgumentException ignored) { }
            watching = false;
            blocked.clear();
        }
        lastStatus = status(error);
        return lastStatus;
    }

    @Override public void onMainDestroy() {
        try { releaseLocal(); }
        finally { routeMonitor.shutdownNow(); }
    }

    @Override public List<LocalNetworkRoute.Candidate> networks() {
        List<LocalNetworkRoute.Candidate> out = new ArrayList<>();
        for (Network network : manager.getAllNetworks()) {
            NetworkCapabilities caps = manager.getNetworkCapabilities(network);
            LinkProperties link = manager.getLinkProperties(network);
            if (caps == null || link == null || link.getInterfaceName() == null) continue;
            List<LocalNetworkRoute.Subnet> addresses = new ArrayList<>();
            for (LinkAddress address : link.getLinkAddresses()) {
                if (address.getAddress() instanceof Inet4Address && !address.getAddress().isLoopbackAddress())
                    addresses.add(new LocalNetworkRoute.Subnet(address.getAddress().getHostAddress(), address.getPrefixLength()));
            }
            out.add(new LocalNetworkRoute.Candidate(network.toString(), link.getInterfaceName(),
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI), caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) || !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN),
                    blocked.contains(network), addresses));
        }
        return out;
    }

    @Override public String bound() {
        Network network = manager.getBoundNetworkForProcess();
        return network == null ? null : network.toString();
    }

    @Override public boolean bind(String id) {
        try {
            if (id == null) return manager.bindProcessToNetwork(null);
            for (Network network : manager.getAllNetworks())
                if (network.toString().equals(id)) return manager.bindProcessToNetwork(network);
            return false;
        } catch (SecurityException e) { return false; }
    }

    @Override public boolean vpnActive() {
        for (Network network : manager.getAllNetworks()) {
            NetworkCapabilities caps = manager.getNetworkCapabilities(network);
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return true;
        }
        return false;
    }

    private String status(String error) {
        try {
            LocalNetworkRoute.Candidate selected = route.selected();
            JSONArray addresses = new JSONArray(), broadcasts = new JSONArray();
            if (selected != null) {
                broadcasts.put("255.255.255.255");
                for (LocalNetworkRoute.Subnet address : selected.addresses) {
                    addresses.put(address.address);
                    if (address.broadcast() != null) broadcasts.put(address.broadcast());
                }
                broadcasts.put("127.0.0.1");
            }
            boolean vpn = false;
            try { vpn = vpnActive(); } catch (RuntimeException ignored) { }
            return new JSONObject().put("ok", error.isEmpty()).put("error", error).put("vpn", vpn)
                    .put("bound", selected != null).put("network", selected == null ? "" : selected.id)
                    .put("interface", selected == null ? "" : selected.name)
                    .put("mode", selected == null ? "system" : selected.wifi ? "wifi" : "ethernet")
                    .put("addresses", addresses).put("broadcasts", broadcasts).toString();
        } catch (JSONException e) { return "{\"ok\":false,\"error\":\"本地网络状态编码失败。\"}"; }
    }
}
