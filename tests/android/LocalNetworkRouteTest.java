package org.wdfz.lan;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public final class LocalNetworkRouteTest {
    static int checks;
    static void check(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    static LocalNetworkRoute.Candidate candidate(String id, boolean wifi, boolean vpn, String address, int prefix) {
        return new LocalNetworkRoute.Candidate(id, "wlan-" + id, wifi, false, vpn, false,
                List.of(new LocalNetworkRoute.Subnet(address, prefix)));
    }
    static final class Fake implements LocalNetworkRoute.Backend {
        List<LocalNetworkRoute.Candidate> available = new ArrayList<>();
        List<String> calls = new ArrayList<>();
        String current;
        boolean reject, vpn;
        public List<LocalNetworkRoute.Candidate> networks() { return available; }
        public String bound() { return current; }
        public boolean vpnActive() { return vpn; }
        public boolean bind(String id) { calls.add(id); if (reject) return false; current = id; return true; }
    }
    public static void main(String[] args) {
        // Host (empty target), scanning, and guest all exclude a VPN that claims WIFI.
        for (String target : List.of("", "192.168.8.9")) {
            Fake system = new Fake(); system.vpn = true;
            system.available.add(candidate("vpn", true, true, "192.168.8.2", 24));
            system.available.add(candidate("mobile", false, false, "10.0.0.2", 8));
            system.available.add(candidate("wifi", true, false, "192.168.8.3", 24));
            LocalNetworkRoute route = new LocalNetworkRoute(system);
            check(route.prepare(target).isEmpty(), "host/guest can bind the physical LAN with VPN active");
            check("wifi".equals(system.current), "never choose VPN WIFI or cellular");
            check(route.prepare(target).isEmpty() && system.calls.size() == 1, "idempotent acquisition");
            check(route.check().isEmpty(), "binding remains live");
            check(route.release().isEmpty() && system.current == null, "return to the prior default/VPN on exit");
            route.release(); check(system.calls.size() == 2, "releasing twice does not rebind the process");
        }
        Fake system = new Fake();
        system.available.add(candidate("other-wifi", true, false, "192.168.1.2", 24));
        system.available.add(new LocalNetworkRoute.Candidate("ethernet", "eth0", false, true, false, false,
                List.of(new LocalNetworkRoute.Subnet("172.20.6.1", 23))));
        system.current = "prior";
        LocalNetworkRoute route = new LocalNetworkRoute(system);
        check(route.prepare("172.20.7.9").isEmpty() && "ethernet".equals(system.current), "select the matching LAN subnet, not the Internet default");
        check("172.20.7.255".equals(route.selected().addresses.get(0).broadcast()), "broadcast uses actual /23 prefix");
        check(route.release().isEmpty() && "prior".equals(system.current), "restore a previous explicit binding");
        route.prepare(""); system.current = "another-owner"; route.release();
        check("another-owner".equals(system.current), "do not overwrite a later owner's binding");
        system.current = null; route.prepare(""); system.available.clear();
        check(!route.check().isEmpty() && route.selected() != null, "network loss fails without falling through to VPN/cellular");
        route.release(); check(system.current == null, "release a lost network after sockets close");

        Fake hotspot = new Fake();
        hotspot.available.add(candidate("mobile", false, false, "10.1.2.3", 8));
        LocalNetworkRoute hotRoute = new LocalNetworkRoute(hotspot);
        check(hotRoute.prepare("").isEmpty() && hotRoute.selected() == null && hotspot.calls.isEmpty(), "hotspot without VPN preserves system local routing");
        hotspot.vpn = true;
        check(!hotRoute.check().isEmpty(), "new VPN invalidates an unbound hotspot session");
        hotRoute.release();
        check(!hotRoute.prepare("").isEmpty() && hotspot.calls.isEmpty(), "hotspot with no exposed physical Network does not pretend to bypass VPN via cellular");

        Fake denied = new Fake(); denied.vpn = true; denied.reject = true; denied.current = "original";
        denied.available.add(candidate("wifi", true, false, "192.168.1.1", 24));
        LocalNetworkRoute deniedRoute = new LocalNetworkRoute(denied);
        check(!deniedRoute.prepare("").isEmpty() && "original".equals(denied.current), "a denied bind reports failure without overriding the prior route");
        denied.reject = false; deniedRoute.prepare(""); denied.reject = true;
        check(!deniedRoute.release().isEmpty() && deniedRoute.selected() != null, "failed cleanup retains ownership so remote mode can refuse to start");
        denied.reject = false; deniedRoute.release();
        denied.available.set(0, new LocalNetworkRoute.Candidate("wifi", "wlan-wifi", true, false, false, true,
                List.of(new LocalNetworkRoute.Subnet("192.168.1.1", 24))));
        check(!deniedRoute.prepare("").isEmpty(), "Android blocked-network status fails explicitly");
        check(new LocalNetworkRoute.Subnet("10.1.2.3", 32).broadcast() == null, "do not invent directed broadcast for /32");
        for (String bad : Arrays.asList("localhost", "1.2.3", "1.2.3.999", "1.2.3.-1")) {
            boolean rejected = false;
            try { LocalNetworkRoute.ipv4(bad); } catch (IllegalArgumentException e) { rejected = true; }
            check(rejected, "no DNS lookup or malformed target: " + bad);
        }
        System.out.println("ANDROID LAN ROUTE: " + checks + " checks passed");
    }
}
