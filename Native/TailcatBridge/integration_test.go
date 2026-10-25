package tailcatbridge

import (
	"bufio"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/tailscale/tailcat"
	"tailscale.com/types/key"
)

// Opt in explicitly: this uses a public bootstrap relay with only ephemeral,
// synthetic test identities and payloads. It is not a production-fleet probe.
func TestWireGuardRoundTrip(t *testing.T) {
	if os.Getenv("PORTDECK_TAILCAT_INTEGRATION") != "1" {
		t.Skip("set PORTDECK_TAILCAT_INTEGRATION=1 to exercise WireGuard and relay bootstrap")
	}
	clientKey := key.NewNode()
	server := &tailcat.Server{
		Logf:           func(string, ...any) {},
		AllowedClients: []key.NodePublic{clientKey.Public()},
		OnTCP: func(port uint16) func(net.Conn) {
			if port != ingressPort {
				return nil
			}
			return func(c net.Conn) {
				defer c.Close()
				c.SetDeadline(time.Now().Add(20 * time.Second))
				req, err := http.ReadRequest(bufio.NewReader(c))
				if err != nil {
					return
				}
				defer req.Body.Close()
				body := `{"status":"ok","name":"Synthetic PortOS","authRequired":true}`
				response := &http.Response{StatusCode: 200, ProtoMajor: 1, ProtoMinor: 1,
					Header: http.Header{"Content-Type": []string{"application/json"}},
					Body:   io.NopCloser(strings.NewReader(body)), ContentLength: int64(len(body)), Close: true}
				response.Write(c)
			}
		},
	}
	if err := server.Start(); err != nil {
		t.Fatal("could not start synthetic Tailcat server")
	}
	defer server.Close()
	k, _ := clientKey.MarshalText()
	tunnel, err := NewTunnel(string(server.TailcatAddr()), string(k), "http://127.0.0.1:5565")
	if err != nil {
		t.Fatal("could not create client tunnel")
	}
	defer tunnel.Close()
	req, _ := http.NewRequest(http.MethodGet, tunnel.localURL()+"/api/system/health", nil)
	req.Header.Set(authHeader, tunnel.Token())
	response, err := (&http.Client{Timeout: 25 * time.Second}).Do(req)
	if err != nil {
		t.Fatal("synthetic encrypted round trip failed")
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if response.StatusCode != 200 || !strings.Contains(string(body), "Synthetic PortOS") {
		t.Fatal("synthetic encrypted health response did not arrive")
	}
}
