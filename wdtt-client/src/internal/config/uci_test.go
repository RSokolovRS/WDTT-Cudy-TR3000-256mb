package config

import "testing"

func TestSanitizeDeviceID(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"openwrt-a1b2c3d4e5f6\n", "openwrt-a1b2c3d4e5f6"},
		{"  router.home_1  ", "router.home_1"},
		// '|' разделяет поля в GETCONF/AUTH — символ обязан вырезаться
		{"dev|ice", "device"},
		{"пусто", ""},
		{"", ""},
	}
	for _, c := range cases {
		if got := sanitizeDeviceID(c.in); got != c.want {
			t.Errorf("sanitizeDeviceID(%q) = %q, ожидалось %q", c.in, got, c.want)
		}
	}
}

func TestSanitizeDeviceIDLimit(t *testing.T) {
	long := ""
	for i := 0; i < 200; i++ {
		long += "a"
	}
	if got := len(sanitizeDeviceID(long)); got != 64 {
		t.Errorf("длина = %d, ожидалось 64", got)
	}
}

func TestDeriveDeviceIDNotEmpty(t *testing.T) {
	// На любой машине должен получиться непустой стабильный ID: MAC, machine-id
	// или фоллбэк openwrt-wdtt.
	if id := deriveDeviceID(); id == "" {
		t.Fatal("deriveDeviceID вернул пустую строку")
	}
}

func TestCollectHashesSlotsAndLegacy(t *testing.T) {
	got := collectHashes(map[string]string{
		"hash1":  "https://vk.com/call/join/aaa111",
		"hash2":  "bbb222",
		"hash3":  "",
		"hashes": "aaa111,ccc333",
	})
	if len(got) != 3 {
		t.Fatalf("ожидалось 3 хеша, получили %v", got)
	}
	if got[0] != "aaa111" || got[1] != "bbb222" || got[2] != "ccc333" {
		t.Fatalf("порядок/нормализация: %v", got)
	}
}

func TestDeriveDeviceIDStable(t *testing.T) {
	if first, second := deriveDeviceID(), deriveDeviceID(); first != second {
		t.Errorf("ID нестабилен: %q != %q", first, second)
	}
}
