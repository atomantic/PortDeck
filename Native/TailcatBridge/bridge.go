// Package tailcatbridge exposes a small, app-scoped Tailcat transport to Swift.
// It creates no TUN device, routes, exit node, or system VPN configuration.
package tailcatbridge

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/tailscale/tailcat"
	"tailscale.com/types/key"
)

const ingressPort = 5565
const authHeader = "X-PortDeck-Tunnel"
const authCookie = "PortDeckTunnel"

var errAddress = errors.New("Use the full, PSK-protected Tailcat address copied privately from PortOS")

// NewDeviceKey generates a private identity. The caller must put it in the
// device-only Keychain. Neither it nor the Tailcat capability belongs in a URL.
func NewDeviceKey() string {
	b, _ := key.NewNode().MarshalText()
	return string(b)
}

// PublicKey returns only the public half suitable for a server's --allow list.
func PublicKey(privateKey string) (string, error) {
	k, err := parsePrivateKey(privateKey)
	if err != nil {
		return "", err
	}
	return k.Public().String(), nil
}

func parsePrivateKey(value string) (key.NodePrivate, error) {
	var k key.NodePrivate
	if err := k.UnmarshalText([]byte(value)); err != nil || k.IsZero() {
		return k, errors.New("The saved Tailcat device identity is invalid")
	}
	return k, nil
}

// InspectAddress validates locally, without DNS, relay discovery, or dialing.
// Its JSON contains public information only. Reject short addresses so this
// client never silently fetches a third-party DERP map.
func InspectAddress(address string) (string, error) {
	ci, err := inspect(address)
	if err != nil {
		return "", err
	}
	var hosts []string
	for _, region := range ci.Region {
		for _, node := range region.Nodes {
			if !node.STUNOnly {
				hosts = append(hosts, node.HostName)
			}
		}
	}
	b, _ := json.Marshal(struct {
		PublicKey string   `json:"publicKey"`
		Relays    []string `json:"relays"`
	}{ci.ServerPublic.String(), hosts})
	return string(b), nil
}

func inspect(address string) (tailcat.ConnInfo, error) {
	if len(address) > 32768 || strings.TrimSpace(address) != address || !strings.HasPrefix(address, "tc") {
		return tailcat.ConnInfo{}, errAddress
	}
	ci, err := tailcat.ParseAddr(tailcat.Addr(address))
	if err != nil || ci.PresharedKey.IsZero() || ci.ServerPublic.IsZero() || ci.ServerDiscoPublic.IsZero() || len(ci.Region) == 0 {
		return tailcat.ConnInfo{}, errAddress
	}
	usable := false
	for _, region := range ci.Region {
		if region == nil || len(region.Nodes) == 0 {
			return tailcat.ConnInfo{}, errAddress
		}
		for _, node := range region.Nodes {
			if node == nil || node.InsecureForTests || node.HostName == "" {
				return tailcat.ConnInfo{}, errAddress
			}
			usable = usable || !node.STUNOnly
		}
	}
	if !usable {
		return tailcat.ConnInfo{}, errAddress
	}
	return ci, nil
}

// Tunnel is an authenticated loopback reverse proxy to precisely one PortOS
// ingress. The secret local token also protects WebKit subresources and upgrades.
type Tunnel struct {
	port      int64
	token     string
	server    *http.Server
	listener  net.Listener
	transport *http.Transport
	closePeer func() error
	mu        sync.Mutex
	conns     map[net.Conn]struct{}
	closed    bool
	closeOnce sync.Once
}

func (t *Tunnel) Port() int64   { return t.port }
func (t *Tunnel) Token() string { return t.token }

// NewTunnel pins the server keys embedded in address and restores a stable
// client key. Opening the local listener is not evidence of remote reachability;
// the caller must perform the usual PortOS health/authentication handshake.
// HTTPS uses Go's platform certificate verification and the supplied DNS name.
func NewTunnel(address, privateKey, origin string) (*Tunnel, error) {
	if _, err := inspect(address); err != nil {
		return nil, err
	}
	k, err := parsePrivateKey(privateKey)
	if err != nil {
		return nil, err
	}
	client := &tailcat.Client{
		Server: tailcat.Addr(address),
		Key:    k,
		// Tailcat diagnostics can contain capabilities and endpoints.
		Logf: func(string, ...any) {},
	}
	dialer := newClientDialer(client)
	t, err := newTunnel(origin, dialer.dial, dialer.close)
	if err != nil {
		dialer.close()
	}
	return t, err
}

func newTunnel(origin string, dial func(context.Context, string, string) (net.Conn, error), closePeer func() error) (*Tunnel, error) {
	target, err := url.Parse(origin)
	if err != nil || (target.Scheme != "http" && target.Scheme != "https") || target.Hostname() == "" ||
		target.Port() != "5565" || target.User != nil || target.RawQuery != "" || target.Fragment != "" ||
		(target.Path != "" && target.Path != "/") {
		return nil, errors.New("Tailcat must target the remote PortOS HTTP or HTTPS ingress on port 5565")
	}
	ln, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return nil, errors.New("Could not open the private local Tailcat connection")
	}
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		ln.Close()
		return nil, errors.New("Could not create the private local connection token")
	}
	t := &Tunnel{
		port:     int64(ln.Addr().(*net.TCPAddr).Port),
		token:    base64.RawURLEncoding.EncodeToString(secret),
		listener: ln, closePeer: closePeer, conns: make(map[net.Conn]struct{}),
	}
	localOrigin := "http://" + ln.Addr().String()
	t.transport = &http.Transport{
		Proxy: nil, DialContext: dial, ForceAttemptHTTP2: false,
		TLSHandshakeTimeout: 15 * time.Second, ResponseHeaderTimeout: 30 * time.Second,
		IdleConnTimeout: 30 * time.Second, MaxIdleConnsPerHost: 4,
	}
	proxy := &httputil.ReverseProxy{
		Transport: t.transport,
		ErrorLog:  log.New(io.Discard, "", 0),
		Rewrite: func(p *httputil.ProxyRequest) {
			p.SetURL(target)
			p.Out.Host = target.Host
			p.Out.Header.Del(authHeader)
			cookies := p.Out.Cookies()
			p.Out.Header.Del("Cookie")
			for _, cookie := range cookies {
				if cookie.Name != authCookie {
					p.Out.AddCookie(cookie)
				}
			}
			if p.In.Header.Get("Origin") != "" {
				p.Out.Header.Set("Origin", target.Scheme+"://"+target.Host)
			}
		},
		ModifyResponse: func(r *http.Response) error {
			if location := r.Header.Get("Location"); location != "" {
				u, err := url.Parse(location)
				if err != nil {
					return errors.New("redirect refused")
				}
				if r.Request == nil || r.Request.URL == nil {
					return errors.New("redirect refused")
				}
				u = r.Request.URL.ResolveReference(u)
				if u.User != nil || u.Scheme != target.Scheme || !strings.EqualFold(u.Host, target.Host) {
					return errors.New("redirect refused")
				}
				local, _ := url.Parse(localOrigin)
				u.Scheme, u.Host = local.Scheme, local.Host
				r.Header.Set("Location", u.String())
			}
			// Never let an upstream response replace the proxy's admission cookie.
			cookies := r.Cookies()
			r.Header.Del("Set-Cookie")
			for _, cookie := range cookies {
				if cookie.Name != authCookie {
					r.Header.Add("Set-Cookie", cookie.String())
				}
			}
			return nil
		},
		ErrorHandler: func(w http.ResponseWriter, _ *http.Request, _ error) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadGateway)
			io.WriteString(w, `{"error":"TAILCAT_UNREACHABLE","message":"The private Tailcat connection failed. Check the remote ingress, device approval, relay connectivity, and HTTPS certificate."}`)
		},
	}
	t.server = &http.Server{
		ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second,
		MaxHeaderBytes: 64 << 10, ErrorLog: log.New(io.Discard, "", 0),
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-store")
			w.Header().Set("Referrer-Policy", "no-referrer")
			token := r.Header.Get(authHeader)
			if token == "" {
				if cookie, err := r.Cookie(authCookie); err == nil {
					token = cookie.Value
				}
			}
			if r.Host != ln.Addr().String() || r.URL.IsAbs() || r.Method == http.MethodConnect ||
				(r.Header.Get("Origin") != "" && r.Header.Get("Origin") != localOrigin) ||
				subtle.ConstantTimeCompare([]byte(token), []byte(t.token)) != 1 {
				http.Error(w, "Private connection authorization required", http.StatusForbidden)
				return
			}
			proxy.ServeHTTP(w, r)
		}),
	}
	go t.server.Serve(&trackingListener{Listener: ln, tunnel: t})
	return t, nil
}

// Close also closes hijacked WebSocket connections, which http.Server.Close
// deliberately leaves open. It is safe to call repeatedly.
func (t *Tunnel) Close() {
	t.closeOnce.Do(func() {
		t.mu.Lock()
		t.closed = true
		var conns []net.Conn
		for c := range t.conns {
			conns = append(conns, c)
		}
		t.mu.Unlock()
		t.server.Close()
		for _, c := range conns {
			c.Close()
		}
		t.transport.CloseIdleConnections()
		t.closePeer()
	})
}

type trackingListener struct {
	net.Listener
	tunnel *Tunnel
}

func (l *trackingListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	l.tunnel.mu.Lock()
	defer l.tunnel.mu.Unlock()
	if l.tunnel.closed {
		c.Close()
		return nil, net.ErrClosed
	}
	tc := &trackedConn{Conn: c, tunnel: l.tunnel}
	l.tunnel.conns[tc] = struct{}{}
	return tc, nil
}

type trackedConn struct {
	net.Conn
	tunnel *Tunnel
}

func (c *trackedConn) Close() error {
	c.tunnel.mu.Lock()
	delete(c.tunnel.conns, c)
	c.tunnel.mu.Unlock()
	return c.Conn.Close()
}

// Keep strconv's port conversion on the Go side out of the mobile API surface.
func (t *Tunnel) localURL() string { return "http://127.0.0.1:" + strconv.FormatInt(t.port, 10) }

type tailcatClient interface {
	DialTCPPort(context.Context, uint16) (net.Conn, error)
	Close() error
}

// An unused upstream Client can initialize itself after Close. Gate new dials
// and drain admitted dials before closing its engine to prevent late startup.
type clientDialer struct {
	client    tailcatClient
	lifetime  context.Context
	cancel    context.CancelFunc
	mu        sync.Mutex
	closed    bool
	dials     sync.WaitGroup
	closeOnce sync.Once
	closeErr  error
}

func newClientDialer(client tailcatClient) *clientDialer {
	ctx, cancel := context.WithCancel(context.Background())
	return &clientDialer{client: client, lifetime: ctx, cancel: cancel}
}

func (d *clientDialer) dial(ctx context.Context, _, _ string) (net.Conn, error) {
	d.mu.Lock()
	if d.closed {
		d.mu.Unlock()
		return nil, net.ErrClosed
	}
	d.dials.Add(1)
	d.mu.Unlock()
	defer d.dials.Done()
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	stop := context.AfterFunc(d.lifetime, cancel)
	defer stop()
	defer cancel()
	if d.lifetime.Err() != nil {
		return nil, net.ErrClosed
	}
	return d.client.DialTCPPort(ctx, ingressPort)
}

func (d *clientDialer) close() error {
	d.closeOnce.Do(func() {
		d.mu.Lock()
		d.closed = true
		d.cancel()
		d.mu.Unlock()
		d.dials.Wait()
		d.closeErr = d.client.Close()
	})
	return d.closeErr
}
