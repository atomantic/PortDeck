package tailcatbridge

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/tailscale/tailcat"
	"tailscale.com/tailcfg"
	"tailscale.com/types/key"
)

func fixtureAddress() tailcat.ConnInfo {
	return tailcat.ConnInfo{
		ServerPublic:      tailcat.NodePublic{NodePublic: key.NewNode().Public()},
		ServerDiscoPublic: tailcat.DiscoPublic{DiscoPublic: key.NewDisco().Public()},
		PresharedKey:      tailcat.NewPresharedKey(),
		Region:            []*tailcfg.DERPRegion{{RegionID: 901, Nodes: []*tailcfg.DERPNode{{Name: "test", RegionID: 901, HostName: "relay.example.invalid"}}}},
	}
}

func TestAddressRequiresPSKFullRelayAndSecureTLS(t *testing.T) {
	ci := fixtureAddress()
	if _, err := InspectAddress(string(ci.Addr())); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		edit func(*tailcat.ConnInfo)
	}{
		{"no psk", func(c *tailcat.ConnInfo) { c.PresharedKey = tailcat.PresharedKey{} }},
		{"short address", func(c *tailcat.ConnInfo) { c.Region = nil; c.RegionID = 901 }},
		{"insecure relay", func(c *tailcat.ConnInfo) { c.Region[0].Nodes[0].InsecureForTests = true }},
		{"missing disco", func(c *tailcat.ConnInfo) { c.ServerDiscoPublic = tailcat.DiscoPublic{} }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ci := fixtureAddress()
			tc.edit(&ci)
			if _, err := InspectAddress(string(ci.Addr())); err == nil {
				t.Fatal("accepted unsafe address")
			}
		})
	}
	if _, err := InspectAddress("tcINVALID-test-only"); err == nil {
		t.Fatal("accepted malformed address")
	}
}

func testProxy(t *testing.T, handler http.Handler) (*Tunnel, *atomic.Int32) {
	t.Helper()
	remote := httptest.NewServer(handler)
	t.Cleanup(remote.Close)
	var dials atomic.Int32
	tunnel, err := newTunnel("http://127.0.0.1:5565", func(ctx context.Context, _, _ string) (net.Conn, error) {
		dials.Add(1)
		return (&net.Dialer{}).DialContext(ctx, "tcp", remote.Listener.Addr().String())
	}, func() error { return nil })
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(tunnel.Close)
	return tunnel, &dials
}

func proxyRequest(t *testing.T, tunnel *Tunnel, path string, configure func(*http.Request)) *http.Response {
	t.Helper()
	r, _ := http.NewRequest(http.MethodPost, tunnel.localURL()+path, strings.NewReader("private capture"))
	r.Header.Set(authHeader, tunnel.Token())
	if configure != nil {
		configure(r)
	}
	c := &http.Client{Timeout: 3 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := c.Do(r)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}

func TestLocalAdmissionAndFixedDestination(t *testing.T) {
	tunnel, dials := testProxy(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != "127.0.0.1:5565" || r.Header.Get(authHeader) != "" {
			t.Error("wrong target or leaked local credential")
		}
		if _, err := r.Cookie(authCookie); err == nil {
			t.Error("leaked proxy cookie")
		}
		if r.Header.Get("Authorization") != "Basic test-only" {
			t.Error("lost instance authentication")
		}
		if r.Header.Get("Origin") != "http://127.0.0.1:5565" {
			t.Error("wrong remote origin")
		}
		body, _ := io.ReadAll(r.Body)
		w.Write(body)
	}))
	for _, mutation := range []func(*http.Request){
		func(r *http.Request) { r.Header.Del(authHeader) },
		func(r *http.Request) { r.Host = "attacker.example" },
		func(r *http.Request) { r.Header.Set("Origin", "https://attacker.example") },
		func(r *http.Request) { r.Method = http.MethodConnect },
	} {
		resp := proxyRequest(t, tunnel, "/api/system/health", mutation)
		if resp.StatusCode != 403 {
			t.Fatalf("admission returned %d", resp.StatusCode)
		}
	}
	if dials.Load() != 0 {
		t.Fatal("unauthorized request reached remote")
	}
	resp := proxyRequest(t, tunnel, "/api/brain", func(r *http.Request) {
		r.Header.Set("Authorization", "Basic test-only")
		r.Header.Set("Origin", tunnel.localURL())
		r.AddCookie(&http.Cookie{Name: authCookie, Value: tunnel.Token()})
	})
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 || string(body) != "private capture" {
		t.Fatal("failed to forward body")
	}
}

func TestRedirectCannotEscapeAndErrorsAreRedacted(t *testing.T) {
	for _, location := range []string{"http://attacker.example/leak", "//attacker.example/leak", "https://127.0.0.1:5565/leak"} {
		t.Run(location, func(t *testing.T) {
			tunnel, _ := testProxy(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Location", location)
				w.WriteHeader(307)
			}))
			resp := proxyRequest(t, tunnel, "/api/action", nil)
			if resp.StatusCode != 502 || resp.Header.Get("Location") != "" {
				t.Fatal("cross-origin redirect escaped")
			}
		})
	}
	tunnel, _ := testProxy(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Add("Set-Cookie", authCookie+"=attacker")
		w.Header().Set("Location", "http://127.0.0.1:5565/next")
		w.WriteHeader(307)
	}))
	resp := proxyRequest(t, tunnel, "/api/action", nil)
	if resp.Header.Get("Location") != tunnel.localURL()+"/next" || len(resp.Cookies()) != 0 {
		t.Fatal("unsafe same-origin rewrite")
	}
}

func TestRelativeRedirectUsesTheCurrentRequestPath(t *testing.T) {
	for _, tc := range []struct{ location, expected string }{
		{"next", "/api/group/next"},
		{"?page=2", "/api/group/item?page=2"},
		{"#section", "/api/group/item#section"},
	} {
		t.Run(tc.location, func(t *testing.T) {
			tunnel, _ := testProxy(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Location", tc.location)
				w.WriteHeader(307)
			}))
			resp := proxyRequest(t, tunnel, "/api/group/item", nil)
			if resp.StatusCode != 307 || resp.Header.Get("Location") != tunnel.localURL()+tc.expected {
				t.Fatal("relative redirect lost the current request path")
			}
		})
	}
}

func TestHTTPSDoesNotTrustSelfSignedCertificates(t *testing.T) {
	remote := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { t.Error("untrusted request reached handler") }))
	defer remote.Close()
	remote.Config.ErrorLog = nil
	tunnel, err := newTunnel("https://portos.example.invalid:5565", func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "tcp", remote.Listener.Addr().String())
	}, func() error { return nil })
	if err != nil {
		t.Fatal(err)
	}
	defer tunnel.Close()
	resp := proxyRequest(t, tunnel, "/api/system/health", nil)
	if resp.StatusCode != 502 {
		t.Fatalf("untrusted TLS returned %d", resp.StatusCode)
	}
}

type pausedClient struct {
	started   chan struct{}
	cancelled chan struct{}
	release   chan struct{}
	closed    atomic.Bool
}

func (c *pausedClient) DialTCPPort(ctx context.Context, _ uint16) (net.Conn, error) {
	close(c.started)
	<-ctx.Done()
	close(c.cancelled)
	<-c.release
	return nil, ctx.Err()
}
func (c *pausedClient) Close() error { c.closed.Store(true); return nil }

func TestCloseCancelsAndDrainsLazyDialBeforeClosingClient(t *testing.T) {
	client := &pausedClient{started: make(chan struct{}), cancelled: make(chan struct{}), release: make(chan struct{})}
	dialer := newClientDialer(client)
	dialDone := make(chan struct{})
	go func() { defer close(dialDone); dialer.dial(context.Background(), "tcp", "ignored") }()
	<-client.started
	closed := make(chan struct{})
	go func() { defer close(closed); dialer.close() }()
	select {
	case <-client.cancelled:
	case <-time.After(time.Second):
		t.Fatal("shutdown did not cancel dial")
	}
	if client.closed.Load() {
		t.Error("client closed before admitted dial returned")
	}
	close(client.release)
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("shutdown did not finish")
	}
	<-dialDone
	if !client.closed.Load() {
		t.Fatal("client engine was not closed")
	}
	if _, err := dialer.dial(context.Background(), "tcp", "ignored"); err == nil {
		t.Fatal("accepted dial after shutdown")
	}
	if err := dialer.close(); err != nil {
		t.Fatal(err)
	}
}

func TestWebSocketUpgradeAndClose(t *testing.T) {
	tunnel, _ := testProxy(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, rw, err := w.(http.Hijacker).Hijack()
		if err != nil {
			return
		}
		defer conn.Close()
		rw.WriteString("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
		rw.Flush()
		io.Copy(conn, conn)
	}))
	c, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", fmt.Sprint(tunnel.Port())), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(3 * time.Second))
	fmt.Fprintf(c, "GET /remote-desktop/websockify HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nCookie: %s=%s\r\n\r\n", tunnel.Port(), authCookie, tunnel.Token())
	reader := bufio.NewReader(c)
	response, err := http.ReadResponse(reader, nil)
	if err != nil || response.StatusCode != 101 {
		t.Fatalf("upgrade: %v", err)
	}
	if _, err := c.Write([]byte("echo")); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, 4)
	if _, err := io.ReadFull(reader, got); err != nil || string(got) != "echo" {
		t.Fatalf("upgrade did not carry bytes: %v", err)
	}
	tunnel.Close()
	if _, err := reader.ReadByte(); err == nil {
		t.Fatal("WebSocket survived disconnect")
	}
	tunnel.Close()
}
