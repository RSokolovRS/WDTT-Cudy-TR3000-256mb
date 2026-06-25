package daemon

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/wdtt-openwrt/wdtt-client/core"
	"github.com/wdtt-openwrt/wdtt-client/internal/captcha"
	"github.com/wdtt-openwrt/wdtt-client/internal/config"
	"github.com/wdtt-openwrt/wdtt-client/internal/routing"
	"github.com/wdtt-openwrt/wdtt-client/internal/status"
	"github.com/wdtt-openwrt/wdtt-client/internal/wg"
)

// Daemon — основной контроллер WDTT на OpenWRT.
type Daemon struct {
	version string
	status  *status.Manager
	wg      *wg.Manager
	cfg     *config.Settings

	mu      sync.Mutex
	core    *core.Core
	cancel  context.CancelFunc
	running bool
}

func New(version string) *Daemon {
	return &Daemon{
		version: version,
		status:  status.New(status.DefaultDir, version),
	}
}

func (d *Daemon) Run(ctx context.Context) error {
	cfg, err := config.Load("")
	if err != nil {
		return err
	}
	if !cfg.Enabled {
		d.status.SetRunning(false)
		log.Println("[WDTT] disabled in UCI, exiting")
		return nil
	}
	return d.runWithConfig(ctx, cfg)
}

func (d *Daemon) runWithConfig(ctx context.Context, cfg *config.Settings) error {
	if err := cfg.Validate(); err != nil {
		d.status.SetError(err)
		return err
	}

	d.mu.Lock()
	if d.running {
		d.mu.Unlock()
		return fmt.Errorf("already running")
	}
	d.running = true
	d.mu.Unlock()

	defer func() {
		d.mu.Lock()
		d.running = false
		d.mu.Unlock()
		d.stopCore()
		_ = routing.Stop()
		d.wg.Teardown()
		d.status.SetRunning(false)
	}()

	d.cfg = cfg
	d.wg = wg.New(cfg.Iface)
	if cfg.IsSelective() {
		d.wg.SetMode(wg.ModeSelective)
	} else {
		d.wg.SetMode(wg.ModeFull)
	}
	d.status.SetRunning(true)

	runCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		select {
		case s := <-sig:
			log.Printf("[WDTT] signal %v, stopping", s)
			cancel()
		case <-runCtx.Done():
		}
	}()

	logWriter := &statusLogWriter{mgr: d.status}
	log.SetOutput(io.MultiWriter(os.Stderr, logWriter))
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)

	coreCfg := core.Config{
		PeerAddr:    cfg.Peer,
		Password:    cfg.Password,
		Hashes:      cfg.Hashes,
		Listen:      cfg.Listen,
		TurnHost:    cfg.TurnHost,
		TurnPort:    cfg.TurnPort,
		DeviceID:    cfg.DeviceID,
		Workers:     cfg.Workers,
		CaptchaMode: cfg.CaptchaMode,
		MTU:         cfg.MTU,
	}

	c := core.New(coreCfg)
	events, err := c.Start()
	if err != nil {
		d.status.SetError(err)
		return err
	}

	d.mu.Lock()
	d.core = c
	d.cancel = cancel
	SetGlobal(d)
	d.mu.Unlock()

	defer func() {
		SetGlobal(nil)
		d.stopCore()
	}()

	go captcha.Watch(runCtx, status.DefaultDir, func(token string) {
		if err := d.SolveCaptcha(token); err != nil {
			log.Printf("[WDTT] captcha submit: %v", err)
		}
	})

	for {
		select {
		case ev, ok := <-events:
			if !ok {
				return nil
			}
			d.handleEvent(ev)
		case <-runCtx.Done():
			return nil
		}
	}
}

func (d *Daemon) handleEvent(ev core.Event) {
	switch ev.Type {
	case core.EventState:
		d.status.SetState(ev.Status)
	case core.EventStats:
		d.status.SetStats(ev.RxBytes, ev.TxBytes, ev.Workers)
	case core.EventLog:
		line := fmt.Sprintf("[%s] %s", ev.Level, ev.Message)
		d.status.AppendLog(line)
	case core.EventEvent:
		switch ev.Name {
		case "wg_config":
			mode := wg.ModeFull
			if d.cfg != nil && d.cfg.IsSelective() {
				mode = wg.ModeSelective
			}
			if err := d.wg.ApplyWithMode(ev.Data, d.turnIPs(), mode); err != nil {
				log.Printf("[WDTT] WireGuard apply failed: %v", err)
				d.status.SetError(err)
			} else {
				if d.cfg != nil && d.cfg.IsSelective() {
					if err := routing.Start(d.wg.Iface(), d.cfg); err != nil {
						log.Printf("[WDTT] selective routing failed: %v", err)
						d.status.SetError(err)
					}
				}
				d.status.SetWGApplied(true)
				d.status.SetState("connected")
				d.status.SetError(nil)
				log.Printf("[WDTT] WireGuard %s up (mode=%s)", d.wg.Iface(), mode)
			}
		case "captcha_required":
			parts := strings.SplitN(ev.Data, "|", 3)
			cap := &status.Captcha{Required: true}
			if len(parts) > 0 {
				cap.Mode = parts[0]
			}
			if len(parts) > 1 {
				cap.RedirectURI = parts[1]
			}
			if len(parts) > 2 {
				cap.Session = parts[2]
			}
			d.status.SetCaptcha(cap)
			d.status.SetState("captcha_required")
		}
	case core.EventError:
		d.status.SetError(fmt.Errorf("%s", ev.Message))
	}
}

func (d *Daemon) turnIPs() []string {
	d.mu.Lock()
	c := d.core
	d.mu.Unlock()
	if c == nil {
		return nil
	}
	return c.GetTurnIPs()
}

func (d *Daemon) stopCore() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cancel != nil {
		d.cancel()
		d.cancel = nil
	}
	if d.core != nil {
		d.core.Stop()
		d.core = nil
	}
}

// SolveCaptcha передаёт токен капчи в ядро (вызывается из rpcd/CLI).
func (d *Daemon) SolveCaptcha(token string) error {
	d.mu.Lock()
	c := d.core
	d.mu.Unlock()
	if c == nil {
		return fmt.Errorf("daemon is not running")
	}
	token = strings.TrimSpace(token)
	if token == "" {
		return fmt.Errorf("empty captcha token")
	}
	c.SolveCaptcha(token)
	d.status.SetCaptcha(nil)
	return nil
}

// StatusManager возвращает менеджер статуса.
func (d *Daemon) StatusManager() *status.Manager { return d.status }

type statusLogWriter struct {
	mgr *status.Manager
}

func (w *statusLogWriter) Write(p []byte) (int, error) {
	msg := strings.TrimRight(string(p), "\n")
	if msg != "" {
		w.mgr.AppendLog(msg)
	}
	return len(p), nil
}

// RunForeground — точка входа для procd.
func RunForeground(version string) int {
	ctx := context.Background()
	d := New(version)
	if err := d.Run(ctx); err != nil {
		log.Printf("[WDTT] fatal: %v", err)
		time.Sleep(2 * time.Second)
		return 1
	}
	return 0
}

// Global singleton for rpcd captcha submission.
var (
	globalMu sync.Mutex
	globalD  *Daemon
)

func SetGlobal(d *Daemon) {
	globalMu.Lock()
	globalD = d
	globalMu.Unlock()
}

func SubmitCaptcha(token string) error {
	globalMu.Lock()
	d := globalD
	globalMu.Unlock()
	if d == nil {
		return fmt.Errorf("wdtt daemon is not active")
	}
	return d.SolveCaptcha(token)
}
