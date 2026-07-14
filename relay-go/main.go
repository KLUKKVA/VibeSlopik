package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
)

const maxBody = 32 << 20

var identifierPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)

type hostRecord struct {
	HostSecret  string `json:"hostSecret"`
	ClientToken string `json:"clientToken"`
	Name        string `json:"name"`
	UpdatedAt   int64  `json:"updatedAt"`
}

type stateFile struct {
	Hosts map[string]*hostRecord `json:"hosts"`
}
type relayRequest struct {
	RequestID string `json:"requestId"`
	Method    string `json:"method"`
	Path      string `json:"path"`
	Query     string `json:"query"`
	Body      any    `json:"body"`
}
type hostReply struct {
	Status int `json:"status"`
	Body   any `json:"body"`
}

type relay struct {
	mu                  sync.Mutex
	state               stateFile
	statePath, adminKey string
	queues              map[string][]relayRequest
	waiters             map[string]chan hostReply
}

func newRelay(statePath, adminKey string) (*relay, error) {
	r := &relay{state: stateFile{Hosts: map[string]*hostRecord{}}, statePath: statePath, adminKey: adminKey, queues: map[string][]relayRequest{}, waiters: map[string]chan hostReply{}}
	loaded, err := loadState(statePath)
	if err != nil {
		backup, backupErr := loadState(statePath + ".bak")
		if backupErr != nil {
			return nil, fmt.Errorf("state and backup are unavailable: %w", err)
		}
		log.Printf("level=warning event=state_recovered source=backup")
		loaded = backup
	}
	if loaded == nil {
		backup, backupErr := loadState(statePath + ".bak")
		if backupErr == nil && backup != nil {
			log.Printf("level=warning event=state_recovered source=backup reason=primary_missing")
			loaded = backup
		}
	}
	if loaded != nil {
		r.state = *loaded
	}
	if r.state.Hosts == nil {
		r.state.Hosts = map[string]*hostRecord{}
	}
	return r, nil
}

func loadState(path string) (*stateFile, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var state stateFile
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("invalid state file %q: %w", filepath.Base(path), err)
	}
	return &state, nil
}

func (r *relay) saveLocked() error {
	if err := os.MkdirAll(filepath.Dir(r.statePath), 0700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(r.state, "", "  ")
	if err != nil {
		return err
	}
	tmp := r.statePath + ".tmp"
	file, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	if _, err = file.Write(data); err == nil {
		err = file.Sync()
	}
	if closeErr := file.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		_ = os.Remove(tmp)
		return err
	}
	if current, readErr := os.ReadFile(r.statePath); readErr == nil {
		if err = os.WriteFile(r.statePath+".bak", current, 0600); err != nil {
			_ = os.Remove(tmp)
			return err
		}
	}
	if err = os.Rename(tmp, r.statePath); err != nil {
		// Windows cannot replace an existing file with Rename.
		if removeErr := os.Remove(r.statePath); removeErr != nil && !errors.Is(removeErr, os.ErrNotExist) {
			_ = os.Remove(tmp)
			return err
		}
		err = os.Rename(tmp, r.statePath)
	}
	return err
}

func writeJSON(w http.ResponseWriter, code int, value any) {
	data, _ := json.Marshal(value)
	h := w.Header()
	h.Set("Content-Type", "application/json; charset=utf-8")
	h.Set("Cache-Control", "no-store")
	h.Set("Connection", "close")
	w.WriteHeader(code)
	_, _ = w.Write(data)
}
func readJSON(req *http.Request, value any) error {
	defer req.Body.Close()
	if req.ContentLength > maxBody {
		return fmt.Errorf("request body is too large")
	}
	decoder := json.NewDecoder(io.LimitReader(req.Body, maxBody+1))
	if err := decoder.Decode(value); err != nil && !errors.Is(err, io.EOF) {
		return fmt.Errorf("invalid JSON")
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return fmt.Errorf("invalid JSON")
	}
	return nil
}
func requestID() string { b := make([]byte, 16); _, _ = rand.Read(b); return hex.EncodeToString(b) }
func parts(path string) []string {
	var out []string
	for _, p := range strings.Split(path, "/") {
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func (r *relay) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	p := parts(req.URL.Path)
	if req.Method == http.MethodGet && len(p) == 1 && p[0] == "healthz" {
		r.mu.Lock()
		n := len(r.state.Hosts)
		r.mu.Unlock()
		writeJSON(w, 200, map[string]any{"ok": true, "name": "vibeslopik-relay", "hosts": n})
		return
	}
	if req.Method == http.MethodPost && strings.Join(p, "/") == "v1/hosts/register" {
		r.register(w, req)
		return
	}
	if len(p) >= 4 && p[0] == "v1" && p[1] == "host" {
		r.hostEndpoint(w, req, p[2], p[3])
		return
	}
	if len(p) >= 4 && p[0] == "v1" && p[1] == "client" {
		r.clientEndpoint(w, req, p[2], "/"+strings.Join(p[3:], "/"))
		return
	}
	writeJSON(w, 404, map[string]any{"ok": false, "error": "not found"})
}

func (r *relay) register(w http.ResponseWriter, req *http.Request) {
	if req.Header.Get("X-VibeSlopik-Admin-Key") != r.adminKey {
		writeJSON(w, 401, map[string]any{"ok": false, "error": "unauthorized"})
		return
	}
	var body struct {
		HostID      string `json:"hostId"`
		HostSecret  string `json:"hostSecret"`
		ClientToken string `json:"clientToken"`
		Name        string `json:"name"`
	}
	if err := readJSON(req, &body); err != nil {
		writeJSON(w, 400, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	if body.HostID == "" || body.HostSecret == "" || body.ClientToken == "" {
		writeJSON(w, 400, map[string]any{"ok": false, "error": "hostId, hostSecret and clientToken are required"})
		return
	}
	if !identifierPattern.MatchString(body.HostID) || len(body.HostSecret) > 512 || len(body.ClientToken) > 512 || len(body.Name) > 256 {
		writeJSON(w, 400, map[string]any{"ok": false, "error": "registration values are invalid or too long"})
		return
	}
	r.mu.Lock()
	r.state.Hosts[body.HostID] = &hostRecord{body.HostSecret, body.ClientToken, body.Name, time.Now().UnixMilli()}
	err := r.saveLocked()
	r.mu.Unlock()
	if err != nil {
		log.Printf("level=error event=registration_save_failed host=%q error=%q", body.HostID, err)
		writeJSON(w, 500, map[string]any{"ok": false, "error": "state could not be saved"})
		return
	}
	log.Printf("level=info event=host_registered host=%q", body.HostID)
	writeJSON(w, 200, map[string]any{"ok": true})
}

func (r *relay) hostEndpoint(w http.ResponseWriter, req *http.Request, id, action string) {
	r.mu.Lock()
	record := r.state.Hosts[id]
	authorized := record != nil && req.Header.Get("X-VibeSlopik-Host-Secret") == record.HostSecret
	if authorized {
		record.UpdatedAt = time.Now().UnixMilli()
	}
	if !authorized {
		r.mu.Unlock()
		writeJSON(w, 401, map[string]any{"ok": false, "error": "unauthorized"})
		return
	}
	if req.Method == http.MethodGet && action == "poll" {
		var item *relayRequest
		q := r.queues[id]
		if len(q) > 0 {
			value := q[0]
			item = &value
			r.queues[id] = q[1:]
		}
		r.mu.Unlock()
		writeJSON(w, 200, map[string]any{"ok": true, "request": item})
		return
	}
	r.mu.Unlock()
	if req.Method == http.MethodPost && action == "reply" {
		var body struct {
			RequestID string    `json:"requestId"`
			Response  hostReply `json:"response"`
		}
		if err := readJSON(req, &body); err != nil {
			writeJSON(w, 400, map[string]any{"ok": false, "error": err.Error()})
			return
		}
		if !identifierPattern.MatchString(body.RequestID) || body.Response.Status < 100 || body.Response.Status > 599 {
			writeJSON(w, 400, map[string]any{"ok": false, "error": "invalid requestId or response status"})
			return
		}
		r.mu.Lock()
		waiter := r.waiters[body.RequestID]
		if waiter != nil {
			delete(r.waiters, body.RequestID)
		}
		r.mu.Unlock()
		if waiter == nil {
			log.Printf("level=warning event=late_reply host=%q request=%q", id, body.RequestID)
			writeJSON(w, 404, map[string]any{"ok": false, "error": "request not found"})
			return
		}
		select {
		case waiter <- body.Response:
		default:
		}
		writeJSON(w, 200, map[string]any{"ok": true})
		return
	}
	writeJSON(w, 404, map[string]any{"ok": false, "error": "not found"})
}

func (r *relay) clientEndpoint(w http.ResponseWriter, req *http.Request, id, path string) {
	r.mu.Lock()
	record := r.state.Hosts[id]
	if record == nil || req.Header.Get("Authorization") != "Bearer "+record.ClientToken {
		r.mu.Unlock()
		writeJSON(w, 401, map[string]any{"ok": false, "error": "unauthorized"})
		return
	}
	r.mu.Unlock()
	var body any
	if req.Method == http.MethodPost {
		if err := readJSON(req, &body); err != nil {
			writeJSON(w, 400, map[string]any{"ok": false, "error": err.Error()})
			return
		}
	}
	idValue := requestID()
	waiter := make(chan hostReply, 1)
	query := ""
	if req.URL.RawQuery != "" {
		query = "?" + req.URL.RawQuery
	}
	item := relayRequest{RequestID: idValue, Method: req.Method, Path: path, Query: query, Body: body}
	r.mu.Lock()
	if len(r.queues[id]) >= 128 || len(r.waiters) >= 1024 {
		r.mu.Unlock()
		log.Printf("level=warning event=queue_busy host=%q", id)
		writeJSON(w, 429, map[string]any{"ok": false, "error": "relay is busy, retry later"})
		return
	}
	r.waiters[idValue] = waiter
	r.queues[id] = append(r.queues[id], item)
	r.mu.Unlock()
	timer := time.NewTimer(5 * time.Minute)
	defer timer.Stop()
	select {
	case response := <-waiter:
		if response.Status == 0 {
			response.Status = 502
		}
		writeJSON(w, response.Status, response.Body)
	case <-req.Context().Done():
		r.cancel(id, idValue)
		log.Printf("level=info event=client_cancelled host=%q request=%q", id, idValue)
	case <-timer.C:
		r.cancel(id, idValue)
		log.Printf("level=warning event=host_timeout host=%q request=%q", id, idValue)
		writeJSON(w, 504, map[string]any{"ok": false, "error": "host is offline or did not answer"})
	}
}

func (r *relay) cancel(hostID, id string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.waiters, id)
	q := r.queues[hostID]
	out := q[:0]
	for _, item := range q {
		if item.RequestID != id {
			out = append(out, item)
		}
	}
	r.queues[hostID] = out
}

func (r *relay) close() {
	r.mu.Lock()
	defer r.mu.Unlock()
	for id, waiter := range r.waiters {
		select {
		case waiter <- hostReply{Status: http.StatusServiceUnavailable, Body: map[string]any{"ok": false, "error": "relay is shutting down"}}:
		default:
		}
		delete(r.waiters, id)
	}
	r.queues = map[string][]relayRequest{}
}

func main() {
	check := flag.Bool("check", false, "validate that the relay binary can run")
	version := flag.Bool("version", false, "print version")
	flag.Parse()
	if *check {
		fmt.Println("VibeSlopik Relay: OK")
		return
	}
	if *version {
		fmt.Println("1.0.0")
		return
	}
	port := os.Getenv("VIBESLOPIK_RELAY_PORT")
	if port == "" {
		port = "8788"
	}
	key := os.Getenv("VIBESLOPIK_RELAY_ADMIN_KEY")
	if key == "" {
		log.Fatal("VIBESLOPIK_RELAY_ADMIN_KEY is required")
	}
	state := os.Getenv("VIBESLOPIK_RELAY_STATE")
	if state == "" {
		state = "./relay-state.json"
	}
	r, err := newRelay(state, key)
	if err != nil {
		log.Fatal(err)
	}
	server := &http.Server{Addr: ":" + port, Handler: r, ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 6 * time.Minute, WriteTimeout: 6 * time.Minute, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 16 << 10}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-stop
		log.Printf("level=info event=shutdown_started")
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := server.Shutdown(ctx); err != nil {
			log.Printf("level=error event=shutdown_failed error=%q", err)
		}
	}()
	log.Printf("level=info event=relay_started version=1.0.0 port=%s", port)
	err = server.ListenAndServe()
	r.close()
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
	log.Printf("level=info event=relay_stopped")
}
