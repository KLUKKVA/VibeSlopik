package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func call(t *testing.T, client *http.Client, method, url string, body any, headers map[string]string) *http.Response {
	t.Helper()
	var data []byte
	if body != nil {
		data, _ = json.Marshal(body)
	}
	req, _ := http.NewRequest(method, url, bytes.NewReader(data))
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	response, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return response
}

func decode(t *testing.T, response *http.Response) map[string]any {
	t.Helper()
	defer response.Body.Close()
	var value map[string]any
	if err := json.NewDecoder(response.Body).Decode(&value); err != nil {
		t.Fatal(err)
	}
	return value
}

func registerHost(t *testing.T, server *httptest.Server) {
	t.Helper()
	response := call(t, server.Client(), http.MethodPost, server.URL+"/v1/hosts/register", map[string]string{
		"hostId": "host", "hostSecret": "secret", "clientToken": "token",
	}, map[string]string{"X-VibeSlopik-Admin-Key": "admin"})
	if response.StatusCode != http.StatusOK {
		t.Fatalf("register: %d: %v", response.StatusCode, decode(t, response))
	}
	response.Body.Close()
}

func TestRegisterAndHealth(t *testing.T) {
	r, err := newRelay(filepath.Join(t.TempDir(), "state.json"), "admin")
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(r)
	defer server.Close()
	response := call(t, server.Client(), "POST", server.URL+"/v1/hosts/register", map[string]string{"hostId": "host", "hostSecret": "secret", "clientToken": "token"}, map[string]string{"X-VibeSlopik-Admin-Key": "admin"})
	if response.StatusCode != 200 {
		t.Fatalf("register: %d", response.StatusCode)
	}
	response.Body.Close()
	response = call(t, server.Client(), "GET", server.URL+"/healthz", nil, nil)
	if response.StatusCode != 200 {
		t.Fatalf("health: %d", response.StatusCode)
	}
	response.Body.Close()
}

func TestAuthenticationAndValidation(t *testing.T) {
	r, _ := newRelay(filepath.Join(t.TempDir(), "state.json"), "admin")
	server := httptest.NewServer(r)
	defer server.Close()

	response := call(t, server.Client(), http.MethodPost, server.URL+"/v1/hosts/register", map[string]string{"hostId": "bad/id", "hostSecret": "s", "clientToken": "t"}, map[string]string{"X-VibeSlopik-Admin-Key": "admin"})
	if response.StatusCode != http.StatusBadRequest {
		t.Fatalf("invalid id: %d", response.StatusCode)
	}
	response.Body.Close()
	response = call(t, server.Client(), http.MethodPost, server.URL+"/v1/hosts/register", map[string]string{"hostId": "host", "hostSecret": "s", "clientToken": "t"}, nil)
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("admin auth: %d", response.StatusCode)
	}
	response.Body.Close()
	registerHost(t, server)
	response = call(t, server.Client(), http.MethodGet, server.URL+"/v1/client/host/api/capabilities", nil, map[string]string{"Authorization": "Bearer wrong"})
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("client auth: %d", response.StatusCode)
	}
	response.Body.Close()
}

func TestBodyLimitAndTrailingJSON(t *testing.T) {
	r, _ := newRelay(filepath.Join(t.TempDir(), "state.json"), "admin")
	request := httptest.NewRequest(http.MethodPost, "/v1/hosts/register", strings.NewReader(`{} {}`))
	request.Header.Set("X-VibeSlopik-Admin-Key", "admin")
	recorder := httptest.NewRecorder()
	r.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("trailing JSON: %d", recorder.Code)
	}

	request = httptest.NewRequest(http.MethodPost, "/v1/hosts/register", io.NopCloser(strings.NewReader("{}")))
	request.ContentLength = maxBody + 1
	request.Header.Set("X-VibeSlopik-Admin-Key", "admin")
	recorder = httptest.NewRecorder()
	r.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("body limit: %d", recorder.Code)
	}
}

func TestRoundTripPreservesQuery(t *testing.T) {
	r, _ := newRelay(filepath.Join(t.TempDir(), "state.json"), "admin")
	server := httptest.NewServer(r)
	defer server.Close()
	registerHost(t, server)

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		response := call(t, server.Client(), http.MethodGet, server.URL+"/v1/client/host/api/test?one=1&two=2", nil, map[string]string{"Authorization": "Bearer token"})
		if response.StatusCode != http.StatusCreated {
			t.Errorf("client response: %d", response.StatusCode)
		}
		response.Body.Close()
	}()

	var item map[string]any
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		response := call(t, server.Client(), http.MethodGet, server.URL+"/v1/host/host/poll", nil, map[string]string{"X-VibeSlopik-Host-Secret": "secret"})
		payload := decode(t, response)
		if payload["request"] != nil {
			item = payload["request"].(map[string]any)
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if item == nil || item["query"] != "?one=1&two=2" {
		t.Fatalf("query not preserved: %#v", item)
	}
	response := call(t, server.Client(), http.MethodPost, server.URL+"/v1/host/host/reply", map[string]any{"requestId": item["requestId"], "response": map[string]any{"status": 201, "body": map[string]any{"ok": true}}}, map[string]string{"X-VibeSlopik-Host-Secret": "secret"})
	if response.StatusCode != http.StatusOK {
		t.Fatalf("reply: %d", response.StatusCode)
	}
	response.Body.Close()
	wg.Wait()
}

func TestCancelledClientIsRemoved(t *testing.T) {
	r, _ := newRelay(filepath.Join(t.TempDir(), "state.json"), "admin")
	server := httptest.NewServer(r)
	defer server.Close()
	registerHost(t, server)

	ctx, cancel := context.WithCancel(context.Background())
	request, _ := http.NewRequestWithContext(ctx, http.MethodGet, server.URL+"/v1/client/host/api/test", nil)
	request.Header.Set("Authorization", "Bearer token")
	done := make(chan struct{})
	go func() { _, _ = server.Client().Do(request); close(done) }()
	time.Sleep(20 * time.Millisecond)
	cancel()
	<-done
	time.Sleep(20 * time.Millisecond)
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.waiters) != 0 || len(r.queues["host"]) != 0 {
		t.Fatalf("cancelled request leaked: waiters=%d queue=%d", len(r.waiters), len(r.queues["host"]))
	}
}

func TestStateRecoveryFromBackup(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state.json")
	r, _ := newRelay(path, "admin")
	r.state.Hosts["first"] = &hostRecord{HostSecret: "a", ClientToken: "b"}
	if err := r.saveLocked(); err != nil {
		t.Fatal(err)
	}
	r.state.Hosts["second"] = &hostRecord{HostSecret: "c", ClientToken: "d"}
	if err := r.saveLocked(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("broken"), 0600); err != nil {
		t.Fatal(err)
	}
	recovered, err := newRelay(path, "admin")
	if err != nil {
		t.Fatal(err)
	}
	if recovered.state.Hosts["first"] == nil {
		t.Fatal("backup state was not recovered")
	}
}

func TestQueueLimitRejectsWithoutLeakingWaiter(t *testing.T) {
	r, _ := newRelay(filepath.Join(t.TempDir(), "state.json"), "admin")
	r.state.Hosts["host"] = &hostRecord{HostSecret: "secret", ClientToken: "token"}
	r.queues["host"] = make([]relayRequest, 128)
	request := httptest.NewRequest(http.MethodGet, "/v1/client/host/api/home", nil)
	request.Header.Set("Authorization", "Bearer token")
	recorder := httptest.NewRecorder()
	r.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusTooManyRequests {
		t.Fatalf("queue limit: %d", recorder.Code)
	}
	if len(r.waiters) != 0 || len(r.queues["host"]) != 128 {
		t.Fatalf("busy request changed relay state")
	}
}

func TestLateOrDuplicateReplyReturnsNotFound(t *testing.T) {
	r, _ := newRelay(filepath.Join(t.TempDir(), "state.json"), "admin")
	r.state.Hosts["host"] = &hostRecord{HostSecret: "secret", ClientToken: "token"}
	request := httptest.NewRequest(http.MethodPost, "/v1/host/host/reply", strings.NewReader(`{"requestId":"already-finished","response":{"status":200,"body":{"ok":true}}}`))
	request.Header.Set("X-VibeSlopik-Host-Secret", "secret")
	recorder := httptest.NewRecorder()
	r.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusNotFound {
		t.Fatalf("late reply: %d", recorder.Code)
	}
}

func TestGracefulCloseWakesPendingClients(t *testing.T) {
	r, _ := newRelay(filepath.Join(t.TempDir(), "state.json"), "admin")
	waiter := make(chan hostReply, 1)
	r.waiters["pending"] = waiter
	r.queues["host"] = []relayRequest{{RequestID: "pending"}}
	r.close()
	select {
	case response := <-waiter:
		if response.Status != http.StatusServiceUnavailable {
			t.Fatalf("shutdown status: %d", response.Status)
		}
	case <-time.After(time.Second):
		t.Fatal("graceful close did not wake client")
	}
	if len(r.waiters) != 0 || len(r.queues) != 0 {
		t.Fatal("graceful close leaked state")
	}
}
