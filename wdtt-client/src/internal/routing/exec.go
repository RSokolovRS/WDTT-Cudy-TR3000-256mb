package routing

import (
	"fmt"
	"os/exec"

	"github.com/wdtt-openwrt/wdtt-client/internal/config"
)

const routingScript = "/usr/libexec/wdtt/routing"

// Start применяет selective routing (nft sets + dnsmasq nftset + policy routing).
func Start(iface string, cfg *config.Settings) error {
	if !cfg.IsSelective() {
		return Stop()
	}
	cmd := exec.Command(routingScript, "start", iface)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("routing start: %w — %s", err, string(out))
	}
	return nil
}

// Stop снимает правила selective routing.
func Stop() error {
	cmd := exec.Command(routingScript, "stop")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("routing stop: %w — %s", err, string(out))
	}
	return nil
}

// Reload перечитывает UCI и обновляет правила.
func Reload(iface string) error {
	cmd := exec.Command(routingScript, "reload", iface)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("routing reload: %w — %s", err, string(out))
	}
	return nil
}
