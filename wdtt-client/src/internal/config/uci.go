package config

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

const DefaultConfigPath = "/etc/config/wdtt"

// RoutingMode — режим маршрутизации трафика.
type RoutingMode string

const (
	RoutingFull      RoutingMode = "full"
	RoutingSelective RoutingMode = "selective"
)

// Rule — секция маршрутизации (аналог секции Podkop).
type Rule struct {
	Name      string
	Enabled   bool
	Type      string // route | exclusion
	Domains   []string
	Subnets   []string
	SourceIPs []string // fully_routed_ips — весь трафик устройства
	ListURL   string   // URL списка доменов (по одному на строку)
}

// Settings — параметры из UCI /etc/config/wdtt.
type Settings struct {
	Enabled              bool
	Peer                 string
	Password             string
	Hashes               []string
	Workers              int
	MTU                  int
	Listen               string
	TurnHost             string
	TurnPort             string
	CaptchaMode          string
	VKAuthMode           string
	DeviceID             string
	Iface                string
	RoutingMode          RoutingMode
	RoutingExcludedIPs   []string
	Rules                []Rule
}

type uciSection struct {
	typ     string
	name    string
	options map[string]string
	lists   map[string][]string
}

func Load(path string) (*Settings, error) {
	if path == "" {
		path = DefaultConfigPath
	}
	sections, err := parseUCI(path)
	if err != nil {
		return nil, err
	}

	var globals *uciSection
	var rules []Rule

	for _, sec := range sections {
		switch sec.typ {
		case "globals":
			if sec.name == "globals" || globals == nil {
				globals = sec
			}
		case "rule":
			rules = append(rules, parseRule(sec))
		}
	}

	if globals == nil {
		return nil, fmt.Errorf("section globals not found in %s", path)
	}

	g := globals.options
	s := &Settings{
		Enabled:     g["enabled"] == "1",
		Peer:        strings.TrimSpace(g["peer"]),
		Password:    g["password"],
		Workers:     atoiDefault(g["workers"], 12),
		MTU:         atoiDefault(g["mtu"], 1380),
		Listen:      defaultString(g["listen"], "127.0.0.1:9000"),
		TurnHost:    strings.TrimSpace(g["turn_host"]),
		TurnPort:    strings.TrimSpace(g["turn_port"]),
		CaptchaMode: defaultString(g["captcha_mode"], "wv"),
		VKAuthMode:  defaultString(g["vk_auth_mode"], "vkcalls"),
		DeviceID:    defaultString(g["device_id"], ""),
		Iface:       defaultString(g["iface"], "wg-wdtt"),
		Rules:       rules,
	}

	// routing_mode: selective (default, как Podkop) | full
	switch strings.ToLower(strings.TrimSpace(g["routing_mode"])) {
	case "full":
		s.RoutingMode = RoutingFull
	default:
		s.RoutingMode = RoutingSelective
	}

	// legacy full_tunnel option
	if g["full_tunnel"] == "1" {
		s.RoutingMode = RoutingFull
	} else if g["full_tunnel"] == "0" {
		s.RoutingMode = RoutingSelective
	}

	s.RoutingExcludedIPs = append(s.RoutingExcludedIPs, globals.lists["routing_excluded_ip"]...)
	s.RoutingExcludedIPs = append(s.RoutingExcludedIPs, globals.lists["routing_excluded_ips"]...)

	for _, h := range strings.Split(g["hashes"], ",") {
		if h = normalizeHash(h); h != "" {
			s.Hashes = append(s.Hashes, h)
		}
	}
	for _, h := range strings.Split(g["hash"], ",") {
		if h = normalizeHash(h); h != "" {
			s.Hashes = append(s.Hashes, h)
		}
	}

	if s.DeviceID == "" {
		s.DeviceID = readMachineID()
	}

	return s, nil
}

func parseRule(sec *uciSection) Rule {
	r := Rule{
		Name:    sec.name,
		Enabled: sec.options["enabled"] != "0",
		Type:    defaultString(sec.options["type"], "route"),
		ListURL: strings.TrimSpace(sec.options["list_url"]),
	}
	r.Domains = append(r.Domains, sec.lists["domain"]...)
	r.Domains = append(r.Domains, sec.lists["domains"]...)
	r.Subnets = append(r.Subnets, sec.lists["subnet"]...)
	r.Subnets = append(r.Subnets, sec.lists["subnets"]...)
	r.SourceIPs = append(r.SourceIPs, sec.lists["source_ip"]...)
	r.SourceIPs = append(r.SourceIPs, sec.lists["fully_routed_ip"]...)
	return r
}

func parseUCI(path string) ([]*uciSection, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open uci config: %w", err)
	}
	defer f.Close()

	var sections []*uciSection
	var current *uciSection

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(line, "config ") {
			parts := strings.Fields(line)
			if len(parts) < 2 {
				continue
			}
			typ := strings.Trim(parts[1], "'\"")
			name := typ
			if len(parts) >= 3 {
				name = strings.Trim(parts[2], "'\"")
			}
			current = &uciSection{
				typ:     typ,
				name:    name,
				options: make(map[string]string),
				lists:   make(map[string][]string),
			}
			sections = append(sections, current)
			continue
		}

		if current == nil {
			continue
		}

		if strings.HasPrefix(line, "option ") {
			parts := strings.Fields(line)
			if len(parts) >= 3 {
				key := parts[1]
				val := strings.TrimSpace(strings.Join(parts[2:], " "))
				val = strings.Trim(val, "'\"")
				current.options[key] = val
			}
			continue
		}

		if strings.HasPrefix(line, "list ") {
			parts := strings.Fields(line)
			if len(parts) >= 3 {
				key := parts[1]
				val := strings.TrimSpace(strings.Join(parts[2:], " "))
				val = strings.Trim(val, "'\"")
				current.lists[key] = append(current.lists[key], val)
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read uci config: %w", err)
	}
	return sections, nil
}

func (s *Settings) Validate() error {
	if s.Peer == "" {
		return fmt.Errorf("peer is required")
	}
	if s.Password == "" {
		return fmt.Errorf("password is required")
	}
	if len(s.Hashes) == 0 {
		return fmt.Errorf("at least one VK hash is required")
	}
	if s.Workers < 3 {
		s.Workers = 3
	}
	if s.Workers > 108 {
		s.Workers = 108
	}
	if s.MTU <= 0 {
		s.MTU = 1380
	}
	if s.Iface == "" {
		s.Iface = "wg-wdtt"
	}
	return nil
}

func (s *Settings) IsSelective() bool {
	return s.RoutingMode == RoutingSelective
}

func normalizeHash(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if idx := strings.LastIndex(raw, "/join/"); idx >= 0 {
		raw = raw[idx+len("/join/"):]
	}
	if q := strings.IndexByte(raw, '?'); q >= 0 {
		raw = raw[:q]
	}
	return strings.Trim(raw, "/ ")
}

func defaultString(v, def string) string {
	if strings.TrimSpace(v) == "" {
		return def
	}
	return strings.TrimSpace(v)
}

func atoiDefault(v string, def int) int {
	v = strings.TrimSpace(v)
	if v == "" {
		return def
	}
	var n int
	_, err := fmt.Sscanf(v, "%d", &n)
	if err != nil || n <= 0 {
		return def
	}
	return n
}

func readMachineID() string {
	data, err := os.ReadFile("/etc/machine-id")
	if err != nil {
		data, err = os.ReadFile("/var/lib/dbus/machine-id")
	}
	if err != nil {
		return "openwrt-wdtt"
	}
	return strings.TrimSpace(string(data))
}
