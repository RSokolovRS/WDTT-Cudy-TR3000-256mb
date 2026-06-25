package wg

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
	"sync"
)

// RoutingMode определяет схему маршрутизации.
type RoutingMode string

const (
	ModeFull      RoutingMode = "full"
	ModeSelective RoutingMode = "selective"
)

// vkExcludeCIDRs — подсети VK/TURN/DNS, которые должны идти мимо туннеля.
var vkExcludeCIDRs = []string{
	"87.240.128.0/18",
	"87.240.192.0/19",
	"90.156.0.0/16",
	"93.186.224.0/21",
	"95.142.192.0/21",
	"95.163.0.0/16",
	"95.213.0.0/18",
	"155.212.192.0/20",
	"185.16.28.0/22",
	"194.67.64.0/18",
	"195.82.146.0/23",
	"213.180.193.0/24",
	"77.88.0.0/18",
	"8.8.8.0/24",
	"1.1.1.0/24",
}

var wgQuickOnlyFields = map[string]bool{
	"address": true, "dns": true, "mtu": true,
	"preup": true, "postup": true, "predown": true, "postdown": true,
	"saveconfig": true,
}

// Manager управляет WireGuard-интерфейсом на OpenWRT.
type Manager struct {
	iface  string
	mode   RoutingMode
	mu     sync.Mutex
	routes []string
}

func New(iface string) *Manager {
	if iface == "" {
		iface = "wg-wdtt"
	}
	return &Manager{iface: iface, mode: ModeSelective}
}

func (m *Manager) SetMode(mode RoutingMode) {
	m.mu.Lock()
	m.mode = mode
	m.mu.Unlock()
}

func (m *Manager) Apply(conf string, turnIPs []string) error {
	m.mu.Lock()
	mode := m.mode
	m.mu.Unlock()
	return m.ApplyWithMode(conf, turnIPs, mode)
}

func (m *Manager) ApplyWithMode(conf string, turnIPs []string, mode RoutingMode) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.mode = mode

	m.teardownLocked()

	addr, mtu, allowedIPs, wgConf := parseWGConfig(conf)
	if addr == "" {
		return fmt.Errorf("Address not found in WireGuard config")
	}

	tmp, err := os.CreateTemp("/tmp", "wdtt-wg-*.conf")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	if _, err := tmp.WriteString(wgConf); err != nil {
		tmp.Close()
		return err
	}
	tmp.Close()
	_ = os.Chmod(tmpName, 0o600)

	if err := run("ip", "link", "add", m.iface, "type", "wireguard"); err != nil {
		return fmt.Errorf("ip link add: %w", err)
	}
	if err := run("wg", "setconf", m.iface, tmpName); err != nil {
		_ = run("ip", "link", "del", m.iface)
		return fmt.Errorf("wg setconf: %w", err)
	}

	_ = run("ip", "addr", "flush", "dev", m.iface)
	if err := run("ip", "addr", "add", addr, "dev", m.iface); err != nil {
		m.teardownLocked()
		return fmt.Errorf("ip addr add: %w", err)
	}
	if mtu != "" {
		_ = run("ip", "link", "set", m.iface, "mtu", mtu)
	}
	if err := run("ip", "link", "set", m.iface, "up"); err != nil {
		m.teardownLocked()
		return fmt.Errorf("ip link set up: %w", err)
	}

	var routes []string
	gw := defaultGateway()
	if gw != "" {
		for _, ip := range turnIPs {
			cidr := ip + "/32"
			if run("ip", "route", "add", cidr, "via", gw) == nil {
				routes = append(routes, cidr)
			}
		}
		for _, cidr := range vkExcludeCIDRs {
			if run("ip", "route", "add", cidr, "via", gw) == nil {
				routes = append(routes, cidr)
			}
		}
		for _, dns := range localDNSServers() {
			cidr := dns + "/32"
			if run("ip", "route", "add", cidr, "via", gw) == nil {
				routes = append(routes, cidr)
			}
		}
	}

	// В режиме full — весь трафик через WG (как раньше).
	// В selective — маршруты задаёт /usr/libexec/wdtt/routing (policy routing).
	if mode == ModeFull {
		for _, cidr := range allowedIPs {
			if run("ip", "route", "add", cidr, "dev", m.iface) == nil {
				routes = append(routes, "dev:"+cidr)
			}
		}
	}

	m.routes = routes
	return nil
}

func (m *Manager) Teardown() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.teardownLocked()
}

func (m *Manager) teardownLocked() {
	for _, entry := range m.routes {
		if strings.HasPrefix(entry, "dev:") {
			cidr := strings.TrimPrefix(entry, "dev:")
			_ = run("ip", "route", "del", cidr, "dev", m.iface)
		} else {
			_ = run("ip", "route", "del", entry)
		}
	}
	m.routes = nil
	_ = run("ip", "link", "del", m.iface)
}

func (m *Manager) Iface() string { return m.iface }

func (m *Manager) Mode() RoutingMode {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.mode
}

func parseWGConfig(conf string) (addr, mtu string, allowedIPs []string, wgConf string) {
	var out strings.Builder
	scanner := bufio.NewScanner(strings.NewReader(conf))
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)
		parts := strings.SplitN(trimmed, "=", 2)
		if len(parts) == 2 {
			key := strings.ToLower(strings.TrimSpace(parts[0]))
			val := strings.TrimSpace(parts[1])
			switch key {
			case "address":
				addr = val
				continue
			case "mtu":
				mtu = val
				continue
			case "allowedips":
				for _, cidr := range strings.Split(val, ",") {
					if c := strings.TrimSpace(cidr); c != "" {
						allowedIPs = append(allowedIPs, c)
					}
				}
			default:
				if wgQuickOnlyFields[key] {
					continue
				}
			}
		}
		out.WriteString(line + "\n")
	}
	wgConf = out.String()
	return
}

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %v: %w — %s", name, args, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func defaultGateway() string {
	cmd := exec.Command("ip", "route", "show", "default")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	fields := strings.Fields(string(out))
	for i, f := range fields {
		if f == "via" && i+1 < len(fields) {
			return fields[i+1]
		}
	}
	return ""
}

func localDNSServers() []string {
	data, err := os.ReadFile("/tmp/resolv.conf.d/resolv.conf.auto")
	if err != nil {
		data, err = os.ReadFile("/etc/resolv.conf")
	}
	if err != nil {
		return nil
	}
	var result []string
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 || fields[0] != "nameserver" {
			continue
		}
		ip := net.ParseIP(fields[1])
		if ip == nil || ip.IsLoopback() {
			continue
		}
		result = append(result, fields[1])
	}
	return result
}
