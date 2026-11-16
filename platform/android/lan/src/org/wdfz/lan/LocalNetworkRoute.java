package org.wdfz.lan;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/** Routing ownership and selection, independent of Android/Godot for executable tests. */
public final class LocalNetworkRoute {
    public static final class Subnet {
        public final String address;
        public final int prefix;
        private final long ip;
        public Subnet(String address, int prefix) {
            this.address = address;
            this.ip = ipv4(address);
            if (prefix < 0 || prefix > 32) throw new IllegalArgumentException("prefix");
            this.prefix = prefix;
        }
        private long mask() { return prefix == 0 ? 0 : (0xffffffffL << (32 - prefix)) & 0xffffffffL; }
        public boolean contains(long target) { return (ip & mask()) == (target & mask()); }
        public String broadcast() {
            if (prefix < 1 || prefix > 30) return null;
            long value = ip | (0xffffffffL ^ mask());
            return (value >>> 24) + "." + ((value >>> 16) & 255) + "." + ((value >>> 8) & 255) + "." + (value & 255);
        }
        @Override public String toString() { return address + "/" + prefix; }
    }

    public static final class Candidate {
        public final String id, name;
        public final boolean wifi, ethernet, vpn, blocked;
        public final List<Subnet> addresses;
        public Candidate(String id, String name, boolean wifi, boolean ethernet, boolean vpn,
                         boolean blocked, List<Subnet> addresses) {
            this.id = id; this.name = name; this.wifi = wifi; this.ethernet = ethernet;
            this.vpn = vpn; this.blocked = blocked; this.addresses = addresses;
        }
        public boolean local() { return !vpn && (wifi || ethernet) && !addresses.isEmpty(); }
    }

    public interface Backend {
        List<Candidate> networks();
        String bound();
        boolean bind(String id);
        boolean vpnActive();
    }

    private final Backend backend;
    private Candidate selected;
    private String previous;
    private boolean fallback;
    private String error = "";
    public LocalNetworkRoute(Backend backend) { this.backend = backend; }
    public Candidate selected() { return selected; }
    public String error() { return error; }
    public boolean active() { return selected != null || fallback; }

    public String prepare(String target) {
        if (active()) return check();
        error = "";
        long destination = target.isEmpty() ? -1 : ipv4(target);
        Candidate best = null;
        int bestScore = -1;
        for (Candidate candidate : backend.networks()) {
            if (!candidate.local()) continue; // VPNs can also advertise TRANSPORT_WIFI.
            int score = candidate.wifi ? 20 : 10;
            if (destination >= 0) for (Subnet subnet : candidate.addresses) {
                if (subnet.contains(destination)) score = Math.max(score, 100 + subnet.prefix);
            }
            if (score > bestScore) { best = candidate; bestScore = score; }
        }
        if (best == null) {
            if (backend.vpnActive()) return error = "VPN 已开启，但 Android 没有提供可直连的本地网络。请连接同一 Wi-Fi，或在 VPN 中将本游戏排除。热点房主可先关闭 VPN 再试。";
            // Tethering's AP interface is not exposed as a ConnectivityManager Network.
            // Without a VPN, keep Android's normal local routes. Never choose cellular
            // as a substitute for Wi-Fi just because it has Internet/VALIDATED capability.
            fallback = true;
            return "";
        }
        if (best.blocked) return error = blockedMessage();
        previous = backend.bound();
        if (!backend.bind(best.id)) return error = "Android 未允许本地网络直连。请在 VPN 中允许应用绕过或将本游戏排除，再重试。";
        selected = best;
        return "";
    }

    public String check() {
        if (!error.isEmpty()) return error;
        if (selected == null) {
            if (fallback && backend.vpnActive()) error = "VPN 接管了当前网络。请重新加入，让游戏选择本地 Wi-Fi；热点房主需允许本游戏绕过 VPN。";
            return error;
        }
        if (!Objects.equals(backend.bound(), selected.id)) return error = "本地网络绑定发生变化，请重新加入房间。";
        for (Candidate candidate : backend.networks()) if (candidate.id.equals(selected.id)) {
            if (candidate.blocked) return error = blockedMessage();
            if (candidate.local() && candidate.name.equals(selected.name) && addressKeys(candidate).equals(addressKeys(selected))) return "";
            return error = "本地网络地址发生变化，请重新加入房间。";
        }
        return error = "Wi-Fi／本地网络已断开，请恢复连接后重新加入房间。";
    }

    public String release() {
        // Only undo our own binding. A different owner must never be overwritten.
        if (selected != null && Objects.equals(backend.bound(), selected.id)) {
            boolean restored = backend.bind(previous);
            if (!restored && previous != null) restored = backend.bind(null);
            if (!restored) return error = "无法恢复系统网络，请重启游戏后再切换联机模式。";
        }
        selected = null; previous = null; fallback = false; error = "";
        return "";
    }

    private String blockedMessage() { return "Android 阻止了本地网络连接。请检查 VPN 的应用绕过设置或系统网络限制，再重新加入。"; }
    private static List<String> addressKeys(Candidate candidate) {
        List<String> keys = new ArrayList<>();
        for (Subnet subnet : candidate.addresses) keys.add(subnet.toString());
        keys.sort(String::compareTo);
        return keys;
    }
    public static long ipv4(String value) {
        String[] parts = value.split("\\.", -1);
        if (parts.length != 4) throw new IllegalArgumentException("IPv4 required");
        long result = 0;
        for (String part : parts) {
            if (!part.matches("[0-9]{1,3}")) throw new IllegalArgumentException("IPv4 required");
            int n = Integer.parseInt(part);
            if (n > 255) throw new IllegalArgumentException("IPv4 required");
            result = (result << 8) | n;
        }
        return result;
    }
}
